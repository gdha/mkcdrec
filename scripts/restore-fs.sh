#!/bin/bash
# Copyright (C) 2001-2008 - Gratien D'haese - IT3 Consultants
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
# WARNING: this script will overwrite one partition   #
#######################################################
# DISASTER RECOVERY means restore data back to disk as it was made on the
# date the backup was made! It does not mean or replace BACKUPS!!!
# $Id: restore-fs.sh,v 1.18 2008/07/09 13:35:52 gdha Exp $

. ./Config.sh
. ./restore_common.sh
. ./ansictrl.sh
color white black

BACKUPS_ON_MT=0

## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

###################################################################
## MAIN

#########
# Step 0: write welcome
#########
clear
color white blue
print "\n\n\tmk${VERSION}\n\n"
print "\tRestore a Linux filesystem with mkCDrec\n\n"
color white black
warn "`basename $0` script will not recreate disk partition layout!\n
You have to create the disk partition layout yourself with fdisk, sfdisk,
cfdisk or parted. In /etc/recovery you find the necessary documentation."


#########
# Step 1: check if this CD was the result of a backup, or just Rescue
#########
Step1

#########
# Step 2: try to find the location of the FS archives
#########
Step2

#########
# Step 3: the backups were seen, here we have to check if a physical device 
######### really exists. Otherwise, we cannot restore.

cd /etc/recovery
Check_df_file # if df.hostname is not the same as df.FQDN

# Check how many disks are candidates to restore.
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
ls -l /dev/sd* | awk '{print $5, $6, $10}' | sed  's/,//' > /tmp/ls_sd
# list all found scsi devices in /tmp/scsi_devs
egrep -A 1 Host /proc/scsi/scsi | sed -e 's/^[  ]*//' > /tmp/scsi_devs
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
}
fi #of /proc/scsi/scsi

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
# after last step some devices could be double listed - uniq/sort
cat /tmp/available.disks | sort | uniq > /tmp/available.new
mv -f /tmp/available.new /tmp/available.disks


# end of disk scanning (all potential installation disks are in file
# /tmp/available.disks )


#########
# Step 4: Select filesystem which we want to restore
#########

stest=0
while ( test ${stest} -lt 1 )
do
clear
color green black
print "\n\nmk${VERSION} - Select filesystem to restore"
color white black
printat 7 1 "Enter your selection:\n\n"

i=1
declare -a FS   # declare array FS[i]
{ while read Line
do
    FS[${i}]=`echo ${Line} | awk '{print $2}'`
    print " ${i}) ${FS[${i}]}\n"
    i=`expr ${i} + 1`
done
} < /etc/recovery/To_Restore
high_i=`expr ${i} - 1`
selection 1-${high_i}
ANS=$?

