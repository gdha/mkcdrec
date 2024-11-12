#!/bin/bash
# Copyright (c) 2000-2008 by Gratien D'haese for mkcdrec
# Please read LICENSE in the mkCDrec top directory
# $Id: bootflop.sh,v 1.47 2009/09/10 05:44:52 gdha Exp $

# source the config file and common functions
. ./Config.sh 2>/dev/null
. ${SCRIPTS}/ansictrl.sh 2>/dev/null
. ${SCRIPTS}/common.sh 2>/dev/null

PATH=${MKCDREC_DIR}/bin:$PATH:  # add our ./bin for mformat if missing on system

SAFE_SYSLINUX=$1
#set -o history
trap do_cleanup SIGTERM SIGINT
#trap check_rc DEBUG

###---------###
# cleanup files left in an unfinished state (overwrite do_cleanup of Config.sh)
do_cleanup()
{
    echo "Cleaning up files created by `basename $0` due to failure." >&2
    umount ${FLOPPY_DIR}/bootflop.img 2> /dev/null
    rm -f ${FLOPPY_DIR}/bootflop.img .mtools.conf
    exit 1
}

###---------###
Bootfloppy_Full () {
###############

# bootfloppy is full, cannot use isolinux because FORCE_SYSLINUX was set to "true"
# Must fail.
Fail "bootfloppy is FULL! Edit Config.sh file and change BOOT_FLOPPY_DENSITY=HD to ED.\nOr, set FORCE_SYSLINUX=false."

}

###---------###
MakeBootFloppy() {
  # FLOPPY_DIR can be $TMP_DIR or /tmp (=1.722Mb floppy)
  echo Populating the floppy filesystem
  modprobe msdos 2>/dev/null
  mount -o loop -t msdos ${FLOPPY_DIR}/bootflop.img ${stagedir}
  if [ $? -ne 0 ]; then
     error 1 "Could not mount bootflop.img. Make sure that the \"msdos\" filesystem is in your kernel (or exist as module)."
  fi

  echo "Copy your linux kernel to the boot floppy image." | tee -a ${LOG}
  # give me a kernel, or give me death
  if [ -z ${LINUX_KERNEL} ]; then
     Find_Linux_kernel
  fi
  echo -e "\nLINUX_KERNEL=`echo ${LINUX_KERNEL}`\nWill copy the following kernel to the boot floppy." | tee -a ${LOG}

  # if LINUX_KERNEL has not returned a valid kernel, than the following list
  # will be scanned and the first its find will be copied to the boot floppy.
  # Be careful: in some circumstances one could grap a different kernel than
  # the copied modules (to rd-base). To be realy, realy sure fill the parameter
  # LINUX_KERNEL up with the correct path/kernel in the Config.sh file.
  ( trap "" DEBUG; copy_kernel ${stagedir}/linux || \
  ( echo "No kernel image was found! Please define \"LINUX_KERNEL\" in Config.sh"  1>&2 ) ) | tee -a ${LOG}

  echo -e "\nCopy the initial ram disk image to the boot floppy image." | tee -a ${LOG}
  cp -v initrd.img.gz ${stagedir}/initrd.gz 
  if [ $? -eq 1 ]; then
        Bootfloppy_Full
  fi
  cp -f ${SCRIPTS}/messages/message.txt ${stagedir}/message.msg
  if [ $? -eq 1 ]; then
        Bootfloppy_Full
  fi
  cp -f ${SCRIPTS}/messages/mkcdrec.lss ${stagedir}/
  if [ $? -eq 1 ]; then
        Bootfloppy_Full
  fi

  # find out if pivot_root is present and that minor kernel version >2
  which pivot_root >/dev/null 2>&1
  pivot_root_found=$?   # 1 when not found

  # Serial port console used by syslinux when SERIAL is not an empty string
  if [ ! -z "${SERIAL}" ]; then
     echo "
     Warning: SERIAL console /dev/${SERIAL} will be used with syslinux!
     
     " | tee -a ${LOG}
     Port=`echo ${SERIAL} | cut -c5-`   # ttyS0, ttyS1 => 0, 1
     echo "SERIAL ${Port} ${BAUDRATE}" > ${stagedir}/syslinux.cfg
  fi
  # plain old syslinux.cfg is useable on floppies and CDROM
  # syslinux: keyword "localboot" is not yet supported - you see errors by booting (harmless)
  echo "Make syslinux.cfg file" | tee -a ${LOG}
        cat <<EOF >> ${stagedir}/syslinux.cfg
DEFAULT 2
TIMEOUT 50
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

  if [ ! -z "${SERIAL}" ]; then # SERIAL="ttyS0"
        cat <<EOF >> ${stagedir}/syslinux.cfg
LABEL 3
 KERNEL linux
 APPEND initrd=initrd.gz ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND}
