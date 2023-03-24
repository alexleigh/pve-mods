# pve-mods

Modifications to [Proxmox Virtual Environment](https://www.proxmox.com/en/proxmox-ve) in
order to add CPU and hard drive temperature readings (powered by
[lm-sensors](https://github.com/lm-sensors/lm-sensors)) to the PVE web-based management
interface.

Temperature readings on the desktop version of the management interface:

![PVE GUI desktop screenshot](https://github.com/alexleigh/pve-mods/blob/docs/desktop.png?raw=true)

Temperature readings on the mobile version of the management interface:

![PVE GUI mobile screenshot](https://github.com/alexleigh/pve-mods/blob/docs/mobile.png?raw=true)

Since the mobile version does not auto-refresh statuses, another enhancement included in these
mods is the addition of an Auto-refresh on/off toggle in the mobile Node status view.

## Disclaimer

These enhancements involve modifying files distributed by Proxmox packages. As such, they
should be used on hobby projects only. Also, any updates to the affected Proxmox packages
will erase the modifications.

## Requirements

lm-sensors needs to be installed on the hypervisor for the probes to work. To install
lm-sensors, run the following on the hypervisor:

```shell
apt install lm-sensors
```

To show hard drive temperatures, the `drivetemp` module must be loaded for lm-sensors to
report SMART temperature readings. To manually load the `drivetemp` module, run the following
on the hypervisor:

```shell
modprobe drivetemp
```

To confirm the SMART temperature readings are working, run the sensors command on the
hypervisor:

```shell
sensors
```

Once the hard drive temperature sensors are confirmed to be working, you can configure the
system to load the `drivetemp` module at boot.

## Usage

The simple way to apply these modifications is by examining the patch files in one of the patches
directories. Caution: directly applying these patches to the PVE distribution files should only be
done if the PVE packages on your system match the version these patches were generated against. The
patch directories and the versions of the Proxmox packages they were generated against are:

[v7.3-6-pwt3.5.5](v7.3-6-pwt3.5.5/patches)
* pve-manager 7.3-6
* proxmox-widget-toolkit 3.5.5

If the version installed on your system are different from these, the patches should not be
applied. Instead, use the patches as a reference to make manual modifications to the affected
files. Of the four patched files,
[pvemanager-mobile.js.patch](v7.3-6-pwt3.5.5/patches/pvemanager-mobile.js.patch) is an optional
change that only needs to be applied if you are interested in adding the temperature readings to the
mobile site. The other three files must be modified in order for the temperature readings to work.

The patches also hardcode the names of various lm-sensors probes to extract temperature
readings. On your system these names are likely different, so the changes you need to make
will be different from the patches. First, run the `sensors` command in JSON mode to inspect
the JSON output:

```shell
sensors -j
```

For each probe whose value you wish to display, take note of the JSON path to reach the dictionary
containing the temperature values, as well as the keys of the current reading and critical value.
The path and key names go into the `%sensors_config` hash in
[Nodes.pm](v7.3-6-pwt3.5.5/patches/Nodes.pm.patch). The keys of the `%sensors_config` can be any
string as long as they are unique and do not collide with any existing keys in the `$res` hash.
These key names in `%sensors_config` will be referenced by the JavaScript files used to display the
temperatures.

With `%sensors_config` configured, modify
[pvemanagerlib.js](v7.3-6-pwt3.5.5/patches/pvemanagerlib.js.patch) to reference the configured
probes. For each item, the `valueField` and `maxField` refer to one of the configured keys in
`%sensors_config`. If you wish to enhance the mobile site as well, modify
[pvemanager-mobile.js](v7.3-6-pwt3.5.5/patches/pvemanager-mobile.js.patch) to also reference the
configured probes.

Depending on the number of probes you have configured, you may need to adjust the height of the
status area in [pvemanagerlib.js](v7.3-6-pwt3.5.5/patches/pvemanagerlib.js.patch). Also, if an odd
number of probes was added, you may need to add a spacer to preserve the layout of items lower on
the status panel.

### Build from source

Alternatively, the modified files can be built from Proxmox sources. The modifications have
been committed to the following repositories:

* [pve-manager](https://github.com/alexleigh/pve-manager)
* [proxmox-widget-toolkit](https://github.com/alexleigh/proxmox-widget-toolkit)

To build the modified files in the [v7.3-6-pwt3.5.5](7.3-6-pwt3.5.5) directory, use the following
branches:

* [pve-manager](https://github.com/alexleigh/pve-manager/tree/v7.3-6)
* [proxmox-widget-toolkit](https://github.com/alexleigh/proxmox-widget-toolkit/tree/v3.5.5)

Cloning the above two repositories and this repository in the same parent directory, and invoking
`make all` in one of the versioned subdirectories, will generate all the modified files within the
versioned subdirectory. Building these files requires a development environment where, at a minimum,
the Proxmox packages `pve-manager`, `proxmox-widget-toolkit`, and
[`pve-docs`](https://github.com/proxmox/pve-docs) can be successfully built.

If you're making modifications on top of official Proxmox repositories, for the purpose of installing
the modified files on a real system, make sure to check out the revision in the Proxmox repository
which matches the version of the Proxmox package installed on the system being modified. For example,
if you are modifying [`pve-manager`](https://git.proxmox.com/?p=pve-manager.git;a=summary), and
the system you are targeting is running `pve-manager` 7.3-6, make sure to check out revision
`723bb6e` "bump version to 7.3-6" prior to making any changes. Otherwise, the modified file will contain
changes other than the changes you intended.

Once the modified files have been built, running `make install` will install the files to the
current system, replacing PVE distributed files. Prior to running `make install`, it is a good
idea to run `make backup` to make a copy of the PVE distributed files. Running `make restore`
will restore the backed up files, replacing the modified ones (`make backup` must have already
been run for `make restore` to work.)
