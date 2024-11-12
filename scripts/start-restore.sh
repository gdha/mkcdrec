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
# $Id: start-restore.sh,v 1.47 2008/10/21 08:22:12 gdha Exp $

. ./Config.sh
. ./ansictrl.sh
. ./restore_common.sh

color white black

BACKUPS_ON_MT=0
OK_TO_REBOOT=0
FSF=0

## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

# Step 0: write welcome
clear
color white blue
print "\n\n\tmk${VERSION}\n\n"
print "\tStart restore part\n\n"
color white black
print "$0 script will reformat and re-install all data from backup.\n"
print "If you do not want to restore data to the same disk, but rather\n"
print "want to clone a disk, use the script clone-dsk.sh\n"
warn "Press Enter to continue with $0, or Ctrl-C to quit."

# Step 1: check if with this CD was the result of a backup, or just Rescue
Step1

# Step 2: try to find the location of the FS archives
Step2

# Step 3: the backups have been seen now. here we have to check if the
# physical device really exists. Otherwise, we cannot restore.
Step3

# Step 4: partition the disk(s)
Step4         

# Step 5: make the filesystem on the disk(s)  (format the partitions)
Step5

# Step 6: make the swap if any
# Step 6bis: label partitions if needed (new in RedHat 7.x)
Step6

# Step 7: restore partition per time

if [ "${RESTORE_DEV}" = "CDROM" ]; then
   Check_Multi_volume   # are we dealing with a multi volume CD? True=0
fi

DeviceCdrom             # define CDROM (eg. /dev/hdc)

cd /etc/recovery
for mdsk  in `ls mkfs.* md/mkfs.* lvm/mkfs.* 2>/dev/null`
do
  _dsk=`echo ${mdsk} | cut -d"." -f 2`
  dsk=`echo ${_dsk} | tr "_" "/" | sed -e 's/%137/_/g'`
  print "\nDisk /dev/${dsk} contains out of the following partition(s):\n"
  grep ${dsk} /etc/recovery/To_Restore | awk '{printf "%s\t%s\t\t%s\n", $1, $2, $3}'

  # are the backups on tape?
  # List all partitions with one disk, e.g. hda[1-19]
    cat /etc/recovery/To_Restore | grep ${dsk} | \
    { while read Line
    do
      ParseDevice ${Line}
      Fs=`echo ${Line} | awk '{print $2}'`      # eg. /usr
      _Fs=`echo ${Fs} | tr "/" "_"`             # eg. _usr
      FStype=`echo ${Line} | awk '{print $3}'`  # eg. ext2

      if [ ${BACKUPS_ON_MT} -eq 1 ]; then
        # check if we have to fsf on tape (skipped a disk?)
        echo "Tapes are sequential. I hope you did not skip a disk?"
        # I'm not sure this will work. TESTING needed.
        mt -f ${RESTORE} fsf ${FSF}
        # we can forward only once on a tape (as agreed before ;-)
        BACKUPS_ON_MT=0
      fi
      # load FStype modules if needed (doesnot hurt anyway)
      modprobe ${FStype} 2>/dev/null
      if [ "${FStype}" = "ext3" ]; then
        modprobe freext3 >/dev/null 2>&1
        sleep 2
      fi
      # mount the partition on LOCALFS
      mount -t ${FStype} /dev/${Dev} ${LOCALFS}
      if [ $? -eq 1 ]; then
        error 1 "Could not mount /dev/${Dev} on ${LOCALFS}. Please investigate manually."
      fi 
      #cd ${LOCALFS}    # do NOT do this for multi vols!
      color yellow black
      print "\n\n\nStart the restore of /dev/${Dev} on ${Fs}\n\n"
      echo ""
      color white black
      # retrieve the tar (call function Get_backup_back restore_common.sh)
      Get_backup_back
      if [ ${err} -eq 1 ]; then
        askyn N "An error occured during restoration. Do you want to continue?"
        if [ $? -eq  0 ]; then
           error 1 "Could not restore ${RESTORE} on /dev/${Dev}. Please investigate."
        fi
      fi
      sync; sync; sync
      if [ "${Fs}" = "/" ]; then
        cd ${LOCALFS}
        mkdir proc > /dev/null 2>&1
        /etc/recovery/mkdirs.sh # make any missing mount point
        OK_TO_REBOOT=1 # 1: /proc made (2: LILO OK)
      fi
      cd /
      sync; sync; sync
      print "Unmount ${LOCALFS} and do a fsck on /dev/${Dev}\n"
      umount ${LOCALFS}
      # do a fsck a restore Dev
      case ${FStype} in
        ext2) fsck.ext2  /dev/${Dev} ;;
        ext3) fsck.ext3 -y /dev/${Dev} ;;
        reiserfs) echo Yes | fsck.reiserfs /dev/${Dev} ;;
        xfs) fsck.xfs /dev/${Dev} ;;    # does an exit 0 (always)
        jfs) fsck.jfs -a -f /dev/${Dev} ;;
        msdos|vfat) fsck.msdos -vV /dev/${Dev} ;;
      esac
    done
    } # end of while loop
done # end for dsk loop

# Step 8: LILO/GRUB the system
# Mount the / partition on LOCALFS and if needed the /boot partition on /boot
Step8

# Step 9: all disks were restored.
for i in 1 2 3 4 5 6 7 8 9
do
        echo -n ""
done
Step9

exit
