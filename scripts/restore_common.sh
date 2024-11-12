# $Id: restore_common.sh,v 1.63 2008/12/12 12:15:37 gdha Exp $
# restore_common.sh: put common functions for start-restore.sh, dp/tsm-
# restore.sh, clone-dsk.sh here. This script will be dotted by these scripts.
#
# Copyright (C) 2001-2008 - Gratien D'haese - IT3 Consultants
# See COPYING license in mkCDrec top directory
#

#-----<--------->-------
DeviceCdrom () {
CDROM=`grep cdrom /proc/mounts | awk '{print $1}'`
}
#-----<--------->-------

Step1 () {
# Step 1: check if with this CD was the result of a backup, or just Rescue
ls /etc/recovery/ | grep Backup_made > /dev/null
if [ $? -eq 1 ]; then
        # Rescue CD-ROM only
        error 1 "Cannot restore any data - RESCUE CD-ROM only"
fi
if [ ! -f /etc/recovery/To_Restore ]; then
        # Nothing to restore anyway
        error 1 "Sorry, no filesystems to restore"
fi
RESTORE_DEV=`cat /etc/recovery/Backup_made_*`
# In case we need to load special modules we can do it here
case ${RESTORE_DEV} in
        CDROM)  ;;
        DISK)   /etc/recovery/mount.sh
                ;;
        NFS)    modprobe -q nfs >/dev/null 
                /etc/recovery/mount.sh
                ;;
        TAPE)   ;;
        NET)    ;;
esac
if [ -f /etc/recovery/BOOTLOADER ]; then
   # system uses LILO/GRUB?
   BOOTLOADER="`cat /etc/recovery/BOOTLOADER`"
   if [ "${BOOTLOADER}" = "UNKNOWN" ]; then
        print "It seems that mkCDrec could not determine which bootloader\n"
        print "your system uses. Edit file /etc/recovery/BOOTLOADER and\n"
        print "change UNKNOWN into LILO or GRUB.\n"
        warn "After restoring it will not be possible to run lilo or grub!"
   fi
fi
}
#-----<--------->-------

Step2 () {
# Step 2: try to find the location of the FS archives
if [ ! -f /etc/recovery/RESTORE_PATH ] && [ ! -f /etc/recovery/TAPE_DEV ]; then
        # should never happen ;-) Murphy...
        error 1 "I'm puzzled - cannot find the RESTORE_PATH, nor tape device!"
fi

# Where are the backups (TAPE, CD, DISK, NFS)
if [ -f /etc/recovery/TAPE_DEV ]; then
  # archives are on tape
  RESTORE_PATH=""
  REMOTE_COMMAND="`cat /etc/recovery/REMOTE_COMMAND`"
  tape_dev=`cat /etc/recovery/TAPE_DEV`
  Tape_local_or_remote  # check if tape is local or remote
  $DEBUG $REMOTE_COMMAND $RHOST mt -f ${tape_dev}  rewind >/dev/null 2>&1
  if [ $? -eq 1 ]; then
    error 1 "Is tape device ${tape_dev} properly attached?
When the problem has been resolved, try again"
  fi
  BACKUPS_ON_MT=1
  print "\nThe backups are on ${tape_dev}.\n"
  # set a default blocksize of 0 - needed for e.g. Transtec
  $DEBUG $REMOTE_COMMAND $RHOST mt -f ${tape_dev} setblk 0
  # check for OBDR: need to fsf a bit
  if [ -f /etc/recovery/OBDR ]; then
        print "\nOBDR tape: positioning tape...\n"
        $DEBUG $REMOTE_COMMAND $RHOST mt -f ${tape_dev} fsf 3 >/dev/null 2>&1
  fi
else
  # Backups are on DISK, CD, NFS
  RESTORE_PATH=`cat /etc/recovery/RESTORE_PATH`
  if [ -z "${RESTORE_PATH}" ]; then
     error 1 "Strange, the /etc/recovery/RESTORE_PATH is empty!"
  fi

  if [ "/cdrom/" = "${RESTORE_PATH}" ]; then
     print "\nThe backups are on this CD-ROM.\n"
  elif [ "`cd ${RESTORE_PATH};pwd`" = "${RESTORE_PATH}" ]; then
     # check if RESTORE_PATH is in the meantime mounted?
     print "\nThe Backups are found on ${RESTORE_PATH}.\n"
  elif [ "`cd /nfs${RESTORE_PATH};pwd`" = "/nfs${RESTORE_PATH}" ]; then
     # check if RESTORE_PATH is under /nfs subtree?
     RESTORE_PATH=/nfs${RESTORE_PATH}
     print "\nThe Backups are found on ${RESTORE_PATH}.\n"
  else
     # archives are on local or NFS disk (check RESTORE_PATH)
     mount | grep ${RESTORE_PATH} > /dev/null
     if [ $? -eq 1 ]; then
        # maybe FS is not mounted? check fs in mtab at the time
        # the backups were made
        grep ${RESTORE_PATH} /etc/recovery/mtab.* > /dev/null
        if [ $? -eq 1 ]; then
           error 1 "Sorry, but I cannot find ${RESTORE_PATH} mentioned to restore backups
from. Please scratch your head and mount it yourself. Then try again"
        fi
        # OK, saw it in mtab file. Is is local or NFS?
        MOUNT_DEV=`grep ${RESTORE_PATH} /etc/recovery/mtab.* |awk '{print $1}'`
        FS=`grep ${RESTORE_PATH} /etc/recovery/mtab.* | awk '{print $2}'`
        # is MOUNT_DEV a NFS mount point?
        grep ${RESTORE_PATH} /etc/recovery/mtab.* | grep nfs > /dev/null
        if [ $? -eq 0 ]; then
           # OK, NFS was involved. Is network up?
           ifconfig | grep eth 2>&1 >/dev/null
           have_eth=$?
           if [ $have_eth -eq 1 ]; then
              error 1 "The network is not active. Please investigate why and correct before
retrying as the backups are on NFS drives."
           fi
        fi # end of NFS test
        #mount ${MOUNT_DEV} ${FS}
        /etc/recovery/mount.sh
        if [ $? -eq 1 ]; then
           error 1 "Cannot mount ${MOUNT_DEV} on ${FS}. What now? Maybe fsck needed?"
        fi
	if [ "`cd /nfs${RESTORE_PATH};pwd`" = "/nfs${RESTORE_PATH}" ]; then
		# check if RESTORE_PATH is under /nfs subtree?
		RESTORE_PATH=/nfs${RESTORE_PATH}
		print "\nThe Backups are found on ${RESTORE_PATH}.\n"
	fi
        print "\nThe backups are found on ${FS}.\n"
      fi # end from  mount | grep ${RESTORE_PATH}
   fi # end of /cdrom/
fi # backups are on TAPE_DEV or not

}

#-----<--------->-------

