include ../defines.mk

all: proxmoxlib.js.patch Nodes.pm.patch pvemanagerlib.js.patch pvemanager-mobile.js.patch

proxmoxlib.js.patch:
	-git diff --no-index ${TOOLKITDIR}/proxmoxlib.js ../proxmoxlib.js > $@

Nodes.pm.patch:
	-git diff --no-index ${PERLLIBDIR}/PVE/API2/Nodes.pm ../Nodes.pm > $@

pvemanagerlib.js.patch:
	-git diff --no-index ${WWWJSDIR}/pvemanagerlib.js ../pvemanagerlib.js > $@

pvemanager-mobile.js.patch:
	-git diff --no-index ${WWWTOUCHDIR}/pvemanager-mobile.js ../pvemanager-mobile.js > $@

clean:
	-rm -f *.patch
