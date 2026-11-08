#!/bin/bash
# pve9-precheck.sh - READ-ONLY pre-install checks for the pve-mods v9.2.26 port.
#
# Run as root on the Proxmox host:
#     bash /home/zitt/lmsensors/pve9-precheck.sh
#
# Writes:  <this dir>/pve9-precheck.json   (full report)
#          <this dir>/pve-mods/v9.2.26/patches/*.patch  (diff -u stock -> modified)
#
# It changes nothing under /usr, /etc or /opt and restarts nothing. Side effects:
#   - creates the patches/ files above
#   - runs /opt/picofan.py once (same as every GUI status poll does; may refresh
#     /tmp/ProxFanPico.json)
#   - reads (not writes) /tmp/smartctl.*.json

set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# works from lmsensors/ (repo at ./pve-mods/v9.2.26) or from inside the repo's v9.2.26/ folder
if [ -d "$DIR/patches" ]; then REPO="$DIR"; else REPO="$DIR/pve-mods/v9.2.26"; fi
OUT="$DIR/pve9-precheck.json"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root (smartctl/pvesh/sysfs checks need it)" >&2
    exit 1
fi
if [ ! -d "$REPO/ORG" ]; then
    echo "ERROR: $REPO/ORG not found" >&2
    exit 1
fi

# --- step 2b: modified file present -> (re)generate its patch; absent (fresh git clone, where
#     *.pm/*.js are gitignored) -> build it from ORG + patch. Hashes are verified below either way.
mkdir -p "$REPO/patches"
for f in Nodes.pm proxmoxlib.js pvemanagerlib.js; do
    if [ -f "$REPO/$f" ]; then
        diff -u --label "ORG/$f" --label "$f" "$REPO/ORG/$f" "$REPO/$f" > "$REPO/patches/$f.patch"
    elif [ -f "$REPO/ORG/$f" ] && [ -f "$REPO/patches/$f.patch" ]; then
        if patch --quiet -o "$REPO/$f" "$REPO/ORG/$f" "$REPO/patches/$f.patch"; then
            echo "built $REPO/$f from ORG + patch"
        else
            echo "WARNING: patch failed for $f (ORG is not stock 9.2.26?)" >&2
        fi
    else
        echo "WARNING: $REPO/$f missing and cannot be built (need ORG/$f and patches/$f.patch)" >&2
    fi
done

# --- everything else is collected by python3 (stdlib only) into one JSON file ---
DIR="$DIR" REPO="$REPO" OUT="$OUT" python3 - <<'PYEOF'
import glob, hashlib, json, os, re, shutil, socket, subprocess, time

DIR, REPO, OUT = os.environ["DIR"], os.environ["REPO"], os.environ["OUT"]

# sha256 of the files that were validated in WSL (Ubuntu 26.04, perl 5.40.1, node 22)
VALIDATED = {
    "Nodes.pm":         "a9587912d995a7aafdcd0cd6b7ebbe19ed320e55b4901c67b206212444200b95",
    "proxmoxlib.js":    "50ad18f4cc19467bbb1a2504163633f71891c372e505bc462f12c9cc227ba2b8",
    "pvemanagerlib.js": "6e7bc321809078296808ec2a62a8d0f9993212e3a8a88f4a27960cf4f97bd33d",
}
TARGETS = {
    "Nodes.pm":         "/usr/share/perl5/PVE/API2/Nodes.pm",
    "proxmoxlib.js":    "/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js",
    "pvemanagerlib.js": "/usr/share/pve-manager/js/pvemanagerlib.js",
}
# mirror of %sensors_config in the modified Nodes.pm (lm-sensors entries only)
SENSORS_CONFIG = {
    "cputemp":   (["coretemp-isa-0000", "Package id 0"], "temp1_input", "temp1_crit"),
    "nvme2temp": (["nvme-pci-0200", "Composite"],         "temp1_input", "temp1_crit"),
    "cputemp2":  (["nct6798-isa-0290", "CPUTIN"],         "temp2_input", "temp2_max"),
    "systemp":   (["nct6798-isa-0290", "SYSTIN"],         "temp1_input", "temp1_max"),
    "fan1rpm":   (["nct6798-isa-0290", "fan1"],           "fan1_input",  "fan1_alarm"),
    "fan2rpm":   (["nct6798-isa-0290", "fan2"],           "fan2_input",  "fan2_alarm"),
    "fan4rpm":   (["nct6798-isa-0290", "fan4"],           "fan4_input",  "fan4_alarm"),
    "fan6rpm":   (["nct6798-isa-0290", "fan6"],           "fan6_input",  "fan6_alarm"),
    "fan7rpm":   (["nct6798-isa-0290", "fan7"],           "fan7_input",  "fan7_min"),
}
PICOFAN_EXPECT = {"fans": [8], "sensors": [1, 2, 3]}

