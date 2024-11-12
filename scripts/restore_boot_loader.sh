. ./Config.sh
. ./ansictrl.sh
. ./restore_common.sh

# Step 8: LILO/GRUB the system
# Mount the / partition on LOCALFS and if needed the /boot partition on /boot
cd /etc/recovery
# check the BOOTLOADER file to find out we were using LILO or GRUB
BOOTLOADER="`cat BOOTLOADER`"

if [ -f /etc/recovery/BOOTLOADER ]; then
   # system uses LILO/GRUB?
   BOOTLOADER="`cat /etc/recovery/BOOTLOADER`"
   if [ "${BOOTLOADER}" = "UNKNOWN" ]; then
        print "It seems that mkCDrec could not determine which bootloader\n"
        print "your system uses. Edit file /etc/recovery/BOOTLOADER and\n"
        print "change UNKNOWN into LILO or GRUB.\n"
        warn "After restoring it will not be possible to run lilo or grub!"
        exit 1
   fi
fi


# Find the ROOT/BOOT partitions
BOOTDEV=""
BOOTFS=""
ROOTDEV=""
ROOTFS="/"
for mdsk  in `ls mkfs.* md/mkfs.* lvm/mkfs.* 2>/dev/null`
do
        _dsk=`echo ${mdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/" | sed -e 's/%137/_/g'`
        grep -q ${dsk} /etc/recovery/To_Restore
        if [ $? -eq 1 ]; then
           # Oops, DevFS naming mixed up - find corresponding dsk
           DevFS_naming_mix             # dsk redefined
        fi
        cat /etc/recovery/To_Restore | grep ${dsk} | \
        { while read Line
        do
          ParseDevice ${Line}   # return Dev and _Dev
          Fs=`echo ${Line} | awk '{print $2}'`
          if [ "${Fs}" = "/" ]; then
                echo /dev/${Dev} > /tmp/ROOTDEV # e.g. /dev/hdb5
                echo /dev/${dsk} > /tmp/ROOTDSK # e.g. /dev/hdb
                echo ${Fs} > /tmp/ROOTFS
                echo ${Line} | awk '{print $3}' > /tmp/ROOTFStype
                echo ${Line} | awk '{print $4}' > /tmp/ROOTFSopt
          fi
          if [ "${Fs}" = "/boot" ]; then
                echo /dev/${Dev} > /tmp/BOOTDEV
                echo /dev/${dsk} > /tmp/BOOTDSK
                echo ${Fs} > /tmp/BOOTFS
                echo ${Line} | awk '{print $3}' > /tmp/BOOTFStype
                echo ${Line} | awk '{print $4}' > /tmp/BOOTFSopt
          fi
        done
        }
done
# reread the written variables from /tmp/ROOT*
ROOTDEV=`cat /tmp/ROOTDEV`
ROOTFS=`cat /tmp/ROOTFS`
ROOTFStype=`cat /tmp/ROOTFStype`
ROOTFSopt=`cat /tmp/ROOTFSopt`

if [ ! -z "${ROOTFSopt}" ]; then
   ROOTFSopt="-o ${ROOTFSopt}"
fi

# OK, we must have a ROOTDEV, BOOTDEV is optional
if [ -z "${ROOTDEV}" ]; then
   error 1 "${BOOTLOADER} does not make any sense if /  was not restored, but all was restored successfully!"
fi

mount -t ${ROOTFStype} ${ROOTFSopt} ${ROOTDEV} ${LOCALFS}
if [ $? -eq 1 ]; then
   error 1 "Mounting ${ROOTDEV} on ${LOCALFS} gave errors."
fi

if [ -f /tmp/BOOTDEV ]; then
   # not empty, try to mount it.
   # read the variables from /tmp/BOOT*
   BOOTDEV=`cat /tmp/BOOTDEV`
   BOOTFS=`cat /tmp/BOOTFS`
   BOOTFStype=`cat /tmp/BOOTFStype`
   BOOTFSopt=`cat /tmp/BOOTFSopt`
   if [ ! -z "${BOOTFSopt}" ]; then
      BOOTFSopt="-o ${BOOTFSopt}"
   fi
   mkdir ${LOCALFS}${BOOTFS} > /dev/null 2>&1
   mount -t ${BOOTFStype} ${BOOTFSopt} ${BOOTDEV} ${LOCALFS}${BOOTFS}
   if [ $? -eq 1 ]; then
        error 1 "Could not mount ${BOOTDEV} on ${LOCALFS}${BOOTFS}. Cannot configure ${BOOTLOADER}. Try it manually."
   fi
fi

# ROOT/BOOT devices are mounted - if LVM in use copy the lvmtab files
if [ ${lvmDevFound} -eq 1 ]; then
   cp /etc/lvmtab ${LOCALFS}/etc 2>/dev/null
   cp -dpR /etc/lvmtab.d ${LOCALFS}/etc
   cp -dpR /etc/lvmconf ${LOCALFS}/etc
   cp -dpR /etc/lvm ${LOCALFS}/etc
   # not sure yet we need to do a 'vgcfgrestore' ? probably not not to upset
   # other untouched volumegroups.
   # chroot ${LOCALFS} vgcfgrestore
fi

