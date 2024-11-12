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
# $Id: dp-restore.sh,v 1.10 2008/09/01 07:49:11 gdha Exp $
####
### dp-restore.sh was sponsored by Hewlett-Packard Belgium
####

if [ -d /usr/omni ]; then
   DP_ROOT_DIR="/usr/omni"      # DP 5.x
   DP_CONFIG_DIR="/usr/omni/config"      # DP 5.x
elif [ -d /opt/omni ]; then
   DP_ROOT_DIR="/opt/omni"      # DP 6.x
   DP_CONFIG_DIR="/etc/opt/omni"      # DP 6.x
fi

PATH=$PATH:${DP_ROOT_DIR}/bin

. ./Config.sh
. ./ansictrl.sh
. ./restore_common.sh

color white black

BACKUPS_ON_MT=0
OK_TO_REBOOT=0

## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

# Step 0: write welcome
clear
color white blue
print "\n\n\tmk${VERSION}\n\n"
print "\tRestore with Data Protector\n\n"
color white black
print "$0 script will reformat and re-install all data from backup.\n\n"
CellMgr=`cat ${DP_CONFIG_DIR}/*/cell_server`
print "Data Protector cell manager ${CellMgr} must be pingable.\n\n"
ping -c 1 ${CellMgr} >/dev/null 2>&1
if [ $? -eq 0 ]; then
   print "\nCell Manager ${CellMgr} seems to be up and running.\n\n"
else
   error 1 "Sorry, but cannot reach cell manager ${CellMgr}"
fi

# Step 1: check if with this CD was the result of a backup, or just Rescue
# When using DP to restore data a rescue CD is sufficient, but in the Config.sh
# file DP_RESTORE must be set to "y" (is detected by mkCDrec automatically)
Step1

# Step 2: try to find the location of the FS archives
#Step2
# OK, location is not on CD, disk or tape (in gzipped tar format) but we
# must talk to a DP Cell Manager to request the data
# We must know the DP_DATALIST_NAME of the full backup definition of this client
DP_DATALIST_NAME="`cat /etc/recovery/DP_DATALIST_NAME`"

if [ -z "${DP_DATALIST_NAME}" ]; then
   warn "No DP_DATALIST_NAME was found! Please use the \"omnidb -rpt\" command 
to retrieve information from the cell manager of the backup session you
need. Write the datalist name into /etc/recovery/DP_DATALIST_NAME, and rerun 
this script again."
   # exit anyway!
   exit 1
fi

# sleep a bit:
sleep 2

# show the menu
declare -a SessionID   # declare Array
stest=0
omnidb -session -datalist "${DP_DATALIST_NAME}" | grep Backup | \
grep Complete > /tmp/sessions

if [ ! -s /tmp/sessions ]; then                                
   error 1 "No Data Protector sessions were found. Are you sure you made a full backup?"
fi 

while ( test ${stest} -lt 1 )
do
  clear
  color green black
  print "\n\nmk${VERSION} - Select SessionID you wish to restore:"
  color white black
  printat 7 1 "Enter your selection:\n\n"
  i=1

  # we know the datalist name - retrieve info from cell mgr.
  { while read Line
  do
    print " ${i}) ${Line}\n"
    SessionID[${i}]=`echo ${Line} | awk '{print $1}'`
    #echo ${SessionID[${i}]}
    i=`expr ${i} + 1`
    echo $i >/tmp/i
  done
  } < /tmp/sessions
  high_i=`expr ${i} - 1`
  selection 1-${high_i}
  ANS=$?

  if [ ${ANS} -gt 0 -a ${ANS} -le ${high_i} ]; then
        stest=1
  fi
done # of stest
SESSIONID=${SessionID[${ANS}]}
unset SessionID

# Step 3: the backups have been seen now. here we have to check if the
# physical device really exists. Otherwise, we cannot restore.
Step3

# Step 4: reformat the disk(s)
# Before going on, are there still disks left to restore?
Step4

# Step 5: make the filesystem on the disk(s)
Step5

# Step 6: make the swap if any
Step6

# Step 7a: mount all filesystems on top of /mnt/local
MountLocalFileSystems

df
sleep 5

# Step 7b: start the Data Protector restore
rm -f /tmp/DP_RESTORE_FAILED
DEVICE=`omnidb -session ${SESSIONID} -detail | grep Device | sort -u | tail -n 1 | awk '{print $4}'`
omnidb -session ${SESSIONID} | grep -i filesystem | { while read Line
do
      DP_HOST_FS=`echo ${Line} | awk '{print $1}'`
      DP_FS=`echo ${DP_HOST_FS} | cut -d: -f 2`
      # FIXME: DP_LABEL is sometimes returned incorrectly
      DP_LABEL=`echo ${Line} | cut -d"'" -f 2`
      color yellow black
      print "\n\n\nStart the restore of ${DP_HOST_FS} on ${LOCALFS}${DP_FS}\n\n"
      color white black
      echo omnir -filesystem ${DP_HOST_FS} ${DP_LABEL} -session ${SESSIONID} -tree ${DP_FS} -into ${LOCALFS} -device ${DEVICE} -log
      omnir -filesystem ${DP_HOST_FS} "${DP_LABEL}" -session ${SESSIONID} -tree ${DP_FS} -into ${LOCALFS} -device ${DEVICE} -log
      case $? in
	0)  echo "Restore was successful." ;;
	10) echo "Restore finished with warnings." ;;
	*)  echo "ERROR: omnir failed."
		touch /tmp/DP_RESTORE_FAILED
		break # get out of the loop
		;;
      esac
done
}
if [ -f /tmp/DP_RESTORE_FAILED ]; then
   echo "
***************************************************************************
**  Please try to push the backups of session ${SESSIONID} from DP GUI  **
**  Make sure you select \"overwrite\" (destination tab) and make the    **
**  new destination \"${LOCALFS}\".                                      **
**  When the restore is complete press ANY key to continue!              **
*************************************************************************** 
"
   read answer
fi

# /dev and uDev Linux based systems need some help with populating a
# minimal /dev at boot time otherwise a panic is the result. Furhermore,
# TSM, NSR or DP do not backup /dev when FStype is tmpfs.
CreateMinimalDev

# Step 8: LILO/GRUB the system
# Mount the / partition on LOCALFS and if needed the /boot partition on /boot
Step8

# Step 9: all disks were restored.
Step9
sync

echo "Please check ${LOCALFS}/etc/fstab file before rebooting"
if [ "`uname -m`" = "ia64" ]; then
   echo "Also check `find ${LOCALFS}/boot/efi -name elilo.conf` file"
fi

exit