def run(cmd, timeout=30, shell=False):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, shell=shell)
        return {"rc": p.returncode, "out": p.stdout, "err": p.stderr}
    except FileNotFoundError as e:
        return {"rc": 127, "out": "", "err": str(e)}
    except subprocess.TimeoutExpired:
        return {"rc": 124, "out": "", "err": f"timeout after {timeout}s"}

def tail(s, n=15):
    lines = (s or "").strip().splitlines()
    return lines[-n:]

def redact(s):
    s = re.sub(r"(['\"]password['\"]\s*:\s*)['\"][^'\"]*['\"]", r"\1'***'", s or "", flags=re.I)
    return re.sub(r"(password\s*=\s*)['\"][^'\"]*['\"]", r"\1'***'", s, flags=re.I)

def sha256(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None

def fstat(path):
    try:
        st = os.stat(path)
        import pwd, grp
        return {"mode": oct(st.st_mode & 0o7777), "owner": pwd.getpwuid(st.st_uid).pw_name,
                "group": grp.getgrgid(st.st_gid).gr_name, "size": st.st_size,
                "mtime": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime))}
    except OSError as e:
        return {"error": str(e)}

def pkgver(pkg):
    r = run(["dpkg-query", "-W", "-f=${Version}", pkg])
    return r["out"].strip() if r["rc"] == 0 else None

report = {"script": "pve9-precheck.sh", "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
          "host": socket.gethostname(), "problems": [], "warnings": []}
P, W = report["problems"], report["warnings"]

# ---- meta / versions ----
report["versions"] = {
    "kernel": os.uname().release,
    "perl": run(["perl", "-e", 'printf "%vd", $^V'])["out"],
    "python3": run(["python3", "--version"])["out"].strip(),
    "packages": {p: pkgver(p) for p in ["pve-manager", "proxmox-widget-toolkit", "libpve-common-perl",
                                         "libjson-perl", "lm-sensors", "smartmontools",
                                         "python3-paho-mqtt", "python3-dateutil", "nodejs"]},
}
pv = report["versions"]["packages"]
if pv["pve-manager"] != "9.2.26":
    P.append(f"pve-manager is {pv['pve-manager']}, port was made against 9.2.26")
if pv["proxmox-widget-toolkit"] != "5.2.12":
    P.append(f"proxmox-widget-toolkit is {pv['proxmox-widget-toolkit']}, port was made against 5.2.12")

# ---- step 1a: file state ----
files = {}
for name, target in TARGETS.items():
    org, new = os.path.join(REPO, "ORG", name), os.path.join(REPO, name)
    inst_h, org_h, new_h = sha256(target), sha256(org), sha256(new)
    state = ("stock" if inst_h == org_h else "already-patched" if inst_h == new_h else "UNKNOWN")
    files[name] = {
        "target": target, "installed_sha256": inst_h, "installed_stat": fstat(target),
        "installed_state": state, "dpkg_owner": run(["dpkg", "-S", target])["out"].strip(),
        "org_sha256": org_h, "new_sha256": new_h,
        "new_matches_validated": new_h == VALIDATED[name],
        "patch_lines": sum(1 for _ in open(os.path.join(REPO, "patches", name + ".patch"))),
    }
    if state == "UNKNOWN":
        P.append(f"{target} is neither the ORG copy nor the new file (package changed since ORG was taken?)")
    if new_h != VALIDATED[name]:
        P.append(f"{new} differs from the WSL-validated version")
