# pve-mods

Modifications to [Proxmox Virtual Environment](https://www.proxmox.com/en/proxmox-ve) in
order to add CPU and fanspeed values (powered by
[lm-sensors](https://github.com/lm-sensors/lm-sensors)) to the PVE web-based management
interface.

Temperature readings on the desktop version of the management interface:

![PVE GUI desktop screenshot](https://raw.githubusercontent.com/Zitt/pve-mods/main/v8.2.4/x299desktop.png)

Updates based on the work by Alexleigh at https://github.com/alexleigh/pve-mods.
Mobile updates not provided in this patch.

This patch is specific to [Asus Pro WS X299 SAGE II](https://www.asus.com/motherboards-components/motherboards/workstation/pro-ws-x299-sage-ii/helpdesk_download/?model2Name=Pro-WS-X299-SAGE-II) motherboard running lmsensors v3.6.0. Different motherboards and/or lmsensors may require additional changes or debug. Patches provided AS-IS. 

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

Hard drive temperatures are skipped here because the Author's system is set to pass thru most of the rust media to a virtual machine.

To access the fan speeds and other temperatures on the motherboard; you will need to [sensors-detect](https://askubuntu.com/questions/53762/how-to-use-lm-sensors) and make the appropriate module changes as outlined when running the application.

```shell
sensors-detect
```
You will need to reboot your pve environment after making the sensors-detect changes. 

To confirm the SMART temperature readings are working, run the sensors command on the
hypervisor:

```shell
sensors
```

Verify that fan speeds are detected. 

### Rev 2 Requirements

In addition to the previous requirements; Rev 2 requires python 3.11 or better be installed on your proxmox node. You may need to do:

```shell
apt install python3.11
```

Python3 is used by the picofan.py and the smartctl.py scripts included in Rev 2.  

[Picofan](https://github.com/tjko/fanpico) is installed in the Authors ProxMox box to provide additional sensors and more fan control as he ran out of fan headers on the X299 board. The picofan scripts use paho-mqtt to communicate with a broker running on the Proxmox node. The Picofan controller talks over Wifi to the broker running at a static IP running [EMQX](https://tteck.github.io/Proxmox/#emqx-lxc). The broker is then queried by the new content in Node.pm. You will probably need to install:
```shell
apt install python3-paho-mqtt
```
for the proper mqtt libraries. The author is using the latest available in proxmox 8.2.4: python3-paho-mqtt/stable,now 1.6.1-1 
Edit picofan.py and insert the broker's username and password:
```python
userName = "<put data here>"
password = ""
```

[Smartctl](https://www.smartmontools.org/) is used by the smartctl.py script to query for NVME SSD health. I believe this is already installed in proxmox. If not you may be able to install with:
```shell
apt install smartmontools
```
Due to linux permissions; the smartctl.py must be run as root. See the Architectural decisions below for more detail.

## Usage

The simple way to apply these modifications is by examining the patch files in one of the patches
directories. Caution: directly applying these patches to the PVE distribution files should only be
done if the PVE packages on your system match the version these patches were generated against. 

Adjust your manual patches as appropriate.
Make backups of your PVE files before patching and I recommend you manually apply the patches with a text editor yourself so that you understand the changes that are being made. 

Order of operations is to install the .patch files first... verify correct operations then apply the r2.patch files. If you don't want the features provided by Rev 2; simply skip or don't do the patches. You should do all the Rev2 patches if you want a single feature or use your software brain to pull out the relevant pieces. 

The patch directories and the versions of the Proxmox packages they were generated against are:

[v8.2.4](v8.2.4/patches)
* pve-manager 8.2.4
* proxmox-widget-toolkit 4.2.1

> **Warning**  
> If the package versions installed on your system are different from these, the patches should not
> be applied. Instead, use the patches as a reference to make manual modifications to the affected
> files.

> **Note**  
> The patches also hardcode the names of various lm-sensors probes to extract temperature readings.
> On your system, the probes you'd like to display and their corresponding names are likely
> different. This is another reason why you might want to make manual modifications rather than
> apply the patch files.

### Making manual modifications

See original [Readme](../README.md) for more information.

## Rev 2 Architectural Decisions

Rev 2 uses helper python scripts to collect data. I'm sure there are better ways to do this; however, I'm not well versed in proxmox code / capabilities. 

### Picofan 
[Picofan](https://github.com/tjko/fanpico) is collected via a MQTT broker with rentetion. It saves new data (when received) from the broker in the */tmp/ProxFanPico.json* file. If the picofan.py is called and no data is available in the broker; it will read and return the data stored previously in */tmp/ProxFanPico.json*. If the data is received by the broker; it is written to the json file and returned to the caller. This is done to prevent GUI hangs in proxmox's summary page if no new data is present in the broker. The picofan.py script makes sure the json file is readable by all users on the system via a chmod. Picofan sensors are reported in the gui.

Data from picofan.py is merged with the sensors data from lmsensors. They are treated similarly. 

### Smartctl
smartctl.py can only be run as a root as certain permissions are needed. Because of this the smartctl.py program writes a publicly readable json file to */tmp/smartctl.*%s*.json* where %s is the name of the nvme drive. This program is run once as part of a systemd unit file. See smartctl-nvme0n1.export.service for a template. How to install unit files is beyond the scope of this document. Additionally; The author has setup a crontab every six hours to re-capture the nvme life periodically. Node.pm in proxmox reads the json file for it's data. An example crontab from the author's root user:
```crontab
33 */6 * * *  PATH=/usr/sbin:$PATH /usr/bin/python3 /opt/smartctl.py  >> /var/log/smartctl.log 2>&1
```
%s in the filename is replaced with the nvme drive as detected by the regular expression on or about line 16. The */proc/mounts* file is interrogated looking for */boot* entries. smartctl is then run to capture the data for that drive. The author's system currently only has one nvme ssd; so only one drive of data is captured. 

### sys file system
Rev 2 uses the pwm readings presented in /sys/devices/platform/nct6775.656/hwmon/hwmon4/pwm* to calculate the maximum RPM speed of a given fan for the bar graphs. It does simple algebra to calculate. If you do not have the author's exact motherboard; you will need to change this code. 

