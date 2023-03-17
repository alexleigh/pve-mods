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

lm-sensors needs to be installed on the hypervisor for the probes to work. To support hard
drive temperatures, the `drivetemp` module must be loaded for lm-sensors to report SMART
temperature readings. Use `sensors -j` to get the JSON output from lm-sensors. The JSON
output is used by the modified pve-manager Perl API to report temperatures. Take note of
the keys in the JSON tree leading to the relevant temperature values, as they need to match
the keys in the JSON parsing code in [Nodes.pm](https://github.com/alexleigh/pve-manager/blob/v7.3-6/PVE/API2/Nodes.pm#L424).

## Usage

The simple way to apply these modifications is by examining the patch files in the
[patches](patches) directory. Directly applying these patches to the PVE distribution
files should only be done if the PVE packages on your system match the version these patches
were generated against, however. These patches were made against:

* pve-manager 7.3-6
* proxmox-widget-toolkit 3.5.5

If the version installed on your system are different from these, the patches should not be
applied. Instead, use the patches as a reference to make manual modifications to the affected
files.

### Build from source

Alternatively, the modified files can be built from Proxmox sources. The modifications have
been committed to the following repositories:

* [pve-manager](https://github.com/alexleigh/pve-manager/tree/v7.3-6)
* [proxmox-widget-toolkit](https://github.com/alexleigh/proxmox-widget-toolkit/tree/v3.5.5)

Cloning the above two repositories and this repository in the same parent directory, and invoking
`make all` in this repository, will generate all the modified files within the directory where
this repository is checked out. Building these files requires a development environment where,
at a minimum, the Proxmox packages `pve-manager`, `proxmox-widget-toolkit`, and
[`pve-docs`](https://github.com/proxmox/pve-docs) can be successfully built.

Once the modified files have been built, running `make install` will install the files to the
current system, replacing PVE distributed files. Prior to running `make install`, it is a good
idea to run `make backup` to make a copy of the PVE distributed files. Running `make restore`
will restore the backed up files, replacing the modified ones (`make backup` must have already
been run for `make restore` to work.)
