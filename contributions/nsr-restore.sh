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
# $Id: nsr-restore.sh,v 1.2 2007/11/13 14:38:13 gdha Exp $
####
### nsr-restore.sh was contributed by Schlomo Schapiro, pro business Berlin AG
####

. ./ansictrl.sh
. ./restore_common.sh

LANG=C

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
print "\tRestore with Legato Networker\n\n"
color white black
print "$(basename "$0") script will reformat and re-install all data from backup.\n\n"
color red white
print "                                                                          \n"
print "The Date and Time on this machine is $(date -R)\n"
print "                                                                          \n"
print "If this is wrong, please abort and set the correct time first !\n\n"
color white black

# Step 1: check if with this CD was the result of a backup, or just Rescue
# When using DP to restore data a rescue CD is sufficient
Step1

# Step 2: try to find the location of the FS archives
#Step2
# OK, location is not on CD, disk or tape (in gzipped tar format) but we
# must talk to a TSM Server to request the data

# sleep a bit:
sleep 2

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


# Step 7b: start the Legato Networker restore
# recover everything from / to $LOCALFS
# we have to give all filesystems to recover on the command line
print "Starting Legato Networker daemon.\n"
/usr/sbin/nsrexecd
sleep 2
nsrwatch -p 1 </dev/tty9 >/dev/tty9 2>&1 &
print "Started nsrwatch on console 9.\n"
NSR_FILESYSTEMS="$(tr -s " \t" "?" < To_Restore | cut -d "?" -f 2 | tr "\n" " ")"
print "Recovering filesystems: $NSR_FILESYSTEMS\n"
BLANK="                                                                                                                                                                                            "
recover -d $LOCALFS -a $NSR_FILESYSTEMS 2>&1 | \
	while read -r ; do 
		echo -ne "\r${BLANK:1-COLUMNS}\r"
		case "$REPLY" in
			*:*\ *)	echo "$REPLY" ;;
			./*)	if [ "${#REPLY}" -ge $((COLUMNS-5)) ] ; then
					echo -n "... ${REPLY:5-COLUMNS}"
				else
					echo -n "$REPLY"
				fi
				;;
			*)	echo "$REPLY" ;; 
		esac 
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
