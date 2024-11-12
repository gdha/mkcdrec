#!/bin/bash
#   FILE: bootia64.sh --
# AUTHOR: Guillaume RADDE ( Guillaume.Radde@Bull.net )
#   DATE: 06 April 2004
#
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
. ./Config.sh 2>/dev/null
. ${SCRIPTS}/common.sh 2>/dev/null

#We create an empty file to contain our boot.img

echo "---------------<entering bootia64>---------------" | tee -a ${LOG}
echo "create empty file to countain boot.img"

dd if=/dev/zero of=${TMP_DIR}/boot.img count=20000 bs=1024
mkfs -t vfat ${TMP_DIR}/boot.img
mount -o loop -t vfat ${TMP_DIR}/boot.img ${stagedir}

#Then we copy  all we need

echo "copying all we need into boot.img"
mkdir ${stagedir}/boot
#cp ${MKCDREC_DIR}/bootia64/* ${MKCDREC_DIR}/stage/boot

# if a dir countaining elilo.efi was specified, we use it .Otherwise, we use a default one

if [ -f ${ELILO_DIR}/elilo.efi ]; then
	echo "elilo.efi found. Copying into ${MKCDREC_DIR}/stage/boot " | tee -a ${LOG}
	cp -f ${ELILO_DIR}/elilo.efi ${MKCDREC_DIR}/stage/boot
else
	echo "elilo.efi not found. Using default one" | tee -a ${LOG}
fi

# we must build a elilo.conf file

if [ -z ${LINUX_KERNEL} ]; then
	KERNEL_TO_BOOT=vmlinuz-`uname -r`
else
	KERNEL_TO_BOOT=`basename ${LINUX_KERNEL}`
fi

APPEND="ramdisk=512000"
if [ ! -z "${SERIAL}" ]; then
   APPEND="ramdisk=512000 console=${SERIAL}"
fi

cat << EOF > ${MKCDREC_DIR}/stage/boot/elilo.conf
prompt
timeout=50

image=${KERNEL_TO_BOOT}
        label=linux
	initrd=initrd.img
        read-only
	append="${APPEND}"
EOF

copy_kernel ${MKCDREC_DIR}/stage/boot
cp -v ${MKCDREC_DIR}/initrd.img.gz ${stagedir}/boot/initrd.img

if [ -d /boot/efi/efi/recovery ]; then
    cp ${stagedir}/boot/* /boot/efi/efi/recovery/
    cp ${ISOFS_DIR}/rd-base.img.bz2 /boot/efi/efi/recovery/
fi

umount ${TMP_DIR}/boot.img

echo "---------------<leaving bootia64>---------------" | tee -a ${LOG}