report["files"] = files

# ---- step 1b: lm-sensors ----
r = run(["sensors", "-j"])
sens = {"rc": r["rc"], "stderr": tail(r["err"], 5)}
data = None
try:
    data = json.loads(r["out"])
except Exception as e:
    sens["parse_error"] = str(e)
    P.append("`sensors -j` did not return JSON")
if data is not None:
    sens["chips"] = {chip: sorted(k for k in v.keys() if k != "Adapter") if isinstance(v, dict) else None
                     for chip, v in data.items()}
    checks = {}
    for key, (path, valkey, critkey) in SENSORS_CONFIG.items():
        node = data
        for seg in path:
            node = node.get(seg) if isinstance(node, dict) else None
        if not isinstance(node, dict):
            checks[key] = {"path": path, "found": False}
            W.append(f"sensor {key}: path {path} not in `sensors -j` (GUI will show '-')")
            continue
        checks[key] = {"path": path, "found": True, "value": node.get(valkey),
                       "crit": node.get(critkey), "valkey_present": valkey in node,
                       "critkey_present": critkey in node}
        if valkey not in node:
            W.append(f"sensor {key}: {valkey} missing under {path}; available: {sorted(node)}")
    sens["config_checks"] = checks
report["sensors"] = sens

# ---- step 1c: hwmon (fan PWM used for bar maximums) ----
hw = {"class_hwmon": {}}
for d in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
    try:
        name = open(os.path.join(d, "name")).read().strip()
    except OSError:
        name = None
    hw["class_hwmon"][os.path.basename(d)] = {"name": name, "device": os.path.realpath(os.path.join(d, "device"))}
pwm_glob = "/sys/devices/platform/nct6775.656/hwmon/hwmon*/pwm[0-9]"
hw["nct6775_656_pwm"] = {}
for p in sorted(glob.glob(pwm_glob)):
    try:
        hw["nct6775_656_pwm"][p] = open(p).read().strip()
    except OSError as e:
        hw["nct6775_656_pwm"][p] = f"error: {e}"
if not hw["nct6775_656_pwm"]:
    W.append(f"no files match {pwm_glob}; fan bar maximums fall back to alarm/min values")
report["hwmon"] = hw

# ---- step 1d: picofan ----
pf = {"script": "/opt/picofan.py", "exists": os.path.exists("/opt/picofan.py")}
if pf["exists"]:
    pf["sha256"] = sha256("/opt/picofan.py")
    r = run(["/usr/bin/python3", "/opt/picofan.py"], timeout=15)
    pf["rc"] = r["rc"]  # 0 = fresh MQTT data, 2 = cached/no data (by design)
    pf["stderr_tail"] = [redact(l) for l in tail(r["err"], 10)]
    try:
        pj = json.loads(r["out"])
        pf["json_ok"] = True
        pf["oldData"] = pj.get("oldData")
        pf["keys"] = sorted(pj.keys())
        for sect, ids in PICOFAN_EXPECT.items():
            have = [x.get("id") for x in pj.get(sect, []) if isinstance(x, dict)]
            pf[f"{sect}_ids"] = have
            missing = [i for i in ids if i not in have]
            if missing:
                W.append(f"picofan: {sect} ids {missing} not present (GUI shows '-' for those)")
    except Exception as e:
        pf["json_ok"] = False
        pf["parse_error"] = str(e)
        W.append("picofan.py output is not JSON (picofan GUI fields will be missing)")
    if r["err"].strip():
        W.append("picofan.py wrote to stderr (see picofan.stderr_tail)")
