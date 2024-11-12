# This makefile uses dispatch.sh to build using an
# architecture-independent makefile, ie: Makefile.x86.	The makefile is
# chosen based on the value of Config.sh's BOOTARCH.

# Needed for ubuntu
SHELL=/bin/bash

# Note on a autofs system, you cannot mount devices on /mnt
mnt=/tmp

all: 
	scripts/dispatch.sh all

rescue: testonce
	scripts/dispatch.sh rescue

superrescue: testonce
	scripts/dispatch.sh superrescue

CD-ROM:
	scripts/dispatch.sh CD-ROM

path:
	scripts/dispatch.sh $@

device:
	scripts/dispatch.sh device

OBDR:
	scripts/dispatch.sh OBDR

USB-KEY:
	scripts/dispatch.sh $@

clean:
	scripts/dispatch.sh clean

test:
	scripts/dispatch.sh test

testonce:
	rm -f /tmp/.mkcdrec.tests.not.passed ; \
	if [ ! -f /tmp/.mkcdrec.tests.passed ]; then \
		make test ; \
	fi ;\
	if [ -f /tmp/.mkcdrec.tests.not.passed ]; then \
	   exit 1 ; \
	fi

help:
	scripts/dispatch.sh help

debug:
	mkdir -p ${mnt}/iso ${mnt}/img ${mnt}/img2 ${mnt}/img3
	mount -o loop /tmp/CDrec.iso ${mnt}/iso
	mount -o loop ${mnt}/iso/boot/boot.img ${mnt}/img
	cp ${mnt}/img/boot/initrd.img /tmp/initrd.img.gz
	cp ${mnt}/iso/rd-base.img.bz2 /tmp/
	rm -f /tmp/initrd.img
	gunzip -c /tmp/initrd.img.gz > /tmp/initrd.img
	rm -f /tmp/rd-base.img
	bunzip2 -c /tmp/iso/rd-base.img.bz2 > /tmp/rd-base.img
	mount -o loop /tmp/initrd.img ${mnt}/img2
	mount -o loop /tmp/rd-base.img ${mnt}/img3
	chroot ${mnt}/img3 

debugtmp:
	mkdir -p ${mnt}/img3
	bunzip2 -c /tmp/backup/rd-base.img.bz2 > /tmp/rd-base.img
	mount -o loop /tmp/rd-base.img ${mnt}/img3
	echo "rd-base is mounted on ${mnt}/img3"


undebug:
	-umount ${mnt}/img3
	rm -rf ${mnt}/img3
	rm -rf /tmp/rd-base.img

install:
	sed -e 's;^MKCDREC_HOME=/var/opt/mkcdrec;MKCDREC_HOME=$(PWD);' < contributions/mkcdrec >/usr/sbin/mkcdrec
	#echo "cd $(PWD); make \$$@" >/usr/sbin/mkcdrec
	chmod +x /usr/sbin/mkcdrec
	@echo "Command /usr/sbin/mkcdrec installed"