if [ ${ANS} -gt 0 -a ${ANS} -le ${#FS[@]} ]; then
        stest=1
fi
done    # of stest
FileSystem=${FS[${ANS}]}
FSF=`expr ${ANS} - 1`   # if backup is on tape (fastforward)
unset FS

########
# Step 5: select target disk (if more than 1 available)
########
# count how many target disks are available: if only 1 then skip next question
nr_target_disk=`wc -l /tmp/available.disks | awk '{print $1}'`

# Now present the user a list of possible target disks to install to. (if >1)
if [ ${nr_target_disk} -eq 1 ]; then
   TARGET_DISK=`cat /tmp/available.disks`
else
# #disks > 1
stest=0
while ( test ${stest} -lt 1 )
do
clear
color green black
print "\n\nmk${VERSION} - Select disk to restore filesystem on"
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
        size=`sfdisk -s ${Line}`
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
fi   # of nr_target_disk

TARGET_DISK_SIZE=`sfdisk -s ${TARGET_DISK} 2>/dev/null`
unset target_dev
target_dev=`echo ${TARGET_DISK} | cut -d"/" -f 3-`
_target_dev=`echo ${TARGET_DISK} | cut -d"/" -f 3- | tr "/" "_"`

########
# Step 6: select target partition according the target_dev layout
########
stest=0
while ( test ${stest} -lt 1 )
do
clear
color green black
print "\n\nmk${VERSION} - Select target partition to restore ${FileSystem} on"
color white black
printat 7 1 "Enter your selection:\n\n"
i=`sfdisk -l ${TARGET_DISK} | grep "^/dev/" | wc -l | awk '{print $1}'`
sfdisk -l ${TARGET_DISK}
selection 1-${i}
ANS=$?

if [ ${ANS} -gt 0 -a ${ANS} -le ${i} ]; then
   stest=1
fi
done # of stest
partition=`sfdisk -l ${TARGET_DISK} | grep "^/dev/" | head -n ${ANS} | tail -n 1|awk '{print $1}'`
partition_size=`sfdisk -l ${TARGET_DISK} | grep "^/dev/" | head -n ${ANS} | tail -n 1| sed -e 's/*//'| awk '{print $5}'| sed -e 's/[-+]//'`

########
# Step 7: does FileSystem fits into the partition
########
if [ -z "${partition_size}" ]; then
   error 1 "$partition: Please select a valid partition next time..."
fi
{ while read Line
do
    FS=`echo ${Line} | awk '{print $6}'`
    if [ "${FS}" = "${FileSystem}" ]; then
       UsedbyFS=`echo ${Line} | awk '{print $3}'`
    fi
done
} < /etc/recovery/df.`hostname`

if [ -z "${UsedbyFS}" ]; then
   error 1 "Mission Impossible Not Possible. ${FileSystem} was not mounted at backup."
fi

if [ ${UsedbyFS} -gt ${partition_size} ]; then
   error 1 "Too bad! Filesystem ${FileSystem} (${UsedbyFS} Kb) cannot be restored in ${partition} (${partition_size} Kb)."
fi

# Still here? What do we know so far:
#  FileSystem and partition (to restore FileSystem on)
# New question: which FStype to use?
# Consideration: when FStype=vfat|msdos we do not need to mkfs.msdos as the 
# archives are in dd format 

{ while read Line
do
    FS=`echo ${Line} | awk '{print $2}'`
    if [ "${FS}" = "${FileSystem}" ]; then
       FStype=`echo ${Line} | awk '{print $3}'`         # FStype of source_dev
       source_dev=`echo ${Line} | awk '{print $1}'`     # /dev/hda1
    fi
done
} < /etc/recovery/To_Restore

SelectExtention         # uses $FStype to select EXT
# $EXT=dd for msdos|fat|vfat
# $EXT=tar for minix,ext2,ext3,reiserfs,xfs,jfs

########
# Step 8: FStype selection (to format partition with - does not have to be the
########  same as FileSystem was original).
#         Exception for EXT=dd (makes no sense to ask here ;-)
rm -f /tmp/mkfs.sh      # make sure there is none to begin with

if [ "${EXT}" = "tar" ]; then
# fill up 2 arrays with known FileSystem tools available on this system
declare -a FStype FSname        # array of mkfs.fs utilities
i=1
for fstype in mkfs.minix mkfs.ext2 mkfs.ext3 mkfs.msdos mkfs.reiserfs mkfs.xfs mkfs.jfs
do
   found=`which ${fstype} 2>/dev/null`
   echo ${found} | grep which >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      # which: no mkfs. is printed to stdout (should be stderr)
      found=""
   fi
   if [ -z ${found} ]; then
      continue
   else
      FStype[${i}]=${found}     # fill absolute path of exe into array FStype
      case ${fstype} in
        mkfs.minix) FSname[${i}]=minix ;;
        mkfs.ext2) FSname[${i}]=ext2 ;;
        mkfs.ext3) FSname[${i}]=ext3 ;;
        mkfs.msdos) FSname[${i}]=msdos ;;
        mkfs.reiserfs) FSname[${i}]=reiserfs ;;
        mkfs.xfs) FSname[${i}]=xfs ;;
        mkfs.jfs) FSname[${i}]=jfs ;;
      esac
      i=`expr ${i} + 1`
   fi 
done
nr=`expr ${i} - 1` # minus 1 to be correct

# display the FStype menu
stest=0
while ( test ${stest} -lt 1 )
do 
clear
color green black
print "\n\nmk${VERSION} - Select filesystem type to create on $partition"
color white black
printat 7 1 "Enter your selection:\n\n"
i=1
while ( test ${i} -le ${nr} )
do
    print " ${i}) ${FSname[${i}]}\n"
    i=`expr ${i} + 1` 
done
selection 1-${nr}
ANS=$?

if [ ${ANS} -gt 0 -a ${ANS} -le ${nr} ]; then
   stest=1
fi
done # stest

FileSystemName=${FSname[${ANS}]}        # FStype name
FileSystemExe=${FStype[${ANS}]}         # executable
unset FSname FStype
FStype=${FileSystemName}        # needed by Get_backup_back

# ParseDevice: /dev/hda2 returns Dev=hda2 and _Dev=hda2
ParseDevice ${partition}

# Options for non-JFS alike filesystems
JOURNAL=""
CHECK_BAD_BLOCKS="-c"

# Some specials for JFS type filesystems
case ${FileSystemName} in
  ext3) JOURNAL="-j"
        CHECK_BAD_BLOCKS="" ;;
  reiserfs|xfs) CHECK_BAD_BLOCKS="" ;;
  jfs) CHECK_BAD_BLOCKS=""
       JOURNAL="-f -v:jfs_${Dev}" ;;