else:
    W.append("/opt/picofan.py not found")
report["picofan"] = pf

# ---- step 1e: smartctl / NVMe life ----
sm = {"boot_nvme_mounts": []}
rx = re.compile(r"^(.+nvme\d.\d)p\d+\s+(.boot\S+)", re.I)
for line in open("/proc/mounts"):
    m = rx.match(line)
    if m:
        sm["boot_nvme_mounts"].append({"dev": m.group(1), "mntpt": m.group(2)})
if not sm["boot_nvme_mounts"]:
    W.append("no NVMe /boot* mount matched; Nodes.pm will report the 'no proc/mounts' placeholder")
sm["json_files"] = {}
for p in sorted(glob.glob("/tmp/smartctl.*.json")):
    ent = fstat(p)
    try:
        j = json.load(open(p))
        ent["percentage_used"] = j.get("nvme_smart_health_information_log", {}).get("percentage_used")
        ent["exit_status"] = j.get("smartctl", {}).get("exit_status")
    except Exception as e:
        ent["parse_error"] = str(e)
    sm["json_files"][p] = ent
for m in sm["boot_nvme_mounts"]:
    if f"/tmp/smartctl.{m['dev'].split('/')[-1]}.json" not in sm["json_files"]:
        W.append(f"/tmp/smartctl.{m['dev'].split('/')[-1]}.json missing; run /opt/smartctl.py")
sm["opt_smartctl_py_sha256"] = sha256("/opt/smartctl.py")
sm["share_smartctl_py_sha256"] = sha256(os.path.join(DIR, "smartctl.py"))
sm["unit"] = {k: run(["systemctl", k, "smartctl-nvme0n1.export"])["out"].strip()
              for k in ["is-enabled", "is-active"]}
cr = run(["crontab", "-l"])
sm["crontab_lines"] = [l for l in cr["out"].splitlines() if "smartctl" in l]
report["smartctl"] = sm

# ---- step 2: syntax checks ----
syn = {}
for label, path in [("new", os.path.join(REPO, "Nodes.pm")), ("org", os.path.join(REPO, "ORG", "Nodes.pm"))]:
    r = run(["perl", "-c", path], timeout=120)
    syn[f"perl_c_{label}"] = {"rc": r["rc"], "output": tail(r["err"] + r["out"], 15)}
if syn["perl_c_new"]["rc"] != 0:
    P.append("perl -c failed on the modified Nodes.pm")
if shutil.which("node"):
    for f in ["proxmoxlib.js", "pvemanagerlib.js"]:
        r = run(["node", "--check", os.path.join(REPO, f)], timeout=120)
        syn[f"node_check_{f}"] = {"rc": r["rc"], "output": tail(r["err"], 5)}
        if r["rc"] != 0:
            P.append(f"node --check failed on {f}")
else:
    syn["node"] = "not installed on host (JS was validated in WSL with node 22)"
report["syntax"] = syn

# ---- services ----
report["services"] = {s: run(["systemctl", "is-active", s])["out"].strip()
                      for s in ["pveproxy", "pvedaemon"]}

report["ready_to_install"] = not P
with open(OUT, "w") as f:
    json.dump(report, f, indent=2, sort_keys=False)
    f.write("\n")

print(f"report: {OUT}")
print(f"ready_to_install: {report['ready_to_install']}")
for p in P: print(f"  PROBLEM: {p}")
for w in W: print(f"  warning: {w}")
PYEOF
rc=$?

# make the report + patches editable from the SMB share (owned like the lmsensors dir)
chown --reference="$DIR" "$OUT" 2>/dev/null
chown -R --reference="$DIR" "$REPO/patches" 2>/dev/null
chmod 644 "$OUT" "$REPO"/patches/*.patch 2>/dev/null
chmod 755 "$REPO/patches" 2>/dev/null
exit $rc