# check the BOOTLOADER value
if [ "${BOOTLOADER}" = "GRUB" ]; then
  # borrowed some code from grubconfig ;-) Thx
  if [ ! -x "`type -path grub`" ]; then
     print "I can't find grub on the system.\n"
     print "If you installed mkCDrec utilities try liloconfig instead!\n"
  else
     # grub command found, find config file...
     if grep -q /boot/grub/grub.conf 2>/dev/null `type -path grub` ; then
        grub_config=grub.conf
     else
        grub_config=menu.lst
     fi
     # get details of boot partition in grub format
     # /tmp/BOOTDEV contains e.g. /dev/hda1 and TARGET_DISK=/dev/sda
     if [ -f /tmp/BOOTDEV ]; then 
        TARGET_DISK=`cat /tmp/BOOTDSK`
        GRUB_PARTITION=`sed -e 's#'${TARGET_DISK}'##' </tmp/BOOTDEV` 
     else 
        TARGET_DISK=`cat /tmp/ROOTDSK`
        GRUB_PARTITION=`sed -e 's#'${TARGET_DISK}'##' </tmp/ROOTDEV` 
     fi
     if [ ${mdDevFound} -eq 1 ]; then
        # in case the TARGET_DISK is eg. /dev/md0 then we have to backtrack
        # to a real physical disk, eg. /dev/hda1
        md_dev=`echo ${TARGET_DISK} | cut -d"/" -f 3`   # md0
        GRUB_PARTITION=`grep ${md_dev} /etc/recovery/mdstat | tr ' ' '\n' | grep "\[0\]" | cut -d"[" -f 1`      # hda1 (boot device)
        # redefine TARGET_DISK for GRUB operation
        TARGET_DISK=`echo ${GRUB_PARTITION} | sed -e 's/[0-9]//g'`      #hda
        unset md_dev
     fi
     # strip all non-numerical characters before deducting one
     GRUB_PARTITION=`echo ${GRUB_PARTITION} | sed -e 's/[A-Za-z]//g'`
     GRUB_PARTITION=`expr ${GRUB_PARTITION} - 1`        # grub starts with zero

     # create a device map on the fly if none exists
     if [ -f ${LOCALFS}/boot/grub/device.map ] ; then
       GRUB_DEVMAP=${LOCALFS}/boot/grub/device.map
     else
       GRUB_DEVMAP=/tmp/grub-device.map
       grub --no-floppy --batch --device-map=${GRUB_DEVMAP} <<EOT
quit
EOT
     fi
     GRUB_DISK=`grep ${TARGET_DISK} ${GRUB_DEVMAP} | awk '{print $1}'` 

     GRUB_ROOT=`echo ${GRUB_DISK} | sed s/\)/,${GRUB_PARTITION}\)/` 
     print "Executing Grub command...\n" 
     ${DEBUG} grub --no-floppy --batch --device-map=${GRUB_DEVMAP} <<EOT 
root ${GRUB_ROOT} 
setup ${GRUB_DISK}
quit 
EOT
     if [ $? -eq 0 ]; then
        OK_TO_REBOOT=2
     else
        print "There were errors with grub command! Do not yet reboot!\n"
        print "Fix it first interactively \"chroot ${LOCALFS} grub\"\n"
        print "Or, if mkCDrec Utilities were installed, try \"chroot ${LOCALFS} grubconfig\"\n"
     fi # of $?
  fi # of type -path grub
elif [ "${BOOTLOADER}" = "LILO" ]; then
  if [ ! -x "`type -path lilo`" ]; then
     print "I can't find lilo on the system.\n"
     print "If you installed mkCDrec utilities try grubconfig instead!\n"
  else
     # lilo found, execute it
     print "Doing the lilo setup now...\n"
     ${DEBUG} chroot ${LOCALFS} lilo
     if [ $? -eq 0 ]; then
        OK_TO_REBOOT=2
     else
        echo "lilo in chroot failed - possibly no devices in /dev in chroot environment"
        echo "adapting lilo.conf..."
        # This sticks /mnt/local (or whatever $LOCALFS is) in front of /boot/
        # in lilo.conf and puts it in its traditional place in the ramdisk
        # The awk script checks for an 'other' section without loader specified
        # if loader is not specified it adds loader=$LOCALFS/boot/chain.b
        # (this is the default anyway)
        sed -e "s%/boot/%${LOCALFS}/boot/%" ${LOCALFS}/etc/lilo.conf | \
         awk -F= ' $1 == "other" { is_other = 1 }; \
                { print $0 }; \
                is_other == 1 \
                { printf "        loader='"${LOCALFS}"'/boot/chain.b\n" ; \
                is_other = 0 }; \
                ' > /etc/lilo.conf
        echo "Running lilo again..."
        ${DEBUG} lilo
        if [ $? -eq 0 ]; then
           OK_TO_REBOOT=2
        else
           print "Problems occured while executing the lilo command!\n"
           print "Try it with \"chroot ${LOCALFS} liloconfig\" instead.\n"
        fi # lilo
     fi # chroot lilo
  fi # of type -path lilo
elif [ "${BOOTLOADER}" = "ELILO" ]; then
  # FIXME: maybe add check for elilo.conf and elilo.efi files
  OK_TO_REBOOT=2
else
  print "Bootloader ${BOOTLOADER} is NOT yet supported!\n"
  print "Try your luck with \"chroot ${LOCALFS} liloconfig\" or\n"
  print "\"chroot ${LOCALFS} grubconfig\" instead.\n"
fi
