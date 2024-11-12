#!/bin/bash
# Copyright (c) 2000-2010 by Gratien D'haese for mkcdrec
# Please read LICENSE in the mkCDrec top directory
# $Id: bootx86_64.sh,v 1.7 2010/02/07 10:22:19 gdha Exp $
. ./Config.sh 2>/dev/null
. ${SCRIPTS}/ansictrl.sh 2>/dev/null

PATH=${MKCDREC_DIR}/bin:$PATH:

trap do_cleanup SIGTERM SIGINT

# cleanup files left in an unfinished state (overwrite do_cleanup of Config.sh)
do_cleanup()
{
    echo "Cleaning up files created by `basename $0` due to failure." >&2
    exit 1
}

copy_kernel() {
# $1 is copy destination
	echo "Copying kernel into $1" | tee -a ${LOG}
	cp -v ${LINUX_KERNEL} $1 2> /dev/null || \
	cp -v /boot/vmlinuz-`uname -r` $1 2> /dev/null || \
	cp -v /boot/efi/efi/redhat/vmlinuz-`uname -r` $1 2> /dev/null || \
	cp -v bzImage  $1 2> /dev/null || \
	cp -v zImage $1 2> /dev/null || \
	cp -v vmlinuz $1 2> /dev/null || \
	cp -v vmlinux $1 2> /dev/null || \
	cp -v linux $1 2> /dev/null || \
	cp -v /vmlinuz $1 2> /dev/null || \
	cp -v /boot/vmlinuz $1 2> /dev/null || \
	cp -v /boot/vmlinux $1 2> /dev/null || \
	error 1 "No kernel image was found!"
}

MakeSyslinuxCfg() {
  # Start preparing the syslinux.cfg file (SERIAL must be on top if available)
  # Serial port console used by isolinux when SERIAL is not an empty string
  if [ ! -z "${SERIAL}" ]; then
     echo "
     Warning: SERIAL console /dev/${SERIAL} will be used with syslinux!

     " | tee -a ${LOG}
     Port=`echo ${SERIAL} | cut -c5-`   # ttyS0, ttyS1 => 0, 1
     echo "SERIAL ${Port} ${BAUDRATE}" > ${ISOFS_DIR}/syslinux.cfg
  fi

  cat <<EOF >> ${ISOFS_DIR}/syslinux.cfg
DEFAULT 0
DISPLAY message.msg
PROMPT 1

LABEL 0
 KERNEL linux
EOF

  if [ "${INITRD_FS}" = "ramfs" ]; then
     cat <<EOF >> ${ISOFS_DIR}/syslinux.cfg
 APPEND initrd=initrd.gz ram=${RAM0} ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND} mkcdrec_on_usbkey

EOF
  else
     cat <<EOF >> ${ISOFS_DIR}/syslinux.cfg
 APPEND initrd=initrd.gz ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND} mkcdrec_on_usbkey
EOF
  fi

  # Add entry for recovery over serial line to .cfg and .msg
  if [ ! -z "${SERIAL}" ]; then # SERIAL="ttyS0"
     cat <<EOF >> ${ISOFS_DIR}/syslinux.cfg
LABEL 3
 KERNEL linux
 APPEND initrd=initrd.gz ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND} mkcdrec_on_usbkey
EOF

    cat ${SCRIPTS}/messages/serial.txt >> ${ISOFS_DIR}/message.msg

  else # SERIAL=""
    :
  fi # SERIAL=""
  # append EOF marker to message.msg file
  cat ${SCRIPTS}/messages/end.txt >> ${ISOFS_DIR}/message.msg

  # finished.

  local sysid=$(uname -nr)
  sysid=$(echo $sysid | tr -d '@/')
  sysid="$sysid on $(date +%Y-%m-%d)"
  perl -pi -e "s/SYSTEMID/$sysid/g" ${ISOFS_DIR}/message.msg

  echo "Directory is made and contains the following:" | tee -a ${LOG}
  ls -l ${ISOFS_DIR}/ | tee -a ${LOG}

  echo "Now running syslinux:" | tee -a ${LOG}
  umount ${USBKEY_DEV} 2>&1 | tee -a ${LOG}
  if [ "X${SAFE_SYSLINUX}" = "Xfalse" ]; then
    echo syslinux ${USBKEY_DEV} | tee -a ${LOG}
    syslinux ${USBKEY_DEV}
  else
    echo syslinux -s ${USBKEY_DEV} | tee -a ${LOG}
    syslinux -s ${USBKEY_DEV}
  fi
  mount -o shortname=winnt ${USBKEY_DEV} ${ISOFS_DIR} 2>&1 | tee -a ${LOG}
}

