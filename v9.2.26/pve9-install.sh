#!/bin/bash
# pve9-install.sh - install the pve-mods v9.2.26 port, with backup and automatic rollback.
#
# Run as root on the Proxmox host:
#     bash /home/zitt/lmsensors/pve9-install.sh             # install
#     bash /home/zitt/lmsensors/pve9-install.sh --dry-run   # all checks + backup plan, change nothing
#     bash /home/zitt/lmsensors/pve9-install.sh --force     # skip version / file-state guards
#     bash /home/zitt/lmsensors/pve9-install.sh --restore [BACKUP_DIR]   # revert (default: latest)
#
# Backups go to /root/pve-mods-backup/<timestamp>/ (NOT /tmp: /tmp is tmpfs on Debian 13
# and is wiped at reboot). Each backup contains the original files with their full paths,
# a manifest (sha256, mode, owner), and a standalone restore.sh.
#
# Result log/report: <this dir>/pve9-install.log and <this dir>/pve9-install.json

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# works from lmsensors/ (repo at ./pve-mods/v9.2.26) or from inside the repo's v9.2.26/ folder
if [ -d "$DIR/patches" ]; then REPO="$DIR"; else REPO="$DIR/pve-mods/v9.2.26"; fi
BACKUP_ROOT=/root/pve-mods-backup
LOG="$DIR/pve9-install.log"
RESULT="$DIR/pve9-install.json"

EXPECT_PVE_MANAGER="9.2.26"
EXPECT_PWT="5.2.12"

# name | installed path | sha256 of WSL-validated new file | sha256 of stock (ORG) file | earlier pve-mods versions (comma list, ok to upgrade)
FILES=(
  "Nodes.pm|/usr/share/perl5/PVE/API2/Nodes.pm|a9587912d995a7aafdcd0cd6b7ebbe19ed320e55b4901c67b206212444200b95|675bf4d79c690bfef2d7c38f7de74010dacf3a4e55ac1049fc50942f10ade8f9|"
  "proxmoxlib.js|/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js|50ad18f4cc19467bbb1a2504163633f71891c372e505bc462f12c9cc227ba2b8|47a053d3ac9a91403bb0f69a633246da6a59f1415786d607da26e528edd2d5c7|"
  "pvemanagerlib.js|/usr/share/pve-manager/js/pvemanagerlib.js|fb47fd5c4a5d72b19f4b83e67cf38419946d78841cb43db89ac5ab618e091453|532fcf0ae6298a190e239e2f538246ff716535dd14890f349687c3a57bd35efe|6e7bc321809078296808ec2a62a8d0f9993212e3a8a88f4a27960cf4f97bd33d,ead62aa5c6c2c621372586915ba231384a73cdf2a803f6c8a4e8cbc12998b81b"
)
SERVICES=(pvedaemon pveproxy)