esac
print "\nShall I execute: "
case ${FileSystemName} in
   vfat) print "mkfs.msdos -F 32 /dev/${Dev}"
         echo "mkfs.msdos -F 32 /dev/${Dev}" > /tmp/mkfs.sh
         ;;
   msdos|fat) print "mkfs.msdos -F 16 /dev/${Dev}"
              echo "mkfs.msdos -F 16 /dev/${Dev}" > /tmp/mkfs.sh
              ;;
   minix|ext2|ext3|auto|reiserfs|xfs|jfs)
         print "mkfs -t ${FileSystemName} ${JOURNAL} ${CHECK_BAD_BLOCKS} /dev/${Dev}"
         echo "mkfs -t ${FileSystemName} ${JOURNAL} ${CHECK_BAD_BLOCKS} /dev/${Dev}" > /tmp/mkfs.sh
         ;;
   *)   error 1 "Sorry, but ${FileSystemName} is unknown to me. If you think otherwise please tell me and explain why."
        ;;
esac

askyn Y ""
# returns 0 for NO, or 1 for YES
if [ $? -eq 1 ]; then
   chmod +x /tmp/mkfs.sh
   ${DEBUG} /tmp/mkfs.sh
fi # askyn

fi # of if EXT=tar (skip for EXT=dd)

#########
# Step 9: When backup is on tape position to FS
#########

if [ ${BACKUPS_ON_MT} -eq 1 ] && [ ${FSF} -gt 0 ]; then
   echo "Will fast forward tape ${FSF} time(s)."
   ${DEBUG} mt -f ${tape_dev} fsf ${FSF}
fi # end of backups are on tape

#########
# Step 10: restore filesystem
#########
# Extention EXT is:
#   dd: do not mount, just dump back
#  tar: mount first LOCALFS, then tar x

LOCALFSTMP=${LOCALFS}.$$
mkdir -p ${LOCALFSTMP}

DeviceCdrom     # defines cdrom device (for umounting if needed)
cd /etc/recovery

# define some vars. which will be used in Get_backup_back
SDev=`echo ${source_dev} | cut -d"/" -f 3-`
TDev=`echo ${partition} | cut -d"/" -f 3-`

if [ ! -z "${RESTORE_PATH}" ]; then
   # Dev is here source_dev in archive file ${_Dev}.${_Fs}.${EXT}.${CmpExt}
   Dev=${SDev}          # used by 'Get_backup_back' to restore on TDev
else                    # TAPE
   Dev=${TDev}          # Dev is device to dump to (=target_dev)
fi

_Dev=`echo ${Dev} | tr "/" "_"`

if [ "${EXT}" = "tar" ]; then
  # mount the partition on LOCALFSTMP
  ${DEBUG} mount -t ${FStype} /dev/${TDev} ${LOCALFSTMP}
  if [ $? -eq 1 ]; then
        error 1 "Could not mount /dev/${TDev} on ${LOCALFSTMP}. Please investigate manually."
  fi 
fi

# retrieve the tar

## call function to do the restore
Fs=${FileSystem}
_Fs=`echo ${Fs} | tr "/" "_"`
askyn Y "Shall I restore ${Fs} on /dev/${TDev} ?"
if [ $? -eq 1 ]; then
     LOCALFS=${LOCALFSTMP}	# Get_backup_back routine uses LOCALFS
     Get_backup_back

     if [ ${err} -eq 1 ]; then
         error 1 "Could not restore ${Fs} on /dev/${TDev}. Please investigate."
     fi
 
     sync; sync; sync
     if [ "${Fs}" = "/" ]; then
        cd ${LOCALFSTMP}
        ${DEBUG} mkdir -p proc > /dev/null 2>&1
        ${DEBUG} /etc/recovery/mkdirs.sh # make any missing mount point
     fi
     cd /
     sync; sync; sync
     print "Unmount ${LOCALFSTMP} and do a fsck on /dev/${TDev}\n"
     ${DEBUG} umount ${LOCALFSTMP}
     # do a fsck a restore Dev
     case ${FStype} in
       ext2) ${DEBUG} fsck.ext2 /dev/${TDev} ;;
       ext3) ${DEBUG} fsck.ext3 /dev/${TDev} ;;
       reiserfs) echo Yes | ${DEBUG} fsck.reiserfs /dev/${TDev} ;;
       xfs) fsck.xfs /dev/${Dev} ;;    # does an exit 0 (always)
       jfs) fsck.jfs -a -f /dev/${Dev} ;;
       msdos|vfat) ${DEBUG} fsck.msdos -vV /dev/${TDev} ;;
     esac 
fi # of askyn

if [ "${EXT}" = "tar" ]; then
   print "\nRemounting /dev/${TDev} on ${LOCALFSTMP}\n"
   ${DEBUG} mount -t ${FStype} /dev/${TDev} ${LOCALFSTMP}
fi

if [ -f /etc/recovery/mke2label.sh ]; then
   grep -q ${TDev} /etc/recovery/mke2label.sh
   if [ $? -eq 0 ]; then
        grep ${TDev} /etc/recovery/mke2label.sh | sh -
        print "\nPartition /dev/${TDev} has been labeled.\n"
   fi
fi
color white black
print "\nDone.\n"
exit
