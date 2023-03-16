DESTDIR=
WWWBASEDIR=${DESTDIR}/usr/share/javascript/proxmox-widget-toolkit
WWWJSDIR=${DESTDIR}/usr/share/pve-manager/js
PERLLIBDIR=${DESTDIR}/usr/share/perl5

all: proxmoxlib.js Nodes.pm pvemanagerlib.js

proxmoxlib.js:
	$(MAKE) -C ../proxmox-widget-toolkit/src clean $@
	cp -a ../proxmox-widget-toolkit/src/$@ $@

Nodes.pm:
	cp -a ../pve-manager/PVE/API2/$@ $@

pvemanagerlib.js:
	$(MAKE) -C ../pve-manager/www/manager6 clean $@
	cp -a ../pve-manager/www/manager6/$@ $@

install:
	install -d ${WWWBASEDIR}
	install -m 0644 proxmoxlib.js ${WWWBASEDIR}
	install -d ${PERLLIBDIR}/PVE/API2
	install -m 0644 Nodes.pm ${PERLLIBDIR}/PVE/API2
	install -d ${WWWJSDIR}
	install -m 0644 pvemanagerlib.js ${WWWJSDIR}

clean:
	rm -f proxmoxlib.js Nodes.pm pvemanagerlib.js

backup:
	mkdir -p orig
	cp -a ${WWWBASEDIR}/proxmoxlib.js orig/
	cp -a ${PERLLIBDIR}/PVE/API2/Nodes.pm orig/
	cp -a ${WWWJSDIR}/pvemanagerlib.js orig/

restore:
	install -d ${WWWBASEDIR}
	install -m 0644 orig/proxmoxlib.js ${WWWBASEDIR}
	install -d ${PERLLIBDIR}/PVE/API2
	install -m 0644 orig/Nodes.pm ${PERLLIBDIR}/PVE/API2
	install -d ${WWWJSDIR}
	install -m 0644 orig/pvemanagerlib.js ${WWWJSDIR}

cleanbackup:
	rm -f orig/proxmoxlib.js orig/Nodes.pm orig/pvemanagerlib.js