MakeIsolinuxCfg() {

# Serial port console used by isolinux when SERIAL is not an empty string
if [ ! -z "${SERIAL}" ]; then
     echo "
     Warning: SERIAL console /dev/${SERIAL} will be used with isolinux!
     
     " | tee -a ${LOG}
     Port=`echo ${SERIAL} | cut -c5-`	# ttyS0, ttyS1 => 0, 1
     echo "SERIAL ${Port} ${BAUDRATE}" > ${ISOFS_DIR}/isolinux/isolinux.cfg
fi


# For AUTODR we change the default into autobooting from CD - option 2
DefaultOpt=0
[ "${AUTODR}" = "y" ] && DefaultOpt=2 && cp -f ${SCRIPTS}/messages/isolinux_def2.txt ${ISOFS_DIR}/isolinux/message.msg
# Isolinux: keyword localboot is supported
	cat <<EOF >> ${ISOFS_DIR}/isolinux/isolinux.cfg
DEFAULT ${DefaultOpt}
TIMEOUT 200
DISPLAY message.msg
PROMPT 1

LABEL 0 
 localboot 0x80
LABEL 1
 localboot 0x00
LABEL 2
 KERNEL linux
 APPEND initrd=initrd.gz ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND}
EOF


# append EOF marker to message.msg file 
cat ${SCRIPTS}/messages/end.txt >> ${stagedir}/message.msg
}

Prepare_Syslinux() {
# prepare USB disk to make it bootable with syslinux
echo "Make USB key bootable with syslinux" | tee -a ${LOG}
copy_kernel ${ISOFS_DIR}/linux || Fail "No kernel image was found!"
cp -f ${MKCDREC_DIR}/initrd.img.gz ${ISOFS_DIR}/initrd.gz
cp -f ${SCRIPTS}/messages/message.usb ${ISOFS_DIR}/message.msg
}

Prepare_Isolinux() {
# create the isolinux/ directory on the CD-ROM
echo "Make CD-ROM bootable with isolinux" | tee -a ${LOG}
mkdir -p ${ISOFS_DIR}/isolinux
cp -f ${ISOLINUX} ${ISOFS_DIR}/isolinux/ || Fail "Cannot find isolinux.bin"
cp -p ${MEMDISK} ${ISOFS_DIR}/isolinux/
#cp -f ${ISOFS_DIR}/utilities/memtest.bin ${ISOFS_DIR}/isolinux/
copy_kernel ${ISOFS_DIR}/isolinux/linux || Fail "No kernel image was found!"

cp -f ${SCRIPTS}/messages/isolinux_def0.txt ${ISOFS_DIR}/isolinux/message.msg
cp -f ${SCRIPTS}/messages/mkcdrec.lss ${ISOFS_DIR}/isolinux/mkcdrec.lss
cp -f ${MKCDREC_DIR}/initrd.img.gz ${ISOFS_DIR}/isolinux/initrd.gz
}

##########################################
# MAIN part
##########################################
#

# set back/foreground color
color white black

MODE=`cat $TMP_DIR/MODE`
if [ x$MODE = xsuperrescue ]; then
   RAMDISK_SIZE=64
fi

echo "-------------< Entering bootx86_64.sh >-------------" | tee -a ${LOG}

# Kernels 2.2.x will return 2, kernel 2.4.x returns 4
kernel_minor_nr=`uname -a | awk '{print $3}' | cut -d. -f2`

# give me a kernel, or give me death
if [ -z ${LINUX_KERNEL} ]; then
     Find_Linux_kernel
fi
echo -e "\nLINUX_KERNEL=`echo ${LINUX_KERNEL}`\nWill copy the following kernel to the isolinux directory." | tee -a ${LOG}

# Is devfsd running? Need to know for root=/dev/ram0 or root=/dev/rd/0
ls -b /dev/.devfsd >/dev/null 2>&1   # empty when no DEVFS active
DEVFSD=$?
if [ x${DEVFS} = x0 ] || [ x${DEVFSD} = x1 ]; then
        # devfsd not running
        RAM0=/dev/ram0
else
        RAM0=/dev/rd/0
fi
# find out if pivot_root is present and that minor kernel version >2
which pivot_root >/dev/null 2>&1
pivot_root_found=$?   # 1 when not found

USBKEY_DEV=`cat ${TMP_DIR}/USBKEY_DEV`
if [ "${USBKEY_DEV}" != "" ]; then
	echo "Prepare the SYSLINUX track (for USB)" | tee -a ${LOG}
	# this is SYSLINUX for USB key
	Prepare_Syslinux
	echo "Create the syslinux.cfg file"  | tee -a ${LOG}
	MakeSyslinuxCfg
fi

# on x86_64 architecture we will always foresee a bootable isolinux track (on CD)
echo "Prepare the ISOLINUX track" | tee -a ${LOG}
# this is the ISOLINUX track (default)
Prepare_Isolinux
echo "Create the isolinux.cfg file"  | tee -a ${LOG}
MakeIsolinuxCfg

echo -e "-------------< Leaving bootx86_64.sh >-------------\n" | tee -a ${LOG}
