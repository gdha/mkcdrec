#!/bin/bash
# Copyright (C) 2000-2007 - Gratien D'haese - IT3 Consultants
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
# $Id: tsm-restore.sh,v 1.8 2009/01/05 09:20:37 gdha Exp $
####
### tsm-restore.sh was sponsored by LDS Potsdam
####
LOCALFS=/mnt/local

. ./ansictrl.sh
. ./restore_common.sh

PATH=$PATH:/opt/tivoli/tsm/client/ba/bin

LANG=C

color white black

BACKUPS_ON_MT=0
OK_TO_REBOOT=0

## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

# Step -1: read TSM config information

# read dsm.sys
while read KEY VALUE ; do echo "$KEY" | grep -q '*' && continue ; test -z "$KEY" && continue ; KEY="$(echo "$KEY" | tr a-z A-Z)" ; export TSM_SYS_$KEY="${VALUE//\"}" ; done </opt/tivoli/tsm/client/ba/bin/dsm.sys
# read dsm.opt
while read KEY VALUE ; do echo "$KEY" | grep -q '*' && continue ; test -z "$KEY" && continue ; KEY="$(echo "$KEY" | tr a-z A-Z)" ; export TSM_OPT_$KEY="${VALUE//\"}" ; done </opt/tivoli/tsm/client/ba/bin/dsm.opt

# Step 0: write welcome

clear
color white blue
print "\n\n\tmk${VERSION}\n\n"
print "\tRestore with Tivoli Storage Manager\n\n"
color white black
print "$(basename "$0") script will reformat and re-install all data from backup.\n\n"
print "TSM Server ${TSM_SYS_TCPSERVERADDRESS} must be pingable.\n"
ping -c 1 ${TSM_SYS_TCPSERVERADDRESS} >/dev/null 2>&1
if [ $? -eq 0 ]; then
   print "TSM Server ${TSM_SYS_TCPSERVERADDRESS} seems to be up and running.\n"
else
   error 1 "Sorry, but cannot reach TSM Server ${TSM_SYS_TCPSERVERADDRESS}"
fi

# Step 1: check if with this CD was the result of a backup, or just Rescue
# When using DP to restore data a rescue CD is sufficient
Step1

# Step 2: try to find the location of the FS archives
#Step2
# OK, location is not on CD, disk or tape (in gzipped tar format) but we
# must talk to a TSM Server to request the data

# sleep a bit:
sleep 2

# find out which filespaces (= mountpoints) are available for restore
TsmFilespaces="$(dsmc query filespace -date=2 -time=1)"
echo "The TSM Server reports the following for this node:"
echo "$TsmFilespaces"
echo ""
echo "Please enter the numbers of the filespaces we should restore."
echo "Pay attention to enter the filesystems in the correct order"
read -p "(like restore / before /var/log) ! (ex. 1 2): " DoFilespaces
DoFilespaces="$(echo "$DoFilespaces" |tr -s " ")"
test "$DoFilespaces" -a ${#DoFilespaces} -gt 0 || error 1 "No filespaces selected !"
echo "I will now restore the following filesystems:"
for k in $DoFilespaces ; do
	FileSpace="$(echo "$TsmFilespaces" | grep "^ *$k *" | awk '{print $5}' )"
	echo "$FileSpace"
done
askyn Y "Is this selection correct ?"
if [ $? -eq 0 ]; then
	# NO
	error 1 "User abort"
fi



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


# Step 7b: start the TSM restore
for k in $DoFilespaces ; do
	FileSpace="$(dsmc query filespace | grep "^ *$k *" | tr -s " " | cut -d " " -f 6)"
	# make sure FileSpace has a trailing / (for dsmc)
	test "${FileSpace:0-1}" == "/" || FileSpace="$FileSpace/"
	color yellow black
	print "\n\n\nStart the restore of $FileSpace on $LOCALFS$FileSpace\n\n"
	color white black
	echo Running dsmc restore "${FileSpace}*" $LOCALFS$FileSpace -verbose -subdir=yes -replace=all -tapeprompt=no
	TsmProcessed=""
	dsmc restore "${FileSpace}*" $LOCALFS$FileSpace -verbose -subdir=yes -replace=all -tapeprompt=no | \
		while read Line ; do
			if test "${Line:0:8}" == "ANS1898I" ; then
				TsmProcessed="$(echo "${Line:9}" | tr -s '*') "
				Line="Restoring" # trigger star
			fi 
			if test "${Line:0:9}" == "Restoring" ; then
				echo -n "$TsmProcessed" 
				star
			else
				echo "$Line"
			fi
		done
done

# /dev and uDev Linux based systems need some help with populating a
# minimal /dev at boot time otherwise a panic is the result. Furhermore,
# TSM, NSR or DP do not backup /dev when FStype is tmpfs.
CreateMinimalDev

# Step 8: LILO/GRUB the system
# Mount the / partition on LOCALFS and if needed the /boot partition on /boot
Step8

# Step 9: all disks were restored.
Step9

echo "Before rebooting the system please investigate ${LOCALFS}/etc/fstab file."

sync
exit
