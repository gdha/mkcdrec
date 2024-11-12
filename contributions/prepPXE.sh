#!/bin/bash
#
# $Id: prepPXE.sh,v 1.6 2007/11/13 14:38:13 gdha Exp $
#
#   FILE: prepPXE.sh
# AUTHOR: Gratien D'haese
#   DATE: 23 September 2003
#
# Copyright (C) 2003 Gratien D'haese
# All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

if [ -f ../Config.sh ]; then
	cd ..
	. ./Config.sh 2>/dev/null
	cd -
else
	. ./Config.sh 2>/dev/null
fi

IN=/mnt/_mkcdrec/backup
                                                                                
USAGE="[OPTION]...
                                                                                
  -h, -?   print this message
  -i path  set the input path   [ $IN ]"

if [ "`whoami`" != "root" ]; then
	echo Must be root!!!
	exit 1
fi

IMG_1=`mktemp /tmp/img.XXXXXX`
IMG_2=`mktemp /tmp/img.XXXXXX`
DIR_1=`mktemp -d /tmp/dir.XXXXXX`
DIR_2=`mktemp -d /tmp/dir.XXXXXX`
DIR_3=`mktemp -d /tmp/dir.XXXXXX`

trap 'rm -f $IMG_1 $IMG_2 $DIR_1 $DIR_2 $DIR_3' SIGHUP SIGINT SIGTERM EXIT

while :;
	do case "$1" in
		-h | "-?" )
			echo -e usage: ${0##*/} "$USAGE" >&2
			exit 1 ;;
		-i )
			IN=$2
			shift ;;
		-?* )
			echo "${0##*/}: unrecognised option: $1" >&2
			exit 1 ;;
		* )
			break ;;
	esac
	shift
done

if [ ! -d $IN ]; then
	echo "${0##*/}: $IN does not exist" >&2
	exit 1
fi

echo "******************************************************************"
echo "*		Prepare PXE root environment for mkCDrec         *"
echo "*		See presentation \"Making mkCDrec PXE aware\"      *"
echo "*		by Gratien D'haese - 23 September 2003           *"
echo "******************************************************************"

# unpack rd-base.img into $IN/..
echo "Unpack rd-base.img into $IMG_1"
bunzip2 -c $IN/rd-base.img.bz2 > $IMG_1
echo mounting rd-base.img at $DIR_1
mount -o loop $IMG_1 $DIR_1
cd $DIR_1
cp -R . $IN/..
cd -
umount $DIR_1

# unpack initrd.img into ../$IN
echo "Unpack initrd.img into $IMG_2"
gunzip -c ${MKCDREC_DIR}/initrd.img.gz > $IMG_2
echo mounting initrd.img at $DIR_2
mount -o loop $IMG_2 $DIR_2
cd $DIR_2
cp -R . /$IN/../initrd/
cd -
umount $DIR_2

echo "move linux kernel to boot/ directory"
mount -o loop $IN/bootflop.img $DIR_3
mkdir -p $IN/../boot
cp $DIR_3/linux $IN/../boot/

echo "Create default PXE configuration file"
cp $DIR_3/message.msg $IN/../../pxes/
cp ${SCRIPTS}/messages/mkcdrec.lss $IN/../../pxes/
host `df -P $IN | tail -n 1 | cut -d: -f1` | tail -n 1 | awk '{print $4}' >/tmp/IP.$$
BS=`cat /tmp/IP.$$`
rm -f /tmp/IP.$$
umount $DIR_3

cat > $IN/../../pxes/pxelinux.cfg/default <<EOF
default 2
timeout 40
display message.msg
F1 message.msg

label 0
label 1
label 2
  kernel ../_mkcdrec/boot/linux
  append rw root=/dev/nfs nfsroot=${BS}:/tftpboot/_mkcdrec ip=both acpi=off ${KERNEL_APPEND}
EOF

echo "Your default PXE configuration file is the following:"
cat  $IN/../../pxes/pxelinux.cfg/default

echo "Correct NFS backup into NET method (for PXE)"
cd $IN/../etc/recovery
fn=`ls Backup_*`
echo "NET" > $fn
echo "Correct RESTORE_PATH when available..."
echo "/backup" >RESTORE_PATH
cd -

echo done.
