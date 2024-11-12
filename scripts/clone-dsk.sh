#!/bin/bash
# Copyright (C) 2000-2008 - Gratien D'haese - IT3 Consultants
#
# This program is free software. You can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation: either Version 1
# or (at your option) any later version.
#
# NO WARRANTY! By running this script you accept all failures, loss of data,
# or any other kind of loss are under your responsibility and yours only!
# The sole purpose if this script is trying to restore data previously
# backuped on CD-ROM, disk, NFS disk or whatever.
#######################################################
# WARNING: this script will ERASE your harddisk!!!!!!!#
#######################################################
# DISASTER RECOVERY means restore data back to disk as it was made on the
# date the backup was made! It does not mean or replace BACKUPS!!!
# $Id: clone-dsk.sh,v 1.45 2008/07/09 13:35:52 gdha Exp $

. ./Config.sh
. ./restore_common.sh
. ./ansictrl.sh
color white black

BACKUPS_ON_MT=0
OK_TO_REBOOT=0

## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

###################################################################
## MAIN

# Step 0: write welcome
clear
color white blue
print "\n\n\tmk${VERSION}\n\n"
print "\tClone a Linux system with mkCDrec\n\n"
color white black
warn "`basename $0` script will reformat and re-install all data from backup.
If you do not want to restore data to some disk, but rather
want to restore the same disk, use the script start-restore.sh"

# Step 1: check if with this CD was the result of a backup, or just Rescue
Step1

# Step 2: try to find the location of the FS archives
Step2

# Step 3: the backups were seen, here we have to check if a physical device really exists. Otherwise, we cannot restore.

echo "Scanning available disks - be patient."

# Check how many disks are candidates to restore.
cd /etc/recovery
ls geometry.* >/dev/null 2>&1 || ls md/geometry.* >/dev/null 2>&1 || error 1 "No disk information found to restore on this mkCDrec CD!"

# If we pass above line we certain we have a potential disk for cloning

# OK, found information of the original disk(s). Now query system for
# available disks on this system

> /tmp/available.disks  # empty file
# scan IDE disks
for host in 0 1 2 3 ; do {
    for chan in a b c d e ; do {
        [ -r /proc/ide/ide${host}/hd${chan}/media ]
            if [ "`cat /proc/ide/ide${host}/hd${chan}/media 2>/dev/null`" = "disk" ]; then
                echo "/dev/hd${chan}" >> /tmp/available.disks
            fi
    } done
} done


# scan SCSI disks
if [ -r /proc/scsi/scsi ]; then
# list all scsi devices as Major Minor /dev/device in /tmp/ls_sd
ls -l /dev/sd* | awk '{print $5, $6, $10}' | sed  's;,;;' > /tmp/ls_sd
#ls -l /dev/cciss/* | awk '{print $5, $6, $10}' | sed  's;,;;' >> /tmp/ls_sd
#ls -l /dev/ida/* | awk '{print $5, $6, $10}' | sed  's;,;;' >> /tmp/ls_sd
# list all found scsi devices in /tmp/scsi_devs
egrep -A 1 Host /proc/scsi/scsi | sed -e 's;^[  ]*;;' > /tmp/scsi_devs
grep "scsi" /tmp/scsi_devs | { while read SCSI_Adapter
do
  SCSI_Major=`echo ${SCSI_Adapter} | awk '{print $2}'`
  case ${SCSI_Major} in
       scsi0) major=8 ;;
       scsi1) major=65 ;;
       scsi2) major=66 ;;
       scsi3) major=67 ;;
       *) ;;
  esac
  id=`echo ${SCSI_Adapter} | awk '{print $6}'`
  minor=$((16*${id}))
  grep ^$major /tmp/ls_sd | { while read Line
  do
    Minor=`echo ${Line} | cut -d" " -f 2`
    Device=`echo ${Line} | cut -d" " -f 3`
    if [ "$minor" = "$Minor" ]; then
        echo ${Device} >> /tmp/available.disks
        break
    fi
  done 
  } 
