DESTDIR=
TOOLKITDIR=${DESTDIR}/usr/share/javascript/proxmox-widget-toolkit
WWWBASEDIR=${DESTDIR}/usr/share/pve-manager
WWWJSDIR=${WWWBASEDIR}/js
WWWTOUCHDIR=${WWWBASEDIR}/touch
PERLLIBDIR=${DESTDIR}/usr/share/perl5

all: proxmoxlib.js Nodes.pm pvemanagerlib.js pvemanager-mobile.js

proxmoxlib.js:
	$(MAKE) -C ../proxmox-widget-toolkit/src clean $@
	cp -a ../proxmox-widget-toolkit/src/$@ $@

Nodes.pm:
	cp -a ../pve-manager/PVE/API2/$@ $@

pvemanagerlib.js:
	$(MAKE) -C ../pve-manager/www/manager6 clean $@
	cp -a ../pve-manager/www/manager6/$@ $@

pvemanager-mobile.js:
	$(MAKE) -C ../pve-manager/www/mobile clean $@
	cp -a ../pve-manager/www/mobile/$@ $@

install:
	install -d ${TOOLKITDIR}
	install -m 0644 proxmoxlib.js ${TOOLKITDIR}
	install -d ${PERLLIBDIR}/PVE/API2
	install -m 0644 Nodes.pm ${PERLLIBDIR}/PVE/API2
	install -d ${WWWJSDIR}
	install -m 0644 pvemanagerlib.js ${WWWJSDIR}
	install -d ${WWWTOUCHDIR}
	install -m 0644 pvemanager-mobile.js ${WWWTOUCHDIR}

clean:
	rm -f proxmoxlib.js Nodes.pm pvemanagerlib.js pvemanager-mobile.js

backup:
	mkdir -p orig
	cp -a ${TOOLKITDIR}/proxmoxlib.js orig/
	cp -a ${PERLLIBDIR}/PVE/API2/Nodes.pm orig/
	cp -a ${WWWJSDIR}/pvemanagerlib.js orig/
	cp -a ${WWWTOUCHDIR}/pvemanager-mobile.js orig/

restore:
	install -d ${TOOLKITDIR}
	install -m 0644 orig/proxmoxlib.js ${TOOLKITDIR}
	install -d ${PERLLIBDIR}/PVE/API2
	install -m 0644 orig/Nodes.pm ${PERLLIBDIR}/PVE/API2
	install -d ${WWWJSDIR}
	install -m 0644 orig/pvemanagerlib.js ${WWWJSDIR}
	install -d ${WWWTOUCHDIR}
	install -m 0644 orig/pvemanager-mobile.js ${WWWTOUCHDIR}

cleanbackup:
	rm -f orig/proxmoxlib.js orig/Nodes.pm orig/pvemanagerlib.js orig/pvemanager-mobile.js