FORCE=0; DRYRUN=0; MODE=install; RESTORE_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1 ;;
        --dry-run) DRYRUN=1 ;;
        --restore) MODE=restore; if [ $# -gt 1 ] && [ "${2#--}" = "$2" ]; then RESTORE_DIR="$2"; shift; fi ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ]; then echo "ERROR: run as root" >&2; exit 1; fi

exec > >(tee -a "$LOG") 2>&1
echo "===== $(date '+%F %T') pve9-install.sh mode=$MODE force=$FORCE dry_run=$DRYRUN ====="

STATUS="started"; DETAIL=""; BK=""; ROLLED_BACK=0; SMOKE=""
log()  { echo "[$(date +%T)] $*"; }
die()  { STATUS="aborted"; DETAIL="$*"; log "ABORT: $*"; finish 1; }
sha()  { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

finish() {
    local rc=$1
    STATUS="$STATUS" DETAIL="$DETAIL" BK="$BK" ROLLED_BACK="$ROLLED_BACK" SMOKE="$SMOKE" \
    MODE="$MODE" RESULT="$RESULT" python3 - <<'PYEOF'
import json, os, time
r = {k.lower(): os.environ.get(k, "") for k in ["MODE", "STATUS", "DETAIL", "BK", "ROLLED_BACK"]}
r["backup_dir"] = r.pop("bk")
r["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
try:
    r["smoke_test"] = json.loads(os.environ.get("SMOKE") or "null")
except Exception:
    r["smoke_test"] = os.environ.get("SMOKE")
json.dump(r, open(os.environ["RESULT"], "w"), indent=2); open(os.environ["RESULT"], "a").write("\n")
PYEOF
    chown --reference="$DIR" "$LOG" "$RESULT" 2>/dev/null
    chmod 644 "$LOG" "$RESULT" 2>/dev/null
    log "status=$STATUS ${DETAIL:+($DETAIL)}"
    exit "$rc"
}

restart_services() {
    local ok=0
    for s in "${SERVICES[@]}"; do
        systemctl restart "$s" || ok=1
    done
    sleep 3
    for s in "${SERVICES[@]}"; do
        if [ "$(systemctl is-active "$s")" != "active" ]; then log "service $s is NOT active"; ok=1; fi
    done
    return $ok
}

# copy every file in a backup dir back to its original path, preserving mode/owner/mtime
restore_from() {
    local b="$1" rc=0
    [ -f "$b/manifest.txt" ] || { log "no manifest in $b"; return 1; }
    while IFS='|' read -r path hash _mode _owner _group; do
        [ -n "$path" ] || continue
        if cp -a "$b/files$path" "$path" && [ "$(sha "$path")" = "$hash" ]; then
            log "restored $path"
        else
            log "FAILED to restore $path"; rc=1
        fi
    done < "$b/manifest.txt"
    return $rc
}

rollback() {
    log "ROLLING BACK from $BK"
    ROLLED_BACK=1
    if restore_from "$BK"; then
        log "files restored"
    else
        log "!!! restore incomplete - run: bash $BK/restore.sh"
    fi
    if restart_services; then
        log "services restarted on original files"
    else
        log "!!! services not healthy after rollback"
    fi
}

# ------------------------------------------------------------------ restore mode
if [ "$MODE" = restore ]; then
    [ -n "$RESTORE_DIR" ] || RESTORE_DIR="$(readlink -f "$BACKUP_ROOT/latest" 2>/dev/null)"
    [ -d "$RESTORE_DIR" ] || die "backup dir not found: ${RESTORE_DIR:-$BACKUP_ROOT/latest}"
    BK="$RESTORE_DIR"
    log "restoring from $BK"
    cat "$BK/manifest.txt"
    restore_from "$BK" || die "restore failed for one or more files"
    restart_services || { STATUS="restored-services-unhealthy"; finish 1; }
    STATUS="restored"; finish 0
fi

# ------------------------------------------------------------------ 1. guards
[ -d "$REPO" ] || die "$REPO not found"
command -v python3 >/dev/null || die "python3 not found"

v_mgr="$(dpkg-query -W -f='${Version}' pve-manager 2>/dev/null)"
v_pwt="$(dpkg-query -W -f='${Version}' proxmox-widget-toolkit 2>/dev/null)"
log "pve-manager=$v_mgr (expect $EXPECT_PVE_MANAGER)  proxmox-widget-toolkit=$v_pwt (expect $EXPECT_PWT)"
if [ "$v_mgr" != "$EXPECT_PVE_MANAGER" ] || [ "$v_pwt" != "$EXPECT_PWT" ]; then
    if [ $FORCE -eq 1 ]; then
        log "WARNING: version mismatch ignored (--force)"
    else
        die "package versions differ from what the port was built against (use --force to override)"
    fi
fi

already=0
for entry in "${FILES[@]}"; do
    IFS='|' read -r name target new_h org_h prev_h <<< "$entry"
    src="$REPO/$name"
    [ -f "$src" ]    || die "missing source $src (run pve9-precheck.sh first; it builds it from ORG + patches)"
    [ -f "$target" ] || die "missing target $target"
    if [ "$(sha "$src")" != "$new_h" ]; then
        if [ $FORCE -eq 1 ]; then
            log "WARNING: $src differs from validated version (--force)"
        else
            die "$src differs from the validated version (re-validate, or --force)"
        fi
    fi
    cur="$(sha "$target")"
    if [ "$cur" = "$org_h" ]; then
        log "$target: stock (ok to patch)"
    elif [ "$cur" = "$new_h" ]; then
        log "$target: already patched"; already=$((already + 1))
    elif [ -n "$prev_h" ] && [[ ",$prev_h," == *",$cur,"* ]]; then
        log "$target: earlier pve-mods version (ok to upgrade; backup will hold that version)"
    elif [ $FORCE -eq 1 ]; then
        log "WARNING: $target is not the expected stock file (--force)"
    else
        die "$target is neither stock 9.2.26 nor the patched file (use --force to override)"
    fi
done
if [ $already -eq ${#FILES[@]} ]; then STATUS="already-installed"; finish 0; fi

log "perl -c on source Nodes.pm"
perl -c "$REPO/Nodes.pm" || die "perl -c failed on $REPO/Nodes.pm"

# ------------------------------------------------------------------ 2. backup
BK="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
if [ $DRYRUN -eq 1 ]; then
    log "DRY RUN: would back up to $BK, install ${#FILES[@]} files, restart ${SERVICES[*]}"
    for entry in "${FILES[@]}"; do
        IFS='|' read -r name target _ _ <<< "$entry"
        log "  $target  ($(stat -c '%a %U:%G' "$target")) <- $REPO/$name"
    done
    BK=""; STATUS="dry-run-ok"; finish 0
fi

mkdir -p "$BK/files" || die "cannot create $BK"
chmod 700 "$BACKUP_ROOT" "$BK"
: > "$BK/manifest.txt"
for entry in "${FILES[@]}"; do
    IFS='|' read -r name target _ _ <<< "$entry"
    cp -a --parents "$target" "$BK/files/" || die "backup copy failed for $target"
    h="$(sha "$target")"
    [ "$(sha "$BK/files$target")" = "$h" ] || die "backup verification failed for $target"
    echo "$target|$h|$(stat -c '%a|%U|%G' "$target")" >> "$BK/manifest.txt"
done
{
    echo "pve-manager=$v_mgr"; echo "proxmox-widget-toolkit=$v_pwt"
    echo "created=$(date '+%F %T')"; echo "by=$0"
} > "$BK/versions.txt"

# standalone restore script (works even if the lmsensors share is unavailable)
cat > "$BK/restore.sh" <<EOF
#!/bin/bash
# Restore the files backed up on $(date '+%F %T') and restart the PVE services.
set -u
B="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
rc=0
while IFS='|' read -r path hash mode owner group; do
    [ -n "\$path" ] || continue
    cp -a "\$B/files\$path" "\$path" && [ "\$(sha256sum "\$path" | cut -d' ' -f1)" = "\$hash" ] \\
        && echo "restored \$path" || { echo "FAILED \$path"; rc=1; }
done < "\$B/manifest.txt"
systemctl restart ${SERVICES[*]}
systemctl is-active ${SERVICES[*]}
echo "Done (rc=\$rc). Hard-refresh the browser (Ctrl+F5)."
exit \$rc
EOF
chmod 700 "$BK/restore.sh"
ln -sfn "$BK" "$BACKUP_ROOT/latest"
log "backup complete: $BK"
cat "$BK/manifest.txt"

# ------------------------------------------------------------------ 3. install (atomic, keep mode/owner)
for entry in "${FILES[@]}"; do
    IFS='|' read -r name target new_h _ <<< "$entry"
    read -r mode uid gid <<< "$(stat -c '%a %u %g' "$target")"
    tmp="$target.pve-mods.new"
    if install -m "$mode" -o "$uid" -g "$gid" "$REPO/$name" "$tmp" && mv -f "$tmp" "$target" \
       && [ "$(sha "$target")" = "$new_h" ]; then
        log "installed $target (mode $mode, owner $uid:$gid)"
    else
        rm -f "$tmp"; log "install failed for $target"; rollback
        STATUS="failed-rolled-back"; DETAIL="install of $target failed"; finish 1
    fi
done

# ------------------------------------------------------------------ 4. verify
log "perl -c on installed Nodes.pm"
if ! perl -c /usr/share/perl5/PVE/API2/Nodes.pm; then
    rollback; STATUS="failed-rolled-back"; DETAIL="perl -c failed on installed Nodes.pm"; finish 1
fi

log "restarting ${SERVICES[*]}"
if ! restart_services; then
    journalctl -u pvedaemon -u pveproxy -n 30 --no-pager
    rollback; STATUS="failed-rolled-back"; DETAIL="services failed to restart"; finish 1
fi

log "smoke test: pvesh get /nodes/$(hostname)/status"
if ! api="$(timeout 60 pvesh get "/nodes/$(hostname)/status" --output-format json 2>&1)"; then
    echo "$api" | tail -20
    rollback; STATUS="failed-rolled-back"; DETAIL="node status API call failed"; finish 1
fi
SMOKE="$(API="$api" python3 - <<'PYEOF'
import json, os
d = json.loads(os.environ["API"])
keys = ["nvme0n1", "cputemp", "cputemp2", "systemp", "nvme2temp", "fan1rpm", "fan2rpm", "fan3rpm",
        "fan4rpm", "fan6rpm", "fan7rpm", "inletTemp", "outletTemp", "picoTemp"]
out = {"present": {k: d[k] for k in keys if k in d}, "missing": [k for k in keys if k not in d],
       "stock_keys_ok": all(k in d for k in ["cpu", "memory", "rootfs", "pveversion"])}
print(json.dumps(out))
PYEOF
)"
log "smoke: $SMOKE"
if ! echo "$SMOKE" | grep -q '"stock_keys_ok": true'; then
    rollback; STATUS="failed-rolled-back"; DETAIL="status API lost stock fields"; finish 1
fi

STATUS="installed"
DETAIL="hard-refresh the browser (Ctrl+F5). Revert with: bash $0 --restore   (or bash $BK/restore.sh)"
finish 0
