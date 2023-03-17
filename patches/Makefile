include ../defines.mk
DIFFCMD=git diff -U20 --no-index

all: proxmoxlib.js.patch Nodes.pm.patch pvemanagerlib.js.patch pvemanager-mobile.js.patch

proxmoxlib.js.patch:
	-${DIFFCMD} ${TOOLKITDIR}/proxmoxlib.js ../proxmoxlib.js > $@

Nodes.pm.patch:
	-${DIFFCMD} ${PERLLIBDIR}/PVE/API2/Nodes.pm ../Nodes.pm > $@

pvemanagerlib.js.patch:
	-${DIFFCMD} ${WWWJSDIR}/pvemanagerlib.js ../pvemanagerlib.js > $@

pvemanager-mobile.js.patch:
	-${DIFFCMD} ${WWWTOUCHDIR}/pvemanager-mobile.js ../pvemanager-mobile.js > $@

clean:
	-rm -f *.patch
