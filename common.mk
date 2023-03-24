proxmoxlib.js:
	$(MAKE) -C ${SRCDIR}/proxmox-widget-toolkit/src clean $@
	cp -a ${SRCDIR}/proxmox-widget-toolkit/src/$@ $@

Nodes.pm:
	cp -a ${SRCDIR}/pve-manager/PVE/API2/$@ $@

pvemanagerlib.js:
	$(MAKE) -C ${SRCDIR}/pve-manager/www/manager6 clean $@
	cp -a ${SRCDIR}/pve-manager/www/manager6/$@ $@

pvemanager-mobile.js:
	$(MAKE) -C ${SRCDIR}/pve-manager/www/mobile clean $@
	cp -a ${SRCDIR}/pve-manager/www/mobile/$@ $@

proxmoxlib.js.patch:
	-${DIFFCMD} ${TOOLKITDIR}/proxmoxlib.js ${BUILDDIR}/proxmoxlib.js > $@

Nodes.pm.patch:
	-${DIFFCMD} ${PERLLIBDIR}/PVE/API2/Nodes.pm ${BUILDDIR}/Nodes.pm > $@

pvemanagerlib.js.patch:
	-${DIFFCMD} ${WWWJSDIR}/pvemanagerlib.js ${BUILDDIR}/pvemanagerlib.js > $@

pvemanager-mobile.js.patch:
	-${DIFFCMD} ${WWWTOUCHDIR}/pvemanager-mobile.js ${BUILDDIR}/pvemanager-mobile.js > $@