EOF
       cat ${SCRIPTS}/messages/serial.txt >> ${stagedir}/message.msg
  else # SERIAL=""
       :
  fi # end of SERIAL

  # append EOF marker to message.msg file 
  cat ${SCRIPTS}/messages/end.txt >> ${stagedir}/message.msg
  echo -e "\n*** Size of boot floppy:" | tee -a ${LOG}

  df -kP ${stagedir} | tee -a ${LOG}
  echo -e "\n" | tee -a ${LOG}
  Used_on_floppy_Kb=`df -kP ${stagedir} | tail -n 1 | awk '{print $3}'`
  if [ ${Used_on_floppy_Kb} -gt 2863 ]; then
     echo "Error: syslinux: bootflop.img is full.
Emergency Stop.
Please install syslinux with isolinux support (e.g. v2.x)!" >> ${LOG}
     umount ${FLOPPY_DIR}/bootflop.img
     Fail "Syslinux: bootflop.img is full. Please install higher version of syslinux!"
  fi

  local sysid=$(uname -nr)
  sysid=$(echo $sysid | tr -d '@/')
  sysid="$sysid on $(date +%Y-%m-%d)"
  perl -pi -e "s/SYSTEMID/$sysid/g" ${stagedir}/message.msg

  RunSyslinux

  # ${MKCDREC_DIR}/tmp/bootflop.img is a 1.44/2.88 bootfloppy
  # /tmp/bootflop.img is a 1.722 Bootfloppy (do not cp to CD!)
  echo "Copy the 1.44 or 2.88 Mb bootflop.img to ISOFS_DIR" | tee -a ${LOG}
  cp -fv ${MKCDREC_DIR}/tmp/bootflop.img ${ISOFS_DIR}/ | tee -a ${LOG}
  if [ -f ${ISOFS_DIR}/isolinux/isolinux.cfg ]; then
     cp -f ${MKCDREC_DIR}/tmp/bootflop.img ${ISOFS_DIR}/isolinux/
  fi
  echo "Boot floppy is ready." | tee -a ${LOG}
}

###---------###
RunSyslinux () {
###########
if [ ! -f ${FLOPPY_DIR}/bootflop.img ]; then
   echo "Missing bootflop.img; skip syslinux phase" | tee -a ${LOG}
   return
fi
echo "Setting up bootable characteristics of the floppy (syslinux)" | tee -a ${LOG}
if [ "X${SAFE_SYSLINUX}" = "Xfalse" ]; then
  echo syslinux ${FLOPPY_DIR}/bootflop.img | tee -a ${LOG} 
  syslinux ${FLOPPY_DIR}/bootflop.img
else
  echo syslinux -s ${FLOPPY_DIR}/bootflop.img | tee -a ${LOG}
  syslinux -s ${FLOPPY_DIR}/bootflop.img
fi
}

###---------###
Backup_floppy_image () {
###################
# Copy a 1.44/1.722 Mb bootfloppy image to ISOFS_DIR/floppy/bootflop.img
# when it is possible (if size permits).
# Handy in case the bootflop.img on ISOFS_DIR is a 2.88 Mb one and the PC
# cannot boot from CD-ROM, then as a last resort on can dd this image to
# floppy.
# Why? in case you loose the physical floppy or it was disabled in Config.sh.
case ${BOOT_FLOPPY_DENSITY} in
HD) # copy 1.44 Mb image to its place
     # FLOPPY_DIR=${TMP_DIR}
     # cp ${TMP_DIR}/bootflop.img ${ISOFS_DIR}/floppy/
     echo "bootflop.img on CD is a 1.44 Mb image (dd to /dev/fd0 works any time)" | tee -a ${LOG}
   ;;