done
} # of SCSI_Adapter
fi # of /proc/scsi/scsi

# scan HW RAID adapters (will catch everything)
cat /proc/partitions | { while read Line
do
   major=`echo ${Line} | awk '{print $1}'`
   minor=`echo ${Line} | awk '{print $2}'`
   name=`echo ${Line} | awk '{print $4}'`
   case ${major} in
   104|105) 
        case ${minor} in
        0|16|32|48|64|80|96)
           echo "/dev/${name}" >> /tmp/available.disks
           ;;
        *) ;; # do nothing
        esac
        ;;
   *)   ;; # do nothing
   esac
done
}

# IDE RAID devices sometimes emulate SCSI and lie about the major number!
# Therefore, add a fall-back method based on /proc/partitions too
cat /proc/partitions | { while read Line
do
   # major minor  blocks name  rio etc...
   minor=`echo ${Line} | awk '{print $2}'`      # 0 when whole scsi disk
   if [ "${minor}" = "0" ]; then
      dev=`echo ${Line} | awk '{print $4}'`
      echo "/dev/${dev}" >> /tmp/available.disks
   fi
done
}

# after last steps some devices could be double listed - uniq/sort
cat /tmp/available.disks | sort | uniq > /tmp/available.new
mv -f /tmp/available.new /tmp/available.disks

# end of disk scanning (all potential installation disks are in file
# /tmp/available.disks )

