#!/bin/bash
# pve-mods-apt-hook.sh - warn when a package upgrade overwrites the pve-mods GUI files.
#
# Installs:
#   /usr/local/sbin/pve-mods-check        compares installed files with /etc/pve-mods/installed.sha256
#   /etc/apt/apt.conf.d/99pve-mods-check  runs it after every dpkg run (apt, GUI updates, unattended)
#
# The manifest /etc/pve-mods/installed.sha256 is written by pve9-install.sh after a successful
# install and removed by `pve9-install.sh --restore`. No manifest means the check stays silent.
#
# On a mismatch the check:
#   - prints a warning in the apt output (stderr)
#   - logs it: journalctl -t pve-mods
#   - emails root ONCE per distinct change (state in /var/lib/pve-mods/last-alert)
# It never fails or blocks apt.
#
# Usage (as root):
#     bash pve-mods-apt-hook.sh install     # install or refresh the hook
#     bash pve-mods-apt-hook.sh status      # show what's installed + run the check now
#     bash pve-mods-apt-hook.sh test        # simulate a reverted file (no mail, no state change)
#     bash pve-mods-apt-hook.sh uninstall   # remove the hook (keeps the manifest)

set -uo pipefail
R="${HOOKROOT:-}"                                   # test prefix only; empty on the real host
CHECK="$R/usr/local/sbin/pve-mods-check"
APTCONF="$R/etc/apt/apt.conf.d/99pve-mods-check"
MANIFEST="$R/etc/pve-mods/installed.sha256"

if [ -z "$R" ] && [ "$(id -u)" -ne 0 ]; then echo "ERROR: run as root" >&2; exit 1; fi

write_check() {
    mkdir -p "$(dirname "$CHECK")"
    cat > "$CHECK" <<'EOF'
#!/bin/sh
# pve-mods-check - called by /etc/apt/apt.conf.d/99pve-mods-check after every dpkg run.
# Warns when a package upgrade has replaced the modified Proxmox GUI files (pve-mods).
# Installed by /home/zitt/lmsensors/pve-mods-apt-hook.sh - see /home/zitt/lmsensors/HISTORY.md
M="${PVE_MODS_MANIFEST:-/etc/pve-mods/installed.sha256}"
STATE="${PVE_MODS_STATE:-/var/lib/pve-mods/last-alert}"
[ -r "$M" ] || exit 0
bad=$(sha256sum --quiet -c "$M" 2>/dev/null | sed -n 's/: FAILED.*$//p')
if [ -z "$bad" ]; then
    rm -f "$STATE" 2>/dev/null
    exit 0
fi
list=$(printf '%s\n' "$bad" | sed 's/^/    /')
msg="A package upgrade replaced these pve-mods (modified Proxmox GUI) files:
$list

The sensor / NVMe / Opt Life panels are gone until the mods are re-ported to the new version.
Runbook: /home/zitt/lmsensors/HISTORY.md  ->  'After the NEXT Proxmox upgrade'
Silence this until then: rm $M"
printf '\n*** pve-mods: %s\n\n' "$msg" >&2
# PVE_MODS_NOMAIL (used by status/test) = terminal output only: no log, no mail
[ -n "${PVE_MODS_NOMAIL:-}" ] && exit 0
logger -t pve-mods -p user.warning "package upgrade replaced: $(echo "$bad" | tr '\n' ' ')" 2>/dev/null
key=$(printf '%s\n' "$bad" | while read -r f; do sha256sum "$f" 2>/dev/null; done | sha256sum | cut -c1-16)
if [ "$(cat "$STATE" 2>/dev/null)" != "$key" ]; then
    mkdir -p "$(dirname "$STATE")" 2>/dev/null && echo "$key" > "$STATE" 2>/dev/null
    if [ -x /usr/sbin/sendmail ]; then
        printf 'To: root\nSubject: [%s] pve-mods reverted by package upgrade\n\n%s\n' "$(hostname)" "$msg" \
            | /usr/sbin/sendmail -t 2>/dev/null
    fi
fi
exit 0
EOF
    chmod 755 "$CHECK"
}

write_aptconf() {
    mkdir -p "$(dirname "$APTCONF")"
    cat > "$APTCONF" <<'EOF'
// pve-mods: warn when a package upgrade overwrites the modified Proxmox GUI files.
// Installed by /home/zitt/lmsensors/pve-mods-apt-hook.sh - see /home/zitt/lmsensors/HISTORY.md
DPkg::Post-Invoke { "if [ -x /usr/local/sbin/pve-mods-check ]; then /usr/local/sbin/pve-mods-check || true; fi"; };
EOF
    chmod 644 "$APTCONF"
}

case "${1:-}" in
    install)
        write_check && echo "installed $CHECK"
        write_aptconf && echo "installed $APTCONF"
        if [ -z "$R" ] && command -v apt-config >/dev/null; then
            apt-config dump | grep -q 'pve-mods-check' && echo "apt sees the hook: OK" || echo "WARNING: apt-config does not show the hook"
        fi
        if [ -r "$MANIFEST" ]; then echo "manifest present: $MANIFEST"; "$CHECK" && echo "check now: installed files match the manifest"
        else echo "NOTE: no manifest yet - run pve9-install.sh once (it writes $MANIFEST); until then the hook stays silent"; fi
        ;;
    uninstall)
        rm -f "$APTCONF" "$CHECK" && echo "removed $APTCONF and $CHECK (manifest kept: $MANIFEST)"
        ;;
    status)
        for f in "$CHECK" "$APTCONF" "$MANIFEST"; do
            if [ -e "$f" ]; then echo "present: $f"; else echo "missing: $f"; fi
        done
        [ -r "$MANIFEST" ] && sed 's/^/    /' "$MANIFEST"
        if [ -x "$CHECK" ]; then
            out=$(PVE_MODS_NOMAIL=1 PVE_MODS_MANIFEST="$MANIFEST" "$CHECK" 2>&1)
            if [ -z "$out" ]; then echo "check: OK (installed files match, or no manifest)"; else echo "$out"; fi
        fi
        ;;
    test)
        [ -x "$CHECK" ] || { echo "hook not installed"; exit 1; }
        [ -r "$MANIFEST" ] || { echo "no manifest to test against"; exit 1; }
        t=$(mktemp); trap 'rm -f "$t"' EXIT
        # same files, first hash deliberately wrong -> simulates a reverted file
        awk 'NR==1{ $1="0000000000000000000000000000000000000000000000000000000000000000" } {print $1"  "$2}' "$MANIFEST" > "$t"
        echo "--- simulated revert of $(awk 'NR==1{print $2}' "$MANIFEST") (no mail, no state change):"
        PVE_MODS_NOMAIL=1 PVE_MODS_MANIFEST="$t" PVE_MODS_STATE=/dev/null "$CHECK"
        echo "--- rc=$? (must be 0: the hook never fails apt)"
        ;;
    *)
        sed -n '2,22p' "$0"; exit 2
        ;;
esac
