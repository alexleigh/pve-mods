include ../defines.mk
include ../common.mk

SRCDIR=../..

all: proxmoxlib.js Nodes.pm pvemanagerlib.js pvemanager-mobile.js

.PHONY: install
install:
	install -d ${TOOLKITDIR}
	install -m 0644 proxmoxlib.js ${TOOLKITDIR}
	install -d ${PERLLIBDIR}/PVE/API2
	install -m 0644 Nodes.pm ${PERLLIBDIR}/PVE/API2
	install -d ${WWWJSDIR}
	install -m 0644 pvemanagerlib.js ${WWWJSDIR}
	install -d ${WWWTOUCHDIR}
	install -m 0644 pvemanager-mobile.js ${WWWTOUCHDIR}

.PHONY: clean
clean:
	-rm -f proxmoxlib.js Nodes.pm pvemanagerlib.js pvemanager-mobile.js

.PHONY: backup
backup:
	mkdir -p orig
	cp -a ${TOOLKITDIR}/proxmoxlib.js orig/
	cp -a ${PERLLIBDIR}/PVE/API2/Nodes.pm orig/
	cp -a ${WWWJSDIR}/pvemanagerlib.js orig/
	cp -a ${WWWTOUCHDIR}/pvemanager-mobile.js orig/

.PHONY: restore
restore:
	install -d ${TOOLKITDIR}
	install -m 0644 orig/proxmoxlib.js ${TOOLKITDIR}
	install -d ${PERLLIBDIR}/PVE/API2
	install -m 0644 orig/Nodes.pm ${PERLLIBDIR}/PVE/API2
	install -d ${WWWJSDIR}
	install -m 0644 orig/pvemanagerlib.js ${WWWJSDIR}
	install -d ${WWWTOUCHDIR}
	install -m 0644 orig/pvemanager-mobile.js ${WWWTOUCHDIR}

.PHONY: cleanbackup
cleanbackup:
	-rm -f orig/proxmoxlib.js orig/Nodes.pm orig/pvemanagerlib.js orig/pvemanager-mobile.js
