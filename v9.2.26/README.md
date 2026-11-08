# pve-mods for Proxmox VE 9.2.26

These mods add CPU, motherboard and NVMe temperatures, fan speeds (with PWM-based bars), NVMe wear
("HD Life") and [Fanpico](https://github.com/tjko/fanpico) sensors to the node **Summary → Status**
panel of the Proxmox VE web interface.

This is a port of the [v8.2.4](../v8.2.4) mods (Rev 1 + Rev 2) to PVE 9. It's based on the work by
[alexleigh](https://github.com/alexleigh/pve-mods).

| Package | Version these patches were made against |
|---|---|
| pve-manager | **9.2.26** |
| proxmox-widget-toolkit | **5.2.12** |

Tested on Debian 13 "trixie", Perl 5.40.1, Python 3.13, lm-sensors 3.6.2, smartmontools 7.5 and
python3-paho-mqtt 2.1.0.

> **Warning**
> These patches modify files owned by Proxmox packages. Any upgrade of `pve-manager` or
> `proxmox-widget-toolkit` silently reverts them. They're specific to an **ASUS Pro WS X299 SAGE II**
> (nct6798 Super I/O). Sensor names, fan numbers and the hwmon platform device
> (`nct6775.656`) will almost certainly be different on your hardware. For hobby use only, as is.

## What changed from v8.2.4

PVE 9 reformatted its sources (prettier / perltidy), so the 8.2.4 patches **don't apply**. The changes
were re-applied by hand at the same places in the code:

| File | Where | Change |
|---|---|---|
| `Nodes.pm` | end of the `status` API method, after the `rootfs` block | NVMe life (from `/tmp/smartctl.<dev>.json`), lm-sensors temps and fans, picofan |
| `proxmoxlib.js` | after `render_node_size_usage` | `render_node_temp`, `render_node_fan`, `render_node_nvme_life` |
| `pvemanagerlib.js` | `PVE.node.StatusView` | height 350 → 660, plus the panel items after `swap` |

Everything added is wrapped in `pve-mods (Zitt)` … `end pve-mods` comments.

Fixes made while porting:
- **hwmon path is globbed** (`/sys/devices/platform/nct6775.656/hwmon/hwmon*/pwmN`). On this host the
  number moved from `hwmon4` (PVE 8) to `hwmon8` (PVE 9), which would have silently broken the fan bars.
- **A missing smartctl JSON is handled cleanly.** This matters more now, because `/tmp` is a tmpfs on
  Debian 13 and is emptied at every boot.
- The JS renderers use `parseFloat`, so values that arrive as strings no longer crash `.toFixed`.
- `$a` was renamed to `$item` (`$a` is reserved for Perl's sort).
- PVE 9 added a `returns` schema to the status method. It keeps `additionalProperties => 1`, so the
  extra keys pass through.

`smartctl.py` is the updated collector. It fixes an exit-code typo (`sys,exit`) and can also collect
the NVMe members of an md RAID that holds swap (writes `/tmp/smartctl.<mdX>.json`; not shown in the
GUI yet).

## Files

| Path | Purpose |
|---|---|
| `patches/*.patch` | `diff -u` from the stock 9.2.26 file to the modified one. This is what's committed. |
| `ORG/` | Put the stock 9.2.26 files here. (`*.pm` and `*.js` are gitignored.) |
| `pve9-precheck.sh` | Read-only checks. Builds the modified files from `ORG/` + `patches/` and writes `pve9-precheck.json`. |
| `pve9-install.sh` | Installer: verifies, backs up, installs, smoke-tests, rolls back automatically on failure; `--restore` reverts. |
| `smartctl.py` | Run as root (cron and/or a systemd oneshot). Writes `/tmp/smartctl.<dev>.json`. |
| `smartctl-nvme0n1.export.service` | Example systemd unit for running `smartctl.py` at boot |
| `versions.txt` | `pveversion -v` excerpt from the build host |
| `../v8.2.4/picofan.py` | Fanpico MQTT reader (unchanged; fill in your broker and credentials) |

## Requirements

```bash
apt install lm-sensors smartmontools python3-paho-mqtt python3-dateutil
sensors-detect          # then reboot, and check `sensors -j`
```

Install `smartctl.py` and `picofan.py` to `/opt/`. Run `smartctl.py` as root at boot and
periodically, for example:

```cron
33 */6 * * *  PATH=/usr/sbin:$PATH /usr/bin/python3 /opt/smartctl.py  >> /var/log/smartctl.log 2>&1
```

## Install (scripted)

As root, from this folder in a clone:

```bash
# 1. stock files -> ORG/ (only while they're still unmodified 9.2.26)
cp /usr/share/perl5/PVE/API2/Nodes.pm                          ORG/
cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js  ORG/
cp /usr/share/pve-manager/js/pvemanagerlib.js                  ORG/

# 2. read-only checks; builds Nodes.pm/proxmoxlib.js/pvemanagerlib.js from ORG + patches
bash pve9-precheck.sh            # look at pve9-precheck.json: ready_to_install, warnings

# 3. install (backup in /root/pve-mods-backup/<timestamp>/, automatic rollback on failure)
bash pve9-install.sh --dry-run
bash pve9-install.sh
```

Then hard-refresh the browser (Ctrl+F5).

The installer refuses to run if the package versions differ, if a modified file doesn't match the
sha256 it was validated with, or if an installed file is neither stock nor already patched.
`--force` overrides the version and hash guards. The rollback after a failure always applies.

**Revert:**

```bash
bash pve9-install.sh --restore                 # latest backup
bash /root/pve-mods-backup/latest/restore.sh   # same, standalone
apt install --reinstall pve-manager proxmox-widget-toolkit
```

## Install (manual)

The patches use relative `ORG/<file>` → `<file>` labels, so build each file next to its stock copy,
then copy it into place:

```bash
cd v9.2.26
for f in Nodes.pm proxmoxlib.js pvemanagerlib.js; do patch -o "$f" "ORG/$f" "patches/$f.patch"; done
perl -c Nodes.pm
# back up the three installed files, copy these over them, then:
systemctl restart pvedaemon pveproxy
```

## Adapting to your hardware

Edit `%sensors_config` in `Nodes.pm`. Each entry maps an API key to a path in `sensors -j` output:

```perl
cputemp => { jsonpath => ['coretemp-isa-0000', 'Package id 0'], valkey => 'temp1_input', critkey => 'temp1_crit' },
```

Then add or remove the matching panel items in `pvemanagerlib.js`. `pve9-precheck.sh` reports which
configured paths exist on your system (`sensors.config_checks` in the JSON).

## Known limitations

- Error placeholders in `Nodes.pm` show as plausible numbers (e.g. "26% remaining" means the smartctl
  JSON couldn't be read). Check the `error` field in `pvesh get /nodes/<node>/status`.
- The NVMe life bar colours high *remaining* life as "critical", because the widget treats a high
  ratio as bad.
- `smartctl.py` runs as root and writes to fixed names in `/tmp`. On a host with untrusted local users,
  move the output to a root-owned directory such as `/run/smartctl/`, change the path in `Nodes.pm`,
  and run it with `python3 -I`.