Step3 () {
# Step 3: the backups have been seen now. here we have to check if the
# physical device really exists. Otherwise, we cannot restore.

# Check how many disks are candidates to restore (sw raid md too)
cd /etc/recovery
Check_df_file # if df.hostname is not the same as df.FQDN

# setting some defaults on the kind of disk configuration we have
NormalDevFound=0
mdDevFound=0
lvmDevFound=0

ls geometry.* > /dev/null 2>&1
if [ $? -eq 0 ];  then
   NormalDevFound=1     # normal IDE/SCSI devices found
fi
ls md/geometry.* > /dev/null 2>&1
if [ $? -eq 0 ];  then
   mdDevFound=1 # md devices found (could be normal)
fi
ls lvm/geometry.* > /dev/null 2>&1
if [ $? -eq 0 ];  then
   lvmDevFound=1
fi

if [ ${NormalDevFound} -eq 1 ]; then
for gdsk in `ls geometry.*`
do
        _dsk=`echo ${gdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        # save the disk geometry to /tmp
        sfdisk -g /dev/${dsk} > /tmp/geometry.${_dsk} 2>/dev/null
        if [ $? -eq 1 ]; then
                error 1 "Cannot find /dev/${dsk} on this system. If you wish to restore data to another disk it is possible, but you have to use the clone-dsk.sh script instead!"
        fi
        diff /tmp/geometry.${_dsk} geometry.${_dsk} >/tmp/diff.${_dsk}
        if [ -s /tmp/diff.${_dsk} ]; then
          # disk has been changed !
          size_old=`cat size.${_dsk}`
          size_new=`sfdisk -s /dev/${dsk} 2>/dev/null`
          if [ ${size_new} -lt ${size_old} ]; then
                error 1 "New disk has size ${size_new} which is lesser than ${size_old} (of the previous disk). Restoring data cannot be done automatically. Try script clone-dsk.sh!"
          fi
          # give a warning of new disk is bigger in size (informational)
          if [ ${size_new} -gt ${size_old} ]; then
             warn "New disk /dev/${dsk} has a larger disk capacity (size ${size_new}), the old disk had size ${size_old}. It is OK to press return."
          fi
        fi
        # The disk is still physical available (maybe bigger in size).
        # It has to be on the same bus, e.g. IDE disk hda, or SCSI sdb.
        # At this point you cannot replace an IDE disk by an SCSI disk, or you  
        # have to do the restoring manually (use clone-dsk.sh instead)
        #
        # FSF counts if we have to forward the tape
        FSF=0
        # Ask to restore this disk?
        askyn Y "Do you want to restore disk /dev/${dsk} ?"
        if [ $? -eq 0 ]; then
                # NO, do not restore this disk! (hide all data)
                mkdir -p /etc/recovery/.hide >/dev/null
                mv /etc/recovery/*.${_dsk} /etc/recovery/.hide
                FSF=`ls ${RESTORE_PATH}/${_dsk}*.log* | wc -l`
                # tape is sequential, meaning you can skip the first disk
                # but it is impossible to skip the 1st disk, restore 2th,
                # and then to skip the 3th. Sorry, you cannot have it all.
        else
                # check if disk is NOT in use, e.g. mounted
                sfdisk -R /dev/${dsk} 2>/dev/null | grep BLKRRPART > /dev/null
                if [ $? -eq 0 ]; then   # 0 means disk is in use!
                        # check whether the backups are on this disk?
                        if [ -z "${RESTORE_PATH}" ]; then
                           error 1 "Disk /dev/${dsk} is in use, but backups are on tape. Please find out why the disk is in use (swap partition in use?)."
                        fi
                        if [ "/cdrom/" = "${RESTORE_PATH}" ]; then
                           error 1 "Disk /dev/${dsk} is mounted, but backups are on CD-ROM. Please find out why the disk is mounted."
                        fi
                        cd ${RESTORE_PATH}
                        if [ $? -eq 0 ]; then
                           # mount point is there, same disk as backup?
                           disk=`df . | tail -n 1 |  awk '{print $1}' | cut -d"/" -f3- | sed -e 's/[0-9]//g'`

                           if [ "${disk}" = "${dsk}" ]; then
                                # disk is mounted and contain backups
                                warn "Disk /dev/${dsk} contain also the backups! I will prevent the restore of the disk automagically."
                                mkdir -p /etc/recovery/.hide >/dev/null
                                mv /etc/recovery/*.${_dsk} /etc/recovery/.hide
                           else
                                # probably NFS mounted
                                error 1 "Disk /dev/${dsk} is mounted, but backups are likely be on a NFS mount point. Please investigate why this disk was mounted. Correct the problem and retry."
                           fi # end of disk test
                        fi # end of cd test
                fi # end of fi BLKRRPART
        fi # end of askyn
done
fi # NormalDevFound=1

if [ ${mdDevFound} -eq 1 ]; then
   color green black
   print "Are you really sure you want to restore a Software RAID from scratch?\n"
   print "It will cause DATA loss if you proceed! Did you try raidstart already ?\n"
   print "In /etc/raidtab the current configuration is described.\n"
   print "Maybe you want to edit this file before proceeding?\n"
   print "Check /usr/doc/howto directory for the Software RAID howto\n\n"
   color white black
   warn "Your disks will be wiped out and rebuild from scratch. OK?"
   ${DEBUG} /etc/recovery/md/buildraid.sh
   print "The Software RAID has been activated, but syncing can take a while.\n"
   cat /proc/mdstat
fi

if [ ${lvmDevFound} -eq 1 ]; then
   color green black
   print "Are you really sure you want to restore a LVM based system from scratch?\n"
   print "It will cause DATA loss if you proceed! Did you try vgscan already?\n"
   print "Check /usr/doc/howto directory for the LVM guide\n\n"
   color white black
   warn "Your disks will be wiped out and rebuild from scratch. OK?"
   ${DEBUG} /etc/recovery/lvm/buildLVM.sh
   print "Logical Volume Manager (LVM) has been activated.\n"
fi
}

#-----<--------->-------
Step4 () {
# Step 4: repartition the disk(s)
# Before going on, are there still disks left to restore?
if [ ${NormalDevFound} -eq 1 ]; then

KERNEL_TYPE=`uname -a | grep ia64` # IA64

if [ "${KERNEL_TYPE}" = "" ]; then
   # for ia32 we use sfdisk to reformat

   ls sfdisk.* > /dev/null
   if [ $? -eq 1 ]; then
        error 1 "No disks left to restore. I quit!"
   fi
   cd /etc/recovery
   for sdsk in `ls sfdisk.*`
   do
        _dsk=`echo ${sdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        askyn Y "Are you ready to partition /dev/${dsk} (No to skip) ?"
        if [ $? -eq 1 ]; then
           ${DEBUG} /etc/recovery/sfdisk.${_dsk}
           if [ $? -eq 1 ]; then
                error 1 "No Warranty remember - repartitioning had errors - use fdisk to inspect."
           fi
           [ -x /sbin/udevstart ] && /sbin/udevstart
        fi
   done
else # [ KERNEL_TYPE = "" ]
   # for ia64 we use parted to reformat
   ls parted.* > /dev/null
   if [ $? -eq 1 ]; then
        error 1 "No disks left to restore. I quit!"
   fi
   cd /etc/recovery
   for sdsk in `ls parted.*`
   do
        _dsk=`echo ${sdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        askyn Y "Are you ready to partition /dev/${dsk} with parted (No to skip) ?"
        if [ $? -eq 1 ]; then
                ${DEBUG} /etc/recovery/parted.${_dsk}
                if [ $? -eq 1 ]; then
                   error 1 "No Warranty remember - repartitioning had errors - use parted to inspect."
                fi
        fi
   done
fi # end of [ KERNEL_TYPE = "" ]

print "\nThe disks have been repartitioned\n"
fi # ${NormalDevFound} -eq 1
}

#-----<--------->-------
Step5 () {
# Step 5: make the filesystem on the disk(s) (i.e. format the partitions)
if [ ${NormalDevFound} -eq 1 ]; then
for mdsk in `ls mkfs.* md/mkfs.* lvm/mkfs.* 2>/dev/null`
do
   _dsk=`echo ${mdsk} | cut -d"." -f 2`
   dsk=`echo ${_dsk} | tr "_" "/"`
   ${DEBUG} sh -x /etc/recovery/mkfs.${_dsk}
done
print "\nAll disks are ready to be restored.\n"
fi
}

#-----<--------->-------
Step6 () {
# Step 6: make the swap if any
if [ -f /etc/recovery/mkswap.sh ]; then
        print "\nInitialize the swap partition:\n"
        cat /etc/recovery/mkswap.sh
        ${DEBUG} /etc/recovery/mkswap.sh
        print "\nSwap partition is made.\n"
fi

# Step 6bis: label partitions if needed (new in RedHat 7.x)
if [ -f /etc/recovery/mke2label.sh ]; then
        ${DEBUG} /etc/recovery/mke2label.sh
        print "\nPartitions have been labeled.\n"
fi
}

#-----<--------->-------
Step8 () {
# Step 8: LILO/GRUB the system
# Mount the / partition on LOCALFS and if needed the /boot partition on /boot
cd /etc/recovery
# check the BOOTLOADER file to find out we were using LILO or GRUB
BOOTLOADER="`cat BOOTLOADER`"

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

# Copy over udev persistent net rules - if requested
if [ -f /tmp/new-per-net-rules ]; then
   cp -p /etc/udev/rules.d/*persistent-net.rules ${LOCALFS}/etc/udev/rules.d \
     2>/dev/null
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
}

#-----<--------->-------
Step9 () {
# Step 9: all disks were restored.
if [ ${OK_TO_REBOOT} -eq 2 ]; then
        color white blue
        print "\n\nSystem has been successfully restored.\n"
        print "You may reboot the system now.\n"
        color white black

else
        color black red
        print "\n\nSystem has been successfully restored.\n"
        print "\n\n${BOOTLOADER} was not successfully done.\n"
        print "Not sure if a reboot will be OK.\n"
        color white black
fi
echo
if [ ${mdDevFound} -eq 1 ]; then
   color yellow black
   print "Please do NOT reboot system until all your disks are in sync!\n"
   cat /proc/mdstat
   print "Please do NOT reboot system until all your disks are in sync!\n"
   print "Check with: cat /proc/mdstat\n"
   color white black
fi
}

#-----<--------->-------
MountLocalFileSystems () {
# mount local file systems from /etc/recovery/To_Restore without
# any further actions. Meaning we will do the restore with an external
# program like Data Protector or Tivoli Storage Manager

cd /etc/recovery
mkdir -p ${LOCALFS}

# mount all partitions listed in To_Restore, e.g. hda[1-19]
cat /etc/recovery/To_Restore | sort -k 2,2 | \
{ while read Line
    do
      ParseDevice ${Line}                       # eg. hda1
      Fs=`echo ${Line} | awk '{print $2}'`      # eg. /usr
      _Fs=`echo ${Fs} | tr "/" "_"`             # eg. _usr
      FStype=`echo ${Line} | awk '{print $3}'`  # eg. ext2

      # load FStype modules if needed (does not hurt anyway)
      modprobe ${FStype} 2>/dev/null
      if [ "${FStype}" = "ext3" ]; then
        modprobe freext3 >/dev/null 2>&1
        sleep 2
      fi
      # mount the partition on LOCALFS
      # SF#1474035 - mount point does not exist
      mkdir -p ${LOCALFS}${Fs} >/dev/null 2>&1
      mount -t ${FStype} /dev/${Dev} ${LOCALFS}${Fs}
      if [ $? -eq 1 ]; then
        error 1 "Could not mount /dev/${Dev} on ${LOCALFS}${Fs}. Please investigate manually."
      fi
      if [ "${Fs}" = "/" ]; then
        cd ${LOCALFS}
        mkdir proc > /dev/null 2>&1
        /etc/recovery/mkdirs.sh # make any missing mount point
        OK_TO_REBOOT=1 # 1: /proc made (2: LILO OK)
      fi
      cd /etc/recovery
    done
    } # end of while loop
}

#-----<--------->-------
Check_df_file () {
################
HOSTNAME=`hostname`

# HOSTNAME is used to find correct /etc/recovery/df.$HOSTNAME file, but
# Slackware sometimes uses the FQDN as hostname, and sometimes not
if [ "df.$HOSTNAME" != "`ls df.*`" ]; then
   DFfile=`ls df.* | head -n 1`
   ln -s ${DFfile} df.${HOSTNAME}
   ln -s fstab.`echo ${DFfile} | cut -d"." -f 2`  fstab.${HOSTNAME}
fi
}

#-----<--------->-------

DiskSizeSectors () {
###############
# input: geometry file
# output: size in sectors
GeometryFile=$1
Cylinders=`cat $GeometryFile | awk '{print $2}'`
Heads=`cat $GeometryFile | awk '{print $4}'`
SectorsTrack=`cat $GeometryFile | awk '{print $6}'`
bc <<EOF
$Cylinders*$Heads*$SectorsTrack
EOF
}
#-----<--------->-------

Replace_Sourcedev_Targetdev () {
source_file=$1
target_file=$2
cat $source_file | { while read line
do
   Replace_Sourcedev_Targetdev_2 "$line"
done
} >$target_file
}

Replace_Sourcedev_Targetdev_2 () {
   input_line=$1
   echo ${source_dev}|egrep -q "cciss|ida|ataraid"
   if [ $? -eq 0 ]; then
        echo ${target_dev}|egrep -q "cciss|ida|ataraid"
        if [ $? -eq 0 ]; then
            # eg: /dev/cciss/c0d0p1 becomes /dev/cciss/c1d0p1
            # eg: /dev/cciss/c0d0 becomes /dev/cciss/c1d0
            # eg: /dev/ataraid/d0p1 becomes /dev/ataraid/d1p1
            res=`echo $input_line|sed 's#'${source_dev}p'#'${target_dev}p'#'|sed 's#'${source_dev}'#'${target_dev}'#'`
        else
            # eg: /dev/cciss/c0d0p1 becomes /dev/hda1
            # eg: /dev/cciss/c0d0 becomes /dev/hda
            res=`echo $input_line|sed 's#'${source_dev}p'#'${target_dev}'#'|sed 's#'${source_dev}'#'${target_dev}'#'`
        fi
   else
        echo ${target_dev}|egrep -q "cciss|ida|ataraid"
        if [ $? -eq 0 ]; then
           echo $input_line|egrep -q "${source_dev}[0-9]+"
           if [ $? -eq 0 ]; then
              # eg: /dev/hda1 becomes /dev/cciss/c0d0p1
              res=`echo $input_line|sed 's#'${source_dev}'#'${target_dev}p'#'`
           else
              # eg: /dev/hda becomes /dev/cciss/c0d0
              res=`echo $input_line|sed 's#'${source_dev}'#'${target_dev}'#'`
           fi
        else
           # eg: /deb/hda1 becomes /dev/hdb1
           # eg: /deb/hda becomes /dev/hdb
           res=`echo $input_line|sed 's#'${source_dev}'#'${target_dev}'#'`
        fi
   fi
   echo $res
} # end function Replace_Sourcedev_Targetdev_2

Resize_partition_layout () {
# Things we know
# SOURCE_DISK(_SIZE): e.g. /dev/hda
# TARGET_DISK(_SIZE): e.g. /dev/hdd
# source_dev=`echo ${SOURCE_DISK} | cut -d'/' -f 3-`    # e.g. hda
# _source_dev=`echo ${source_dev} | tr '/' '_'`
# target_dev=`echo ${TARGET_DISK} | cut -d'/' -f 3-`
# _target_dev=`echo ${target_dev} | tr '/' '_'`

# purpose of this function:
# parse the partitions.file of a source disk and map it onto the characteristics
# of the target disk. Meaning enlarging (or decreasing) the different partitions
# unless some partitions are fixed (by FIXED_SIZE in Config.sh) or if the par-
# tition contained a microsoft based filesystem.
# Swap partitions: we ask the user what to do with it and propose a list to 
# choose from.

# add code to recognize Compaq Smart-2 arrays (gdha, 05/11/2001)
source_part_dev=${source_dev}   # e.g. cciss/c0d0
echo ${source_dev} | egrep "cciss|ida|ataraid" > /dev/null 2>&1
if [ $? -eq 0 ]; then
   source_part_dev=${source_part_dev}p  # add 'p' for partition
fi

target_part_dev=${target_dev} # e.g. cciss/c0d0, or hda
echo ${target_dev}  | egrep "cciss|ida|ataraid" > /dev/null 2>&1
if [ $? -eq 0 ]; then
   target_part_dev=${target_part_dev}p  # add 'p' for partition
fi

# calculate the total size in sectors of source disk
SourceDiskSectorsSize=`DiskSizeSectors /etc/recovery/geometry.${_source_dev}`

# calculate the total size in sectors of target disk
sfdisk -g ${TARGET_DISK} > /tmp/geometry.${_target_dev}
TargetDiskSectorsSize=`DiskSizeSectors /tmp/geometry.${_target_dev}`

#  if hostname is different with mkCDrec then orig distro adapt df file
Check_df_file

# find used space on disk, scaled size of resizable partitions and swap size
total_scalable=0        # sum of sectors in scalable partitions
total_fixed=0           # sum of sectors in fixed-size partitions
extended_scalable=0     # sum of sectors in scalable logical partitions
extended_fixed=0        # sum of sectors in fixed-size logical partitions
min_extended_size=0     # Sum of used sectors by all logical partitions
md_swap_ipart=0         # Software RAID swap partition (default=0,none)

rm -f /tmp/swap.${_target_dev}
> /tmp/sfdisk.tmp       # temp. file containing the figures after 1st round

# hunt down the Software RAID swap partition (if any)
if [ -f /etc/recovery/mkswap.sh ] && [ -f /etc/recovery/mdstat ]; then
   md_swap_dev=`tail -n 1 /etc/recovery/mkswap.sh | awk '{print $2}' | cut -d"/" -f 3`
   md_swap_ipart=`grep ${md_swap_dev} /etc/recovery/mdstat | sed -e 's/.*'${source_part_dev}'//'  | cut -d"[" -f1`
   # md_swap_ipart should contain an integer nr of partition       
fi

# first round: go through the source partitions file and collect figures
ipart=1                 # i partition number

while true      # do not use "while read Line" as "selection" eats lines!
do
  Line=`grep "/dev/${source_part_dev}${ipart}[ :]" /etc/recovery/partitions.${_source_dev}`
  if [ $? -eq 0 ]; then
    Bootable=""
    echo ${Line} | grep boot > /dev/null
    if [ $? -eq 0 ]; then
        Bootable=",*"
    fi
    # get the file system type, size and name
    ID=`echo ${Line} | cut -d"=" -f 4 | cut -c1-2 | sed 's/ //g'`
    start_size=`echo ${Line} | cut -d"=" -f 2 | sed 's/, size//' | sed 's/ //g'`
    part_size=`echo ${Line} | cut -d"=" -f 3 | sed 's/, Id//' | sed 's/ //g'`
    part_name=`echo ${Line} | awk '{print $1}' | sed 's/://'`
    # check if current partition was mounted at time of backup, and how
    # many sectors were used for data
    FileSystem=`grep "^/dev/${source_part_dev}${ipart} " /etc/recovery/df.${HOSTNAME} | awk '{print $6}'`
    Used_KB=`grep "^/dev/${source_part_dev}${ipart} " /etc/recovery/df.${HOSTNAME} | awk '{print $3}'`
    [ -z ${Used_KB} ] && Used_KB=0      # not mounted (unused partition)
    UsedSectors=`expr ${Used_KB} \* 2`

    # by default partitions are of fixed size => scalable=0
    ##############
    scalable=0   # small disks do have a problem with this policy
    ##############
    on_backup=0
    grep -q "^/dev/${source_part_dev}${ipart}[[:space:]]" /etc/recovery/To_Restore
    if [ $? -eq 0 ]; then
      on_backup=1
      # partition is to be restored, is it scalable?
      if [ -f /etc/recovery/fixed.${_source_dev} ]; then
        grep -q "^/dev/${source_part_dev}${ipart}$" /etc/recovery/fixed.${_source_dev}
        scalable=$?
      else
        # nothing fixed, so scalable OK
        scalable=1
      fi
    fi
    
    if [ ${ipart} -le 2 -a ${on_backup} -eq 0 ]; then
      # no DOS or Linux 1st part. found on backup (To_Restore file)

      # check if partition exists on "target" disk
      trg_id=0
      trg_details=`sfdisk -d ${TARGET_DISK} | grep "/dev/${target_part_dev}${ipart} "`
      if [ ! -z "${trg_details}" ]; then
         # Partition layout found on target disk - check partition
         trg_start=`echo $trg_details | cut -d"=" -f 2 | sed 's/, size//' | sed 's/ //g'`
         trg_size=`echo $trg_details | cut -d"=" -f 3 | sed 's/, Id//' | sed 's/ //g'`
         trg_id=`echo $trg_details | cut -d"=" -f 4 | cut -c1-2 | sed 's/ //g'`
      fi

      if [ "${ID}" != "5" -a "${ID}" != "85" -a "${ID}" != "f" ]; then
        # only check on DOS when the partition on source disk is not an
        # extended partition

        # if the partition on target disk already contains a DOS-alike
        # filesystem ask the question if user wants to preserve it or not
        case ${trg_id} in
        1|4|6|7|b|c|e|11|12|14|16|17|1b|1c|1e|84|86|87|de)
          clear
          print "How would you like partition ${ipart} to be handled?\n\n"
          print "  1  Create an empty partition of zero size\n"
          print "  2  Keep the partition on target disk\n"

          maxsel=2
          selection 1-$maxsel
          first_part_choice=$?
          case ${first_part_choice} in
            1) part_size=0
            start_size=0
            ID=0
            ;;
            2) part_size=${trg_size}
            start_size=${trg_start}
            total_fixed=`expr ${total_fixed} + ${part_size}`
            ID=${trg_id}
            ;;
          esac
          ;;
          *) # do NOT care what is on the target disk
          total_fixed=`expr ${total_fixed} + ${part_size}`
          ;;
        esac
      fi # end of [ ${ID} != 5 -a ${ID} != 85 -a ${ID} != f ]
    else # of ipart -eq 1 -a ${on_backup} -eq 0
      [ "${ipart}" = "${md_swap_ipart}" ] && ID=82 # magic trick for md swap
      case ${ID} in
        # ignore empty and extended partitions
        "0"|"5"|"85"|"f")
        ;;
        "82") # swap par
        clear
        swap_sz_Mb=`expr $part_size / 2048`
        print "\nSwap partition $part_name has size $swap_sz_Mb Mb.\n"
        print "You can change the size of this partition if required.\n\n"
        for i in 1 2 3 4 5
        do
          factor=`expr $i + 1`
          size=`expr $swap_sz_Mb \* $factor / 4`
          print "  $i  $size Mb\n"
        done
        print "\n"
        selection 1-5
        choice=$?
        factor=`expr $choice + 1`
        part_size=`expr $part_size \* $factor / 4`
        total_fixed=`expr ${total_fixed} + ${part_size}`
        UsedSectors=${part_size}        # to adjust min_extended_size when par>4
        echo "$part_name $part_size" >>/tmp/swap.${_target_dev}
        ;;
        *) # Linux/FAT32 or whatever flavour
        if [ ${scalable} -eq 1 ]; then
          total_scalable=`expr ${total_scalable} + ${part_size}`
        else
          total_fixed=`expr ${total_fixed} + ${part_size}`
        fi
        ;; 
      esac
    fi # end of ipart
    [ "${ID}" = "fd" ] && ID=83 # software RAID ID becomes Linux type
    echo "${ipart}:${start_size}:${part_size}:${ID}:${Bootable}:${scalable}:${UsedSectors}" >> /tmp/sfdisk.tmp

    if [ ${ipart} -eq 1 ]; then
      # include offset to start of first partition
      total_fixed=`expr ${total_fixed} + ${start_size}`
    fi
    
    if [ ${ipart} -gt 4 ]; then
      min_extended_size=`expr ${UsedSectors} + ${min_extended_size}`
      if [ ${scalable} -eq 1 ]; then
        extended_scalable=`expr ${extended_scalable} + ${part_size}`
      else
        extended_fixed=`expr ${extended_fixed} + ${part_size}`
      fi
      if [ ${part_size} -eq 0 ]; then
        # empty logical partitions need to have a non-zero size
        total_fixed=`expr ${total_fixed} + 1`
      fi
    fi
    ipart=`expr $ipart + 1`
  else
    LastPartNr=`expr $ipart - 1`
    break       # no more lines to read in partitions.$source_dev
  fi # end of Line=grep
done
#########################################################################
# calculate the ratio difference between target/source disk
# but exclude fixed-size partitions from the calculation
# greater than 1 means target disk is bigger than source disk
available_sectors=`expr ${TargetDiskSectorsSize} - ${total_fixed}`
if [ ${total_scalable} -lt 1 ]; then
   TargetvsSourceRatio=0
else
   TargetvsSourceRatio=`Divide ${available_sectors} ${total_scalable}`
fi

# End of first round - do some checks to see if everything fits...
ScaledExtendedSize=`Multiply ${extended_scalable} ${TargetvsSourceRatio} | sed 's/\..*$//'`
ScaledExtendedSize=`expr ${ScaledExtendedSize} + ${extended_fixed}`
if [ ${ScaledExtendedSize} -lt ${min_extended_size} ]; then
   ScaledExtendedSize=${min_extended_size}
fi
###########################################################################
# total_scalable is amount of sectors which may be scaled up/down
echo total_scalable=$total_scalable
# total_fixed is amount of sectors which is fixed \(no modification possible\)
echo total_fixed=$total_fixed
# extended_scalable is amount of sectors in extended mode and scalable
echo extended_scalable=$extended_scalable
# extended_fixed is amount of sectors in extended mode and fixed in size
echo extended_fixed=$extended_fixed
# min_extended_size is sum of sectors of all logical partitions \(par\>4\)
echo min_extended_size=$min_extended_size
# ScaledExtendedSize is amount of sectors of extended partition after scaling up/down
echo ScaledExtendedSize=$ScaledExtendedSize
# LastPartNr is last partition number
echo LastPartNr=$LastPartNr
# TargetDiskSectorsSize is the max. sector size of target disk!
echo TargetDiskSectorsSize=$TargetDiskSectorsSize
# TargetvsSourceRatio is the resizing factor \(\<1 is smaller target disk\)
echo TargetvsSourceRatio=$TargetvsSourceRatio
###########################################################################

# Round two: make the real sfdisk file
# make an sfdisk input file for the new partition layout
# adjust the size of scalable partitions
echo "sfdisk --force -uS ${TARGET_DISK} << EOF" > /tmp/sfdisk.${_target_dev}
next_sector=0
new_total=0
# now we will read /tmp/sfdisk.tmp back in and finish with /tmp/sfdisk.target
{ while read Line
do
  ipart=`echo ${Line} | cut -d: -f1`
  ID=`echo ${Line} | cut -d: -f 4`
  part_start=`echo ${Line} | cut -d: -f 2`
  part_size=`echo ${Line} | cut -d: -f 3`
  Bootable="`echo ${Line} | cut -d: -f 5`"
  scale=`echo ${Line} | cut -d: -f 6`
  if [ ${scale} -eq 1 ]; then
    used=`echo ${Line} | cut -d: -f 7`
  fi
    
  if [ ${ipart} -eq 1 ]; then
        start=${part_start}
        start1=${part_start}
        next_sector=${part_start}
        new_total=${part_start}
  elif [ ${ipart} -le 4 ]; then
        start=${next_sector}
  else
        start=""
  fi

  case ${ID} in
  0) echo "0,0,0${Bootable}" >> /tmp/sfdisk.${_target_dev} ;;
  5|85|f) # extended partition
        if [ "${ID}" = "5" ]; then
           Str=",E"
        else
           Str=",X"
        fi
        # ScaledExtendedSize <= TargetDiskSectorsSize - start
        # well it should, but practical sometimes not (decrease mode often not)
        ScaledExtendedSizeCheck=`expr ${TargetDiskSectorsSize} - ${start}`
        if [ ${ScaledExtendedSize} -gt ${ScaledExtendedSizeCheck} ]; then
           ScaledExtendedSize=${ScaledExtendedSizeCheck}
        fi
        echo "${start},${ScaledExtendedSize}${Str}${Bootable}" \
         >>/tmp/sfdisk.${_target_dev}
        #next_sector=`expr ${next_sector} + ${ScaledExtendedSize} + 1`
        # above is probably wrong: it should be for extended partition=
        # next_sector+start1 
        next_sector=`expr ${next_sector} + ${start1}`
        ;;
  82)   # swap partition
        new_total=`expr ${new_total} + ${part_size}`
        if [ ${ipart} -ne ${LastPartNr} ]; then
           next_sector=`expr ${next_sector} + ${part_size}`
        else
           part_size=""
        fi
        echo "${start},${part_size},S" >>/tmp/sfdisk.${_target_dev}
        ;;
  *)    # Dos/Linux/others
        if [ ${scale} -eq 1 ]; then
          part_size=`Multiply ${part_size} ${TargetvsSourceRatio} | sed 's/\..*$//'`
          if [ ${part_size} -lt ${used} ]; then
          #   error 1 "Automatic resizing failed. Please do it manually with fdisk"
              part_size=`Multiply ${used} 1.11  | sed 's/\..*$//'`
          fi
        fi
        if [ ${ipart} -ge 4 -a ${part_size} -eq 0 ]; then
           part_size=1  # may not be 0 as sfdisk will skip empty logical p
        fi
        new_total=`expr ${new_total} + ${part_size}`
        if [ ${ipart} -ne ${LastPartNr} ]; then
           next_sector=`expr ${next_sector} + ${part_size}`
        else
           part_size=""
        fi
        echo "${start},${part_size},${ID}${Bootable}" \
         >>/tmp/sfdisk.${_target_dev}
  esac

done
} < /tmp/sfdisk.tmp

if [ ${TargetDiskSectorsSize} -lt ${new_total} ]; then
   error 1 "Automatic resizing failed. Please do it manually with fdisk"
fi

# close the file (with EOF)
echo "EOF" >> /tmp/sfdisk.${_target_dev}
chmod +x /tmp/sfdisk.${_target_dev}
} # end of function Resize_partition_layout
#-----<--------->-------


Divide () {
#########
num1=$1
num2=$2

# divide with floating numbering
bc -l <<EOF
${num1}/${num2}
EOF
}
#-----<--------->-------

Multiply () {
###########
num1=$1
num2=$2

bc -l <<EOF
${num1}*${num2}
EOF
}
#-----<--------->-------

Convert2Mb () {
############
numKb=$1

# convert Kb into Mb
bc <<EOF
${numKb}/1024
EOF
}
#-----<--------->-------

Check_Multi_volume () {
#####################
# return 0 if we're dealing with a multi volume CD
# All CDs made by mkCDrec contain a Volume-ID starting with "CDrec-`date`*"
ls /cdrom/CDrec-* > /dev/null 2>&1
if [ $? -eq 1 ]; then
   echo "No mkCDrec label found on this CD-ROM, I quit."
   exit 1
fi
ls /cdrom/CDrec-* | grep "_" > /dev/null 2>&1
IsMultiVol=$?
}
#-----<--------->-------

Current_VolID () {
################
# returns CDrecDate and volno
OLDPW=`pwd`
cd /cdrom
ls CDrec-* > /dev/null 2>&1
if [ $? -eq 1 ]; then
   echo "This CD-ROM was not created by mkCDrec, but how did you get so far?"
   exit 1
fi
CDrecDate=`ls CDrec-* | cut -d"_" -f 1`
volno=`ls CDrec-* | cut -d"_" -f 2`
# complete VolID is ${CDrecDate}_${volno}
cd ${OLDPW}
}
#-----<--------->-------

WhichCompressProgram () {
#######################
CMP_PROG=`cat /etc/recovery/CompressedWith`
CMP_PROG_OPT="-dc"      # decompress to stdout
}
#-----<--------->-------

WhichEncryptCipher () {
#######################
ENC_PROG_CIPHER=`cat /etc/recovery/EncryptedWith`
if [ -z "${ENC_PROG_CIPHER}" ]; then
        ENC_PROG_PASSWD=""
        ENC_PROG="cat"
else
        print "[1;33mEnter your encryption password[36m\n"
        stty -echo < `tty`
        read passwd < `tty`
        stty echo < `tty`
        #ENC_PROG_PASSWD="-pass pass:${passwd}"
        touch /tmp/.key
        chmod 600 /tmp/.key
        echo ${passwd} > /tmp/.key
        ENC_PROG_PASSWD="-kfile /tmp/.key"
        ENC_PROG="openssl"
fi
}
#-----<--------->-------

SelectCmpExtention () {
##################
# Extention of backup is gz (gzip compression) or bz2 (bzip2 compression)
# Do not care if backup is split up or not (eg. gz_ or bz2_)
case ${CMP_PROG} in
     gzip) CmpExt=gz ;;
     bzip2) CmpExt=bz2 ;;
     compress) CmpExt=Z ;;
     lzop) CmpExt=lzo ;;
     *) CmpExt=z ;;
esac
}
#-----<--------->-------

SelectEncExtention () {
##################
if [ -z "${ENC_PROG_CIPHER}" ]; then
    EncExt=""
else
    EncExt=.${ENC_PROG_CIPHER}
fi
}
#-----<--------->-------

SelectExtention () {
###############
# we try to find out if the archive was made by tar of dd
case ${FStype} in
    ext2|ext3|auto|minix|reiserfs|xfs|jfs) EXT=tar ;;
    msdos|fat|vfat) EXT=dd ;;
    *) error 1 "Unknown ${FStype}: cannot allocate an archive extention (tar or dd)."
esac
}
#-----<--------->-------

Tape_local_or_remote () {
#######################
echo ${tape_dev} | grep ":" > /dev/null
if [ $? -eq 0 ]; then
        # remote HOST:TAPE
        RHOST=`echo ${tape_dev} | cut -d":" -f 1`
        RESTORE=`echo ${tape_dev} | cut -d":" -f 2`
else
        RESTORE=${tape_dev}
        RHOST=""            # force it to be empty
        REMOTE_COMMAND=""   # force it to be empty
fi
}
#-----<--------->-------

restore_split_file () {
#######################
# this function restores a split file
FILE_TO_RESTORE=$1  #this must be the name of the file without the suffix .part

while [ /bin/true ]     #we loop until we restore the last cd, then we break
do
        if [ -f /tmp/more_to_come ]
        then
                MTC=`cat /tmp/more_to_come`
        else
                MTC=0
        fi


        if [ ! -f $FILE_TO_RESTORE ]
        then
                FILE_TO_RESTORE=`echo $FILE_TO_RESTORE | sed -e 's/_$//'`
                if [ ! -f $FILE_TO_RESTORE ]
                then
                        error 1 "Cannot find $FILE_TO_RESTORE . Are you sure this is the right CD ?"
                fi
        fi


        LIST_OF_SPLIT_FILES=""
        err=0
        i=0

        echo "beginning the restore of split file ${FILE_TO_RESTORE}" 1>&2

        if [ -f ${FILE_TO_RESTORE}.part0 ]; then
        #the file is split (to avoid the 2 Gb limit file size!)
        #first we look for all the pieces of the file in the right order

                while [ $err -eq 0 ]
                do
                        LIST_OF_SPLIT_FILES=${LIST_OF_SPLIT_FILES}\ ` ls ${FILE_TO_RESTORE}.part$i 2>/dev/null `
                        err=$?
                        i=$(($i+1))
                done

                # and then we paste them and send all to stdout
        echo "${FILE_TO_RESTORE} is split into ${LIST_OF_SPLIT_FILES}" 1>&2
                for current_file in ${LIST_OF_SPLIT_FILES}
                do
                        cat ${current_file}
                done
        else
                # the file isn't split, we just need to cat it
                cat ${FILE_TO_RESTORE}
        fi
        if [ -f ${RESTORE_PATH}/LAST_CD ]; then
           MTC=0        # if this CD is the last one - no more to come
        fi
        if [ $MTC -gt 0 ]
        then
                cd /etc/recovery
                sh ask.for.cd.sh
        else
                break
        fi
done
}
#-----<--------->-------

Get_backup_back () {

WhichEncryptCipher      # define ENC_PROG_CIPHER
SelectEncExtention      # encrypt file extention (bf, des, ...)
WhichCompressProgram    # define CMP_PROG (gunzip, bunzip2, lzop)
SelectCmpExtention      # compress file extention (gz, bz2, lzo)
SelectExtention         # tar or dd
err=0                   # being optimistic

if [ -z "${RESTORE_PATH}" ]; then
   # backup is on tape
   Tape_local_or_remote # check if tape is local or remote
   # define $ENCRYPTION:
   if [ "openssl" = "${ENC_PROG}" ]; then
        ENCRYPTION="${ENC_PROG} ${ENC_PROG_CIPHER} -d ${ENC_PROG_PASSWD}"
   else
        ENCRYPTION="cat"
   fi

   if [ "${EXT}" = "tar" ]; then
         ${DEBUG} ${REMOTE_COMMAND} ${RHOST} dd if=${RESTORE} bs=512 | \
         ${ENCRYPTION} | \
         ${CMP_PROG} ${CMP_PROG_OPT} | tar --extract --verbose --same-owner \
         --overwrite --preserve-permissions -C ${LOCALFS} --file -
         err=$?
   else
         ${DEBUG} ${REMOTE_COMMAND} ${RHOST} dd if=${RESTORE} bs=512 |  \
         ${ENCRYPTION} | \
         ${CMP_PROG} ${CMP_PROG_OPT} > /dev/${Dev}
   fi
elif [ "${RESTORE_PATH}" = "/cdrom/" ]; then
        # backups are on CD-ROM - single/multi volume?
        Check_Multi_volume      # CD is multi-volume or not
        if [ ${IsMultiVol} -eq 0 ]; then        # true:0 (multi-vol CD)
           # multi-volume CD
           Current_VolID        # define CDrecDate and volno
           # LAST_CD is the flag that ends a CDrec CD set
           # Restore $Fs on $Dev (backups can be splitted up)
           # RESTORE_PATH=/cdrom/
           RESTORE=${RESTORE_PATH}${_Dev}.${_Fs}.${EXT}.${CmpExt}${EncExt}
           # define $ENCRYPTION:
           if [ "openssl" = "${ENC_PROG}" ]; then
                ENCRYPTION="${ENC_PROG} ${ENC_PROG_CIPHER} -d -in /dev/stdin ${ENC_PROG_PASSWD}"
           else
                ENCRYPTION="cat /dev/stdin"
           fi
           # Endless loop until we break from it (after successfull restore)
           bcktest=0
           while ( test ${bcktest} -lt 1 )
           do
             if [ -f ${RESTORE} ]; then
              # easy part ($Fs) is on this CD and is NOT splitted up
              if [ "${EXT}" = "tar" ]; then
                #${DEBUG} ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | \
                #tar --extract --verbose --same-owner --preserve-permissions \
                #--overwrite -C ${LOCALFS} --file -
                ${DEBUG} restore_split_file ${RESTORE} | ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | \
                tar --extract --verbose --same-owner --preserve-permissions \
                --overwrite -C ${LOCALFS} --file -
                err=$?
              else
                Restore_dump
              fi
              bcktest=1 # OK, quit the loop
             elif [ -f ${RESTORE}_ ]; then
              # $Fs found on this CD, but is splitted up across CDs
              # each $Dev.$_Fs.$EXT.$CmpExt_ means to be continued
              # next function will read all parts and pipe them to TAR
              Restore_Splitted_Backup   # ${RESTORE}_ is known
              bcktest=1 # OK, quit the loop
             else
              # $Fs not found on this CD (try next one)
              if [ -f ${RESTORE_PATH}/LAST_CD ]; then
                volno=1
              else
                volno=$((volno+1))
              fi
              umount ${CDROM}
              if [ $? -eq 1 ]; then
                error 1 "Cannot unmount ${CDROM} device (cdrom)!"
              fi
              # if in AUTODR mode - break it otherwise we loop forever.
              [ -f /etc/recovery/AUTODR ] && rm -f /etc/recovery/AUTODR
              warn "Please insert CD-ROM with label ${CDrecDate}_${volno}"
              mount -r -t iso9660 ${CDROM} /mnt/cdrom
              sleep 5
             fi
           done # loop 'till break (restore backup)
        else
           # single volume CD
           RESTORE=${RESTORE_PATH}${_Dev}.${_Fs}.${EXT}.${CmpExt}${EncExt}
           # define $ENCRYPTION:
           if [ "openssl" = "${ENC_PROG}" ]; then
                ENCRYPTION="${ENC_PROG} ${ENC_PROG_CIPHER} -d -in /dev/stdin ${ENC_PROG_PASSWD}"
           else
                ENCRYPTION="cat /dev/stdin"
           fi
           if [ "${EXT}" = "tar" ]; then

                #${DEBUG} ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | \
                #tar --extract --verbose --overwrite \
                #--same-owner --preserve-permissions -C ${LOCALFS} --file -
                ${DEBUG} restore_split_file ${RESTORE} | ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | \
                tar --extract --verbose --overwrite \
                --same-owner --preserve-permissions -C ${LOCALFS} --file -
                err=$?
           else
                Restore_dump
           fi
        fi # end of IsMultiVol
else
         # backup is on HD/NFS
         RESTORE=${RESTORE_PATH}/${_Dev}.${_Fs}.${EXT}.${CmpExt}${EncExt}
         # define $ENCRYPTION:
         if [ "openssl" = "${ENC_PROG}" ]; then
                ENCRYPTION="${ENC_PROG} ${ENC_PROG_CIPHER} -d -in ${RESTORE} ${ENC_PROG_PASSWD}"
         else
                ENCRYPTION="cat ${RESTORE}"
         fi
         if [ "${EXT}" = "tar" ]; then
                ${DEBUG} ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | \
                tar --extract --verbose --same-owner --preserve-permissions \
                --overwrite -C ${LOCALFS} --file -
                err=$?
         else
                Restore_dump
         fi

fi  # end of ${RESTORE_PATH}
}

#-----<--------->-------

Restore_dump () {
############
print "Start restore of ${FStype} partition at `date`\n"
# define $ENCRYPTION:
if [ "openssl" = "${ENC_PROG}" ]; then
        ENCRYPTION="${ENC_PROG} ${ENC_PROG_CIPHER} -d -in /dev/stdin ${ENC_PROG_PASSWD}"
else
        ENCRYPTION="cat /dev/stdin"
fi
print "restore_split_file ${RESTORE} | ${DEBUG} ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | dd bs=512 of=/dev/${Dev}\n"
#${DEBUG} ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | dd bs=512 of=/dev/${Dev}
${DEBUG} restore_split_file ${RESTORE} | ${ENCRYPTION} | ${CMP_PROG} ${CMP_PROG_OPT} | dd bs=512 of=/dev/${Dev}
err=$?
print "End of restore of ${FStype} partition at `date`\n"

}

#-----<--------->-------

Restore_Splitted_Backup () {
##########################
# input: ${RESTORE}_ until ${RESTORE}
#        ${CMP_PROG}
#        ${LOCALFS}
# output: hopefully a complete restore of backups residing on multiple CDs

RESTORE=${RESTORE}_     # this will be read by pastestream
##echo /dev/stdin > /tmp/restore
echo ${RESTORE} > /tmp/restore
MORE_TO_COME=1          # part 1 of the file (more CDs will follow)
echo ${MORE_TO_COME} > /tmp/more_to_come
# define $ENCRYPTION:
if [ "openssl" = "${ENC_PROG}" ]; then
        ENCRYPTION="${ENC_PROG} ${ENC_PROG_CIPHER} -d  ${ENC_PROG_PASSWD}"
else
        ENCRYPTION="cat"
fi

# pastestream will call ask.for.cd.sh script which umounts/mounts CDs
# and redefines RESTORE and MORE_TO_COME
if [ "${EXT}" = "tar" ]; then
   restore_split_file ${RESTORE} | ${ENCRYPTION} | \
   ${CMP_PROG} ${CMP_PROG_OPT} | tar --extract --verbose --overwrite \
   --same-owner --preserve-permissions -C ${LOCALFS} --file -
   err=$?
else
   restore_split_file ${RESTORE} | ${ENCRYPTION} | \
   ${CMP_PROG} ${CMP_PROG_OPT} | dd bs=512 of=/dev/${Dev}
   err=$?
fi
}

#-----<--------->-------
ParseDevice () {
###########
# input $1 is a line containing as 1st argument a file system devive, eg.
# /dev/hda1, /dev/sdb1, /dev/md0, /dev/disk/c1t0d0
# Output: Dev: hda1, sdb1, md0, disk/c1t0d0
#        _Dev: hda1, sdb1, md0, disk_c1t0d0
Dev=`echo ${1} | awk '{print $1}' | cut -d"/" -f 3-`
_Dev=`echo ${Dev} | sed -e 's/_/%137/g' | tr "/" "_"`
}

#-----<--------->-------
DevFS_naming_mix () {
# in case DevFS was involved it could be that there is a mix between short
# naming (as in mkfs.sda) and long naming convention in To_Restore, e.g.
# /dev/scsi/host0/bus0/target0/lun0. In that case we need to backtrack...
# Input is dsk (eg. sda); output is dsk (eg. /dev/scsi/host0/bus0/target0/lun0)
scsi_or_ide=`echo ${dsk} | cut -c1-2`
case ${scsi_or_ide} in
# ok, fast groove between scsi/ide and assume /boot is 1st part.
        sd) Xdev="scsi"
                        ;;
        hd) Xdev="ide"
                        ;;
        *) Xdev="scsi" # assume SCSI for all the rest (probably correct)
                        ;;
esac
tmp_dsk=`grep ${Xdev} /etc/recovery/To_Restore | awk '{print $1}' | egrep '(part1|part5)' | sort -u| tail -n 1`
# tmp_dsk is now e.g. /dev/scsi/host0/bus0/target0/lun0/part5
if [ -z "${tmp_dsk}" ]; then
        error 1 "Lilo: could not map ${dsk} into a DevFS device."
fi
unset Xdev
# now remap the DevFS dsk
nNF=`echo ${tmp_dsk} | awk -F"/" '{print NF-1}'`
# count the number of fields minus 1 (nNF) and redefine dsk
dsk=`echo ${tmp_dsk} | cut -d"/" -f 1-${nNF}`
unset nNF
}

#-----<--------->-------
export starposition=1
star ()
{
    set -- '/' '-' '\' '|';
    test $starposition -gt 4 -o $starposition -lt 1 && starposition=1;
    echo -n "${!starposition}";
    echo -en "\r";
    let starposition++
    #sleep 0.1
}
#-----<--------->-------

CreateMinimalDev ()
{
        # help is needed for /dev which is mounted as a tmpfs type.
        # these types are not recognised by DP or TSM, so we need to
        # create a minimal /dev to get booted. We use an existing script
        # from mkCDrec (makedev) to do this task...
        # we rename the script so there can be no confusion!
        cp /usr/bin/makedev ${LOCALFS}/usr/bin/makedev.mkcdrec
        # we must  run in a chroot environment
        chroot ${LOCALFS} /usr/bin/makedev.mkcdrec
        echo "CreateMinimalDev routine pupulated a minimal /dev:"
        ls ${LOCALFS}/dev
        # do cleanup - remove our script
        rm -f ${LOCALFS}/usr/bin/makedev.mkcdrec
}