########################################################################
# Ask user which SOURCE disk (previously backuped) to restore/clone on a
# target disk (available.disks)
### scan local IDE/SCSI disks in /etc/recovery
> /tmp/source.disks     # empty file
for gdsk in `ls geometry.*`
do
        _dsk=`echo ${gdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        echo "/dev/${dsk}" >> /tmp/source.disks
done

# scan meta-disks in md/* (Software RAID meta-disks)
for gdsk in `ls md/geometry.*`
do
        _dsk=`echo ${gdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        echo "/dev/${dsk}" >> /tmp/source.disks
done
mv /tmp/source.disks /tmp/xx
cat /tmp/xx | sort | uniq > /tmp/source.disks
rm -f /tmp/xx

######################################################################
# do some magic for Software Raid
######################################################################
if [ -d /etc/recovery/md ]; then
   cp /etc/recovery/md/geometry.*      /etc/recovery
   cp /etc/recovery/md/partitions.*    /etc/recovery
   cp /etc/recovery/md/size.*          /etc/recovery
   cp /etc/recovery/md/sfdisk.*        /etc/recovery
fi
######################################################################

# show the menu
stest=0
while ( test ${stest} -lt 1 )
do
clear
color green black
print "\n\nmk${VERSION} - Source disk to restore"
color white black
printat 7 1 "Enter your selection:\n\n"
i=1
declare -a source_dev   # declare Array source_dev[i]
declare -a source_size  # declare Array source_size[i]
{ while read Line
do
        ParseDevice ${Line}
        size=`cat /etc/recovery/size.${_Dev} 2>/dev/null || cat /etc/recovery/md/size.${_Dev} 2>/dev/null`
        print " ${i}) ${Line} (size: ${size} Kb)\n"
        source_dev[${i}]=${Line}
        source_size[${i}]=${size}
        i=`expr ${i} + 1`
done
} < /tmp/source.disks
high_i=`expr ${i} - 1`
selection 1-${high_i}
ANS=$?

if [ ${ANS} -gt 0 -a ${ANS} -le ${#source_dev[@]} ]; then
        stest=1
fi
done # of stest
SOURCE_DISK=${source_dev[${ANS}]}       # we've got a source disk
SOURCE_DISK_SIZE=${source_size[${ANS}]}
unset source_dev
unset source_size

# Now present the user a list of possible target disks to install to.
###
stest=0
while ( test ${stest} -lt 1 )
do
clear
color green black
print "\n\nmk${VERSION} - Target disk to restore on"
color white black
printat 7 1 "Enter your selection:\n\n"
i=1
declare -a target_dev   # declare Array target_dev[i]
{ while read Line
do
        sfdisk -s ${Line} >/dev/null 2>&1
        if [ $? -eq 1 ]; then
                continue
        fi
        size=`sfdisk -s ${Line} 2>/dev/null`
        Dev=`echo ${Line} | cut -d"/" -f 3-`
        print " ${i}) ${Line} (size: ${size} Kb)\n"
        target_dev[${i}]=${Line}
        i=`expr ${i} + 1`
done
} < /tmp/available.disks
high_i=`expr ${i} - 1`
selection 1-${high_i}
ANS=$?

if [ ${ANS} -gt 0 -a ${ANS} -le ${#target_dev[@]} ]; then
        stest=1
fi
done # of stest

TARGET_DISK=${target_dev[${ANS}]}       # we've got a target disk
TARGET_DISK_SIZE=`sfdisk -s ${TARGET_DISK} 2>/dev/null`
unset target_dev

Check_df_file # if df.hostname is not the same as df.FQDN

###
# Step 4: artificial guessing of what we need vs. what we have
source_dev=`echo ${SOURCE_DISK} | cut -d"/" -f 3-`       # e.g. hda
_source_dev=`echo ${source_dev} | tr "/" "_"`
target_dev=`echo ${TARGET_DISK} | cut -d"/" -f 3-`
_target_dev=`echo ${target_dev} | tr "/" "_"`

askyn Y "Is disk /dev/${target_dev} already formatted (manually)?"
# returns 0 for NO, or 1 for YES
if [ $? -eq 0 ]; then
   # to clone a meta-device we need to following steps bedore resizing
   # 1/ check if source_dev was a md device
   # 2/ yes? then change To_Restore file, eg. md0 to hda1
   # 3/ mv md/df.`hostname` to /etc/recovery
   grep ${source_dev} df.${HOSTNAME} >/dev/null 2>&1
   if [ $? -eq 1 ]; then
      # Software Raid device as source device?
      # check if md/geometry.* file exist
      [ ! -f /etc/recovery/md/geometry.${source_dev} ] && echo "Cannot clone /dev/${source_dev} - software raid?" && exit 1
      mv /etc/recovery/To_Restore /etc/recovery/old.To_Restore
      cp /etc/recovery/md/To_Restore.md /etc/recovery/To_Restore
      mv /etc/recovery/df.${HOSTNAME} /etc/recovery/old.df.${HOSTNAME}
      cp /etc/recovery/md/df.* /etc/recovery/df.${HOSTNAME}
   fi
   
   # resize the partition layout if possible (bigger/smaller disks)
   Resize_partition_layout
else
   # user did it manually (maybe it failed automatically?)
   > /tmp/SFDISK.done.manual
fi

# Are we still here? yeah, we must have a sfdisk.$target_dev by now
# is target disk mounted?
sfdisk -R ${TARGET_DISK} 2>&1 | grep BLKRRPART > /dev/null
if [ $? -eq 0 ]; then
  error 1 "Disk  ${TARGET_DISK} is in use. I cannot clone it."
fi # end of fi BLKRRPART

###
### is SOURCE_DISK is on tape, and if so, do we need to fast forward?
# FSF counts if we have to forward the tape
FSF=0
if [ ${BACKUPS_ON_MT} -eq 1 ]; then
for gdsk in `ls geometry.* 2>/dev/null || ls md/geometry.* 2>dev.null`
do
        _dsk=`echo ${gdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        if [ "${SOURCE_DISK}" = "/dev/${dsk}" ]; then
                break
        fi
        fsf=`grep ${dsk} /etc/recovery/To_Restore | wc -l`
        FSF=`expr ${FSF} + ${fsf}`
done
fi # end of backups are on tape

# Step 5: reformat the disk(s)
cd /etc/recovery
# check the flag /tmp/SFDISK.done.manual which means users did fdisk already
if [ ! -f /tmp/SFDISK.done.manual ]; then
   rm -f /tmp/SFDISK.done.manual  # clear the flag to be sure
   askyn Y "Do you want to reformat /dev/${target_dev} ?"
   # returns 0 for NO, or 1 for YES
   if [ $? -eq 1 ]; then
     if [ -f /tmp/sfdisk.${_target_dev} ]; then
       chmod +x /tmp/sfdisk.${_target_dev}
       ${DEBUG} /tmp/sfdisk.${_target_dev}
       err=$?
     else
       # should never get here (in /tmp there must be a sfdisk.target_dev)
       ${DEBUG} /etc/recovery/sfdisk.${_target_dev}
       err=$?
     fi
     if [ ${err} -eq 1 ]; then
       error 1 "No Warranty remember - reformat had errors - use fdisk to inspect."
     else
       print "\nThe disk has been reformatted, and will now start the mkfs.\n"
       [ -x /sbin/udevstart ] && /sbin/udevstart
     fi
   fi
fi

# Step 6: make the filesystem on the target disk
echo
# even if we skip mkfs part - we still need a mkfs.source_dev for lilo/grub
# for software raid (step 9)
if [ ! -f /etc/recovery/mkfs.${_source_dev} ] && [ -f /etc/recovery/mdstat ]; then
   # Software RAID cloning - check _source_dev in mdstat
   for Fle in `ls /etc/recovery/md/mkfs.md*`
   do
       xmd=`echo ${Fle} | cut -d"." -f 2`       # eg. md0
       cat ${Fle} >> /etc/recovery/mkfs.${_source_dev}
       x=`grep ${xmd} /etc/recovery/mdstat | sed -e 's/.*'${_source_dev}'/'${_source_dev}'/g' | cut -d"[" -f 1`
       mv /etc/recovery/mkfs.${_source_dev} /etc/recovery/mkfs.temp
       sed -e 's/'${xmd}'/'${x}'/g' < /etc/recovery/mkfs.temp >/etc/recovery/mkfs.${_source_dev}
   done
   rm -f /etc/recovery/mkfs.temp
fi
askyn Y "Start mkfs process of disk /dev/${target_dev} ?"
if [ $? -eq 1 ]; then
  Replace_Sourcedev_Targetdev /etc/recovery/mkfs.${_source_dev} /tmp/mkfs.${_target_dev} || Replace_Sourcedev_Targetdev /etc/recovery/md/mkfs.${_source_dev} /tmp/mkfs.${_target_dev}
  chmod +x /tmp/mkfs.${_target_dev}
  echo "y" | ${DEBUG} /tmp/mkfs.${_target_dev}
  print "\nTarget disk (/dev/${target_dev}) is ready to be restored.\n"
else
  print "\nSkip mkfs process of target disk /dev/${target_dev}\n"
fi # of askyn

# Step 7: make the swap if any
if [ -f /etc/recovery/mkswap.sh ]; then
 askyn Y "Initialize the swap partition ?"
 if [ $? -eq 1 ]; then
  if [ -f /etc/recovery/mdstat ]; then
    # Software RAID swap partition
    xmd=`tail -n 1 /etc/recovery/mkswap.sh | awk '{print $2}' | cut -d"/" -f 3` # md2
    x=`grep ${xmd} /etc/recovery/mdstat | sed -e 's/.*'${source_dev}'/'${source_dev}'/' -e 's/\[.*//'` #hdb3
    mv /etc/recovery/mkswap.sh /etc/recovery/old.mkswap.sh
    sed -e 's/'${xmd}'/'${x}'/g' < /etc/recovery/old.mkswap.sh > /etc/recovery/mkswap.sh
  fi  
  # remove other swap part. - keep only swap to clone
  grep ${source_dev} /etc/recovery/mkswap.sh >/tmp/t1
  Replace_Sourcedev_Targetdev /tmp/t1 /tmp/mkswap.sh
  rm /tmp/t1
  print "\nInitialize the swap partition:\n"
  cat /tmp/mkswap.sh
  chmod +x /tmp/mkswap.sh
  ${DEBUG} /tmp/mkswap.sh
  print "\nSwap partition is made and swapon /dev/${target_dev} done.\n"
 else
  print "\nSkip the initialization of the swap partition.\n"
 fi # of askyn
fi

# Step 7bis: label partitions if needed
if [ -f /etc/recovery/mke2label.sh ]; then
 askyn Y "Shall I label the partitions (LABEL) ?"
 if [ $? -eq 1 ]; then
  if [ -f /etc/recovery/mdstat ]; then
     # Software RAID active - so first change md to source_dev
     mv /etc/recovery/mke2label.sh /etc/recovery/old.mke2label.sh
     cat /etc/recovery/old.mke2label.sh | { while read Line
     do
       xmd=`echo ${Line} | awk '{print $2}' | cut -d"/" -f 3` # md0
       x=`grep ${xmd} /etc/recovery/md/df.${HOSTNAME} | grep ${source_dev} | awk '{print $1}'` #/dev/hdb3
       _tmp_fs=`echo ${Line} | awk '{print $3}'` # eg. /home
       echo "e2label ${x} ${_tmp_fs}" >> /etc/recovery/mke2label.sh
     done
     }
  fi
  # now replace source_dev by target_dev                    
  Replace_Sourcedev_Targetdev /etc/recovery/mke2label.sh /tmp/mke2label.sh
  chmod +x /tmp/mke2label.sh
  ${DEBUG} /tmp/mke2label.sh
  print "\nPartitions have been labeled.\n"
 else
  print "\nLabeling skipped.\n" 
 fi # of askyn
fi

# Step 8: restore one partition a time
DeviceCdrom     # defines cdrom device (for umounting if needed)
cd /etc/recovery
print "\nSource disk /dev/${source_dev} contains out of the following partition(s):\n"
cd /mnt/cdrom/
ls -1 ${_source_dev}*.log* 2>/dev/null | cut -d"." -f 1 
[ -d /etc/recovery/md ] && ls -1 *.log* 2>/dev/null | cut -d"." -f 1
cd /etc/recovery        # we may not occupy /cdrom (or we cannot umount it)

askyn Y "Shall I restore all partitions ?"
restore_all=$?

if [ -f /etc/recovery/md/To_Restore.md ] && [ ! -f /etc/recovery/old.To_Restore ]; then
   # Software RAID original, but disk format was skipped
   mv /etc/recovery/To_Restore /etc/recovery/old.To_Restore
   cp /etc/recovery/md/To_Restore.md /etc/recovery/To_Restore
fi

(grep ${source_dev} /etc/recovery/To_Restore && grep mapper /etc/recovery/To_Restore) | \
{ while read Line
do
  ### loop over the backup-ed file-systems - restore one per one
  ParseDevice ${Line}
  SDev=${Dev} # eg. hdb3
  # we have a SDev (eg. hdb3), so remap it into TDev (eg. sda3)
  TDev=`Replace_Sourcedev_Targetdev_2 ${SDev}`
  # check if Software RAID is in use
  if [ -f /etc/recovery/mdstat ]; then
     # Oops: original was meta-device, so map hdb3 to eg. md0
     # why? restore /cdrom/md0._boot.tar.gz onto /dev/sda3 (if hdb3 was in Line)
     # What do we know? SDev=hdb3, source_dev=hdb, target_dev=sda
     # use md/df.$HOSTNAME to find corresponding original SDev, eg. md0
     SDev=`grep ${SDev} /etc/recovery/md/df.${HOSTNAME} 2>/dev/null | awk '{print $7}'`
     [ -z "${SDev}" ] && echo "Problem re-mapping SDev from meta-device" && exit 1
  fi
  Fs=`echo ${Line} | awk '{print $2}'`          # eg. /usr
  _Fs=`echo ${Fs} |  tr "/" "_"`                # eg. _usr
  FStype=`echo ${Line} | awk '{print $3}'`
  if [ ${BACKUPS_ON_MT} -eq 1 ]; then
        # check if we have to fsf on tape (skipped a disk?)
        warn "Tapes are sequential. I hope you did not skip a disk?"
        # I'm not sure this will work. TESTING needed.
        mt -f ${RESTORE} fsf ${FSF}
        BACKUPS_ON_MT=0
  fi
  # before attempting to mount ext3 force modprobes
  if [ "${FStype}" = "ext3" ]; then
     modprobe ext3 >/dev/null 2>&1
     modprobe freext3 >/dev/null 2>&1
  fi
  sleep 2
  # mount the partition on LOCALFS
  mount -t ${FStype} /dev/${TDev} ${LOCALFS}
  if [ $? -eq 1 ]; then
        error 1 "Could not mount /dev/${TDev} on ${LOCALFS}. Please investigate manually."
  fi 
  ### cd ${LOCALFS}
  # retrieve the tar
  color yellow black
  print "\n\n\nStart the restore of /dev/${TDev} on ${Fs}\n\n"
  echo ""
  color white black

  ## call function to do the restore (restore source_dev backup on target_dev)
  Dev=${SDev}           # needed because 'Get_backup_back' is a shared fct
  _Dev=`echo ${Dev} | tr "/" "_"`
  [ ${restore_all} -ne 1 ] && askyn Y "Shall I restore ${Fs} on /dev/${TDev} ?"
  
  if [ $? -eq 1 ]; then         # do the restore
     Get_backup_back

     if [ ${err} -eq 1 ]; then
         error 1 "Could not restore ${Fs} on /dev/${TDev}. Please investigate."
     fi
 
     sync; sync; sync
     if [ "${Fs}" = "/" ]; then
        cd ${LOCALFS}
        mkdir -p proc > /dev/null 2>&1
        /etc/recovery/mkdirs.sh # make any missing mount point
        OK_TO_REBOOT=1 # 1: /proc made (2: LILO OK)
     fi
     cd /
     sync; sync; sync
     print "Unmount ${LOCALFS} and do a fsck on /dev/${TDev}\n"
     umount ${LOCALFS}
     # do a fsck a restore TDev
     case ${FStype} in
       ext2) fsck.ext2 -y /dev/${TDev} ;;
       ext3) fsck.ext3 -y /dev/${TDev} ;;
       reiserfs) echo Yes | fsck.reiserfs /dev/${TDev} ;;
       xfs) fsck.xfs /dev/${TDev} ;;
       jfs) fsck.jfs -a -f /dev/${TDev} ;;
       msdos|vfat) fsck.dos -vV /dev/${TDev} ;;
     esac 
  fi # of answer
done # end of part loop
}

# Step 9: LILO the system
# Mount the / partition on LOCALFS and if needed the /boot partition on /boot
cd /etc/recovery
# Find the ROOT/BOOT partitions
BOOTDEV=""
BOOTFS=""
ROOTDEV=""
ROOTFS="/"
for mdsk  in `ls mkfs.${_source_dev}`
do
        _dsk=`echo ${mdsk} | cut -d"." -f 2`
        dsk=`echo ${_dsk} | tr "_" "/"`
        grep -q ${dsk} /etc/recovery/To_Restore
        if [ $? -eq 1 ]; then
           # Oops, DevFS naming mixed up - find corresponding dsk
           DevFS_naming_mix             # dsk redefined
        fi
        # loop over all partition of $source_dev
        cat /etc/recovery/To_Restore | grep ${dsk} | \
        { while read Line
        do
          ParseDevice ${Line}
          SDev=${Dev}
          TDev=`Replace_Sourcedev_Targetdev_2 ${SDev}`
          Fs=`echo ${Line} | awk '{print $2}'`
          if [ "${Fs}" = "/" ]; then
                echo /dev/${TDev} > /tmp/ROOTDEV
                echo ${Fs} > /tmp/ROOTFS
                echo ${Line} | awk '{print $3}' > /tmp/ROOTFStype
                echo ${Line} | awk '{print $4}' > /tmp/ROOTFSopt
          fi
          if [ "${Fs}" = "/boot" ]; then
                echo /dev/${TDev} > /tmp/BOOTDEV
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
        error 1 "LILO does not make any sense if / was not restored on 
/dev/${target_dev}, but the restore itself was OK."
fi

mount -t ${ROOTFStype} ${ROOTFSopt} ${ROOTDEV} ${LOCALFS}
if [ $? -eq 1 ]; then
        error 1 "Mounting ${ROOTDEV} on ${LOCALFS} gave errors."
fi

if [ -f /tmp/BOOTDEV ]; then    # boot dev. not the same as root dev.
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
                error 1 "Could not mount ${BOOTDEV} on ${LOCALFS}${BOOTFS}. Cannot do ${BOOTLOADER}. Try it manually."
        fi
fi

# modify the /etc/fstab file too if necessary (29/12/00)
if [ -f /etc/recovery/mdstat ]; then
   echo "Software Raid detected for source disks - create new fstab file"
   # Software RAID active - so first change md to source_dev
   mv ${LOCALFS}/etc/fstab ${LOCALFS}/etc/old.fstab
   cat ${LOCALFS}/etc/old.fstab | { while read Line
   do
     echo ${Line} | grep "^/dev/md" >/dev/null 2>&1
     if [ $? -eq 0 ]; then
        # probably /dev/md? or /dev/md/? (make source_dev)
        xmd=`echo ${Line} | awk '{print $1}' | cut -d"/" -f 3` # md0
        x=`grep ${xmd} /etc/recovery/md/df.${HOSTNAME} | grep ${source_dev} | awk '{print $1}' | cut -d"/" -f 3` # hdb3
        rest=`echo ${Line} | awk '{print $2"\t"$3"\t"$4"\t"$5"\t"$6}'`
        echo "/dev/${x}         "${rest} >> ${LOCALFS}/etc/fstab
     else
        # Line contains no /dev/md? - write it out
        echo ${Line} >> ${LOCALFS}/etc/fstab
     fi
   done
   }
fi   
${DEBUG} mv ${LOCALFS}/etc/fstab ${LOCALFS}/etc/fstab.${_source_dev}
Replace_Sourcedev_Targetdev ${LOCALFS}/etc/fstab.${_source_dev} ${LOCALFS}/etc/fstab

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
     for grub_config in menu.lst grub.conf; do
        [ -f ${LOCALFS}/boot/grub/${grub_config} ] || continue
        cp ${LOCALFS}/boot/grub/${grub_config} ${LOCALFS}/boot/grub/${grub_config}.${_source_dev}
        Replace_Sourcedev_Targetdev ${LOCALFS}/boot/grub/${grub_config}.${_source_dev} ${LOCALFS}/boot/grub/${grub_config}
     done

     # /boot/grub/device.map accordingly new boot device
     if [ -f  ${LOCALFS}/boot/grub/device.map ]; then
        ${DEBUG} mv ${LOCALFS}/boot/grub/device.map ${LOCALFS}/boot/grub/device.map.${_source_dev}
        Replace_Sourcedev_Targetdev ${LOCALFS}/boot/grub/device.map.${_source_dev} ${LOCALFS}/boot/grub/device.map
        ${DEBUG} chmod 600 ${LOCALFS}/boot/grub/device.map
     fi

     # get details of boot partition in grub format
     # /tmp/BOOTDEV contains e.g. /dev/hda1 and TARGET_DISK=/dev/sda
     if [ -f /tmp/BOOTDEV ]; then 
        GRUB_PARTITION=`sed -e 's#'${TARGET_DISK}'##' </tmp/BOOTDEV` 
     else 
        GRUB_PARTITION=`sed -e 's#'${TARGET_DISK}'##' </tmp/ROOTDEV` 
     fi 
     # strip all non-numerical characters before deducting one
     GRUB_PARTITION=`echo ${GRUB_PARTITION} | sed -e 's/[A-Za-z]//'`
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
     fi # $? of chroot
  fi # of type -path grub
elif [ "${BOOTLOADER}" = "LILO" ]; then
  if [ ! -x "`type -path lilo`" ]; then
     print "I can't find lilo on the system.\n"
     print "If you installed mkCDrec utilities try grubconfig instead!\n"
  else
     # be polite ask if executing lilo is wanted or not
     askyn Y "Shall I adapt lilo.conf and /etc/fstab for you + lilo the disk ?"
     if [ $? -eq 1 ]; then
       # change lilo.conf accordingly the new boot device
       if [ -f /etc/recovery/mdstat ]; then
            # Software RAID active - so first change md to source_dev
            echo "Software RAID source disk detected - lilo.conf"
            mv ${LOCALFS}/etc/lilo.conf ${LOCALFS}/etc/old.lilo.conf
            cat ${LOCALFS}/etc/old.lilo.conf | { while read Line
            do
              echo ${Line} | grep "/dev/md" >/dev/null 2>&1
              if [ $? -eq 0 ]; then
                # probably root=/dev/md? or boot=/dev/md? (make source_dev)
                prefix=`echo ${Line} | cut -d"/" -f 1-2` # boot=/dev
                xmd=`echo ${Line} | cut -d"/" -f 3` # md0
                x=`grep ${xmd} /etc/recovery/md/df.${HOSTNAME} | grep ${source_dev} | awk '{print $1}' | cut -d"/" -f 3` # hdb3
                echo "${prefix}/${x}" >> ${LOCALFS}/etc/lilo.conf
              else
                # Line contains no /dev/md? - write it out
                echo ${Line} >> ${LOCALFS}/etc/lilo.conf
              fi
            done
            }
       fi # of [ -f /etc/recovery/mdstat ]
       ${DEBUG} mv ${LOCALFS}/etc/lilo.conf ${LOCALFS}/etc/lilo.conf.${_source_dev}
       Replace_Sourcedev_Targetdev ${LOCALFS}/etc/lilo.conf.${_source_dev} ${LOCALFS}/etc/lilo.conf
       ${DEBUG} chmod 600 ${LOCALFS}/etc/lilo.conf


       # do the 'lilo' command now
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
          print "When error \"duplicate entry loader\" occurs delete the duplicate line\n"
          print "and run \"lilo\" again. If that does not help, then\n"
          print "try it with \"chroot ${LOCALFS} liloconfig\" instead.\n"
        fi # lilo
       fi # chroot lilo
     fi # of askyn
  fi # of type -path lilo
else
  print "Bootloader ${BOOTLOADER} is NOT yet supported!\n"
  print "Try your luck with \"chroot ${LOCALFS} liloconfig\" or\n"
  print "\"chroot ${LOCALFS} grubconfig\" instead.\n"
fi # of BOOTLOADER

# force a sync to forecome boot problems
sync ; sync

# Step 10: all disks were restored.
if [ ${OK_TO_REBOOT} -eq 2 ]; then
        color white blue
        print "\n\nSource disk has been successfully cloned.\n"
        print "You may reboot the system now."
        if [ "${source_dev}" != "${target_dev}" ]; then
         print "\nHowever, it would be wise to inspect ${LOCALFS}/etc/lilo.conf and ${LOCALFS}/etc/fstab before rebooting!"
        fi
else
        color black red
        print "\n\nSource disk has been successfully restored.\n"
        print "\n\n${BOOTLOADER} was not successfully done.\n"
        print "Not sure if a reboot will be OK."
        print "Please check ${LOCALFS}/etc/lilo.conf and ${LOCALFS}/etc/fstab files.\n"
fi
        print "\nCheck also if the network parameters are setup correctly."
        color white black
for i in 1 2 3 4 5 6 7 8 9
do
        echo -n ""
done
echo
exit