H1722|ED) # copy the 1.722 Mb image to its place
      # the ISOFS_DIR/bootflop.img is too big (2.88 Mb) for a floppy!
      FLOPPY_DIR=/tmp     
      # we mount the 2.88 Mb floppy image and check the used space
      mkdir -p ${TMP_DIR}/floppy.ED.img
      mount -o loop -t msdos ${TMP_DIR}/bootflop.img ${TMP_DIR}/floppy.ED.img
      Used_on_floppy_Kb=`df -kP ${TMP_DIR}/floppy.ED.img | tail -n 1 | awk '{print $3}'`
      if [ ${Used_on_floppy_Kb} -le 1664 ]; then
        # Lucky! We can make a backup floppy to boot from if ever needed
        mount -o loop -t msdos ${FLOPPY_DIR}/bootflop.img ${stagedir}
        cp ${TMP_DIR}/floppy.ED.img/* ${stagedir}/
        umount ${FLOPPY_DIR}/bootflop.img
        RunSyslinux
        echo "Made an extra 1.722 Mb bootflop.img into floppy/ of the CD" | tee -a ${LOG}
        mkdir -p ${ISOFS_DIR}/floppy
        cp ${FLOPPY_DIR}/bootflop.img ${ISOFS_DIR}/floppy
      else
        echo "Unfortunately current bootfloppy image is too big to make an extra 1.722 Mb image into floppy/ directory on the CD-ROM" | tee -a ${LOG}
      fi
      umount ${TMP_DIR}/bootflop.img
   ;;
*)  Fail "Failed in bootflop.sh function Backup_floppy_image! Impossible situation."
   ;;
esac

}

###---------###
Format_Bootfloppy () {
# kludge to get around having to use a real floppy
export MTOOLSRC=./.mtools.conf
echo "drive a: file=\"${TMP_DIR}/bootflop.img\" mformat_only" > .mtools.conf
echo "Busy mformat the boot floppy image..." | tee -a ${LOG}
if [ "${BOOT_FLOPPY_DENSITY}" = "HD" ]; then
 dd if=/dev/zero of=${TMP_DIR}/bootflop.img count=2880 bs=512
 mformat -t 80 -h 2 -s 18 A: 
else
 dd if=/dev/zero of=${TMP_DIR}/bootflop.img count=5760 bs=512
 mformat -t 80 -h 2 -s 36 A:
# Also create floppy image of density "${BOOT_FLOPPY_DENSITY}" = "H1722" 
# we do them both for our Backup_floppy_image function
   echo "drive a: file=\"/tmp/bootflop.img\" mformat_only" > .mtools.conf
   dd if=/dev/zero of=/tmp/bootflop.img count=3444 bs=512
   mformat -t 82 -h 2 -s 21 A:
fi
rm -f .mtools.conf
}

###---------###
Prepare_Isolinux () {
  echo "Make CD-ROM bootable with isolinux." | tee -a ${LOG}

  # create isolinux directory on ISO image
  mkdir -p ${ISOFS_DIR}/isolinux

  # copy the linux kernel to isolinux/ dir
  if [ -z ${LINUX_KERNEL} ]; then
     Find_Linux_kernel
  fi
  echo -e "\nLINUX_KERNEL=`echo ${LINUX_KERNEL}`\nWill copy the following kernel to the isolinux directory." | tee -a ${LOG}

  # if LINUX_KERNEL has not returned a valid kernel, than the following list
  # will be scanned and the first its find will be copied to the boot floppy.
  # Be careful: in some circumstances one could grap a different kernel than
  # the copied modules (to rd-base). To be realy, realy sure fill the parameter
  # LINUX_KERNEL up with the correct path/kernel in the Config.sh file.
  ( trap "" DEBUG; copy_kernel ${ISOFS_DIR}/isolinux/linux || \
  ( echo "No kernel image was found! Please define \"LINUX_KERNEL\" in Config.sh"  1>&2 ) ) | tee -a ${LOG}

  # Start preparing the isolinux.cfg file (SERIAL must be on top if available)
  # Serial port console used by isolinux when SERIAL is not an empty string
  if [ ! -z "${SERIAL}" ]; then
     echo "
     Warning: SERIAL console /dev/${SERIAL} will be used with isolinux!
     
     " | tee -a ${LOG}
     Port=`echo ${SERIAL} | cut -c5-`   # ttyS0, ttyS1 => 0, 1
     echo "SERIAL ${Port} ${BAUDRATE}" > ${ISOFS_DIR}/isolinux/isolinux.cfg
  fi


  # copy the stuff we need to isolinux dir:
  cp -f ${ISOLINUX} ${ISOFS_DIR}/isolinux/ || Fail "Cannot find isolinux.bin"
  cp -p ${MEMDISK} ${ISOFS_DIR}/isolinux/
  cp -f ${SCRIPTS}/messages/isolinux_def0.txt ${ISOFS_DIR}/isolinux/message.msg
  cp -f ${SCRIPTS}/messages/mkcdrec.lss ${ISOFS_DIR}/isolinux/mkcdrec.lss
  cp -f ${MKCDREC_DIR}/initrd.img.gz ${ISOFS_DIR}/isolinux/initrd.gz
  # For AUTODR we change the default into autobooting from CD - option 2
  DefaultOpt=0 
  # For AUTODR mode use the approriate message.msg file
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
EOF

  if [ "${INITRD_FS}" = "ramfs" ]; then
     cat <<EOF >> ${ISOFS_DIR}/isolinux/isolinux.cfg
 APPEND initrd=initrd.gz ram=${RAM0} ramdisk_size=$(((${RAMDISK_SIZE}+512)*1024)) ${KERNEL_APPEND}

EOF
  else
     cat <<EOF >> ${ISOFS_DIR}/isolinux/isolinux.cfg
 APPEND initrd=initrd.gz ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND}
EOF
  fi


  # Add entry for recovery over serial line to .cfg and .msg
  if [ ! -z "${SERIAL}" ]; then # SERIAL="ttyS0"
     cat <<EOF >> ${ISOFS_DIR}/isolinux/isolinux.cfg
LABEL 3
 KERNEL linux
 APPEND initrd=initrd.gz ramdisk_size=$((${RAMDISK_SIZE}*1024)) ${KERNEL_APPEND}
EOF

    cat ${SCRIPTS}/messages/serial.txt >> ${ISOFS_DIR}/isolinux/message.msg

  else # SERIAL=""
    :
  fi # SERIAL=""
  # append EOF marker to message.msg file 
  cat ${SCRIPTS}/messages/end.txt >> ${ISOFS_DIR}/isolinux/message.msg
  
  # finished.

  local sysid=$(uname -nr)
  sysid=$(echo $sysid | tr -d '@/')
  sysid="$sysid on $(date +%Y-%m-%d)"
  perl -pi -e "s/SYSTEMID/$sysid/g" ${ISOFS_DIR}/isolinux/message.msg

  echo "Isolinux directory is made and contains the following:" | tee -a ${LOG}
  ls -l ${ISOFS_DIR}/isolinux/ | tee -a ${LOG}
}

###---------###
Prepare_Syslinux () {
  echo "Make USB key bootable with syslinux." | tee -a ${LOG}

  # copy the linux kernel to .../ dir
  if [ -z ${LINUX_KERNEL} ]; then
     Find_Linux_kernel
  fi
  echo -e "\nLINUX_KERNEL=`echo ${LINUX_KERNEL}`\nWill copy the following kernel." | tee -a ${LOG}

  # if LINUX_KERNEL has not returned a valid kernel, than the following list
  # will be scanned and the first its find will be copied to the boot floppy.
  # Be careful: in some circumstances one could grap a different kernel than
  # the copied modules (to rd-base). To be realy, realy sure fill the parameter
  # LINUX_KERNEL up with the correct path/kernel in the Config.sh file.
  ( trap "" DEBUG; copy_kernel ${ISOFS_DIR}/linux || \
  ( echo "No kernel image was found! Please define \"LINUX_KERNEL\" in Config.sh"  1>&2 ) ) | tee -a ${LOG}

  # Start preparing the syslinux.cfg file (SERIAL must be on top if available)
  # Serial port console used by isolinux when SERIAL is not an empty string
  if [ ! -z "${SERIAL}" ]; then
     echo "
     Warning: SERIAL console /dev/${SERIAL} will be used with syslinux!
     
     " | tee -a ${LOG}
     Port=`echo ${SERIAL} | cut -c5-`   # ttyS0, ttyS1 => 0, 1
     echo "SERIAL ${Port} ${BAUDRATE}" > ${ISOFS_DIR}/syslinux.cfg
  fi


  # copy the stuff we need to ISOFS_DIR dir:
  cp -f ${SCRIPTS}/messages/message.usb ${ISOFS_DIR}/message.msg
  cp -f ${MKCDREC_DIR}/initrd.img.gz ${ISOFS_DIR}/initrd.gz
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

######################################################################################
#
# MAIN part
#

# set back/foreground color
color white black

MODE=`cat $TMP_DIR/MODE`
if [ x$MODE = xsuperrescue ]; then
   RAMDISK_SIZE=64
fi

# Is devfsd running? Need to know for root=/dev/ram0 or root=/dev/rd/0
ls -b /dev/.devfsd >/dev/null 2>&1   # empty when no DEVFS active
DEVFSD=$?
if [ x${DEVFS} = x0 ] || [ x${DEVFSD} = x1 ]; then
	# devfsd not running
	RAM0=/dev/ram0
else
	RAM0=/dev/rd/0
fi

echo "-------------< Entering bootflop.sh >-------------" | tee -a ${LOG}

# Kernels 2.2.x will return 2, kernel 2.4.x returns 4
kernel_minor_nr=`uname -a | awk '{print $3}' | cut -d. -f2`

if [ "${FORCE_SYSLINUX}" = "true" ]; then
   # here follows the SYSLINUX track
   Format_Bootfloppy    # create with mformat the bootflop.img
   FLOPPY_DIR=${TMP_DIR}
   MakeBootFloppy

   # Foresee a skip this question in Config.sh (PROMPT_BOOT_FLOPPY)
   if [ "${PROMPT_BOOT_FLOPPY}" = "1" ]; then

    print "\n${c_higreen}Rescue boot floppy${c_end}\n"
    askyn N "Do you want a real physical boot floppy?"
    if [ $? -eq 1 ]; then       # 1 is yes
        if [ ${BOOT_FLOPPY_DENSITY} = "HD" ]; then
          FLOPPY_DENSITY_MB="1.44"
          FLOPPY_DIR=${TMP_DIR}
          FLOPPY_DEVICE="/dev/fd0"
        elif [ ${BOOT_FLOPPY_DENSITY} = "H1722" ]; then
          FLOPPY_DENSITY_MB="1.722"
          FLOPPY_DIR=/tmp
          FLOPPY_DEVICE="/dev/fd0H1722"
          if [ ! -b ${FLOPPY_DEVICE} ]; then
            mknod ${FLOPPY_DEVICE} b 2 60
          fi
          MakeBootFloppy
        else
          Fail "Unable to make boot floppy for this density."
        fi # BOOT_FLOPPY_DENSITY
        while ( true )
        do
         clear
         printat 7 1 "\n${c_hired}Please insert a ${FLOPPY_DENSITY_MB} Mb floppy${c_end}\n"
         prompt
         print "\nPlease wait while writing a real boot floppy for you..."
         dd if=${FLOPPY_DIR}/bootflop.img of=${FLOPPY_DEVICE}
         if [ $? -eq 0 ]; then
                break
         fi
        done
   fi # make a phys. floppy
  fi # end of PROMPT_BOOT_FLOPPY

  # copy a backup floppy image (1.44 or 1.722 Mb) to ISOFS_DIR/floppy in case
  # we loose the physical floppy or when it was never made (in some cases you
  # will send me a greeting card I did this ;-)
  Backup_floppy_image
  rm -f /tmp/bootflop.img

else
   USBKEY_DEV=`cat ${TMP_DIR}/USBKEY_DEV`
   if [ "${USBKEY_DEV}" != "" ]; then
      # this is SYSLINUX for USB key
      Prepare_Syslinux
   else
      # this is the ISOLINUX track (default)
      Prepare_Isolinux
   fi
fi


echo -e "-------------< Leaving bootflop.sh >-------------\n" | tee -a ${LOG}
