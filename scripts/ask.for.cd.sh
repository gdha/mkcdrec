#!/bin/sh
# ask.for.cd.sh is a helper script of pastestream program
# Copyright (C) 2001-2008 - Gratien D'haese - IT3 Consultants
#
# INPUT:	RESTORE = path/file pasted into pipe of TAR
# OUTPUT:	RESTORE = pastestream will open this file
#		MORE_TO_COME = 0/1 (0 ends stream and quits pastestream)
# Be Careful NOT to mangle with STDOUT, use STDERR instead
# /dev/stderr must be linked to /proc/self/fd/2
# $Id: ask.for.cd.sh,v 1.7 2008/07/09 13:35:52 gdha Exp $

# FUNCTIONS
###########
warn() {

    echo -ne "[1;31;40mWARNING:[0;37;40m\n" > /dev/stderr
    echo -ne "[0;32;40m${1}[0;37;40m\n" > /dev/stderr
    prompt
}

prompt () {

    echo -ne "[0;37;40mPress [1;37;40m[ENTER][0;37;40m to continue or [1;35;40m[CTRL-C][0;37;40m to abort: " > /dev/stderr
    read junk < ${MY_TTY}

}

# MAIN
######
# set STDout aside (to be sure not to mangle it with output of here)
exec 5<&1	# use fd 5 as a temporary fd for stdout

# check current tty and fill in proper CONSOLE value
MY_TTY=`cat /tmp/my_tty`

CDROM=`grep cdrom /proc/mounts | awk '{print $1}'`	# /dev/cdrom

OLDPW=`pwd`
cd /cdrom
ls CDrec-* > /dev/null 2>&1
if [ $? -eq 1 ]; then
   echo "This CD-ROM was not created by mkCDrec, but how did you get so far?" > /dev/stderr
   exit 1
fi
CDrecDate=`ls CDrec-* | cut -d"_" -f 1`
volno=`ls CDrec-* | cut -d"_" -f 2`
# complete current VolID is ${CDrecDate}_${volno}
if [ -f LAST_CD ]; then
   volno=1		# LAST_CD found, end of set go back to one
else
   volno=$((volno+1))
fi

# read the previous RESTORE variable from /tmp/restore
RESTORE=`cat /tmp/restore`

cd ${OLDPW}

while ( true )
do
  umount ${CDROM} >/dev/null 2>&1
  warn "Please insert mkCDrec CD ${CDrecDate}_${volno} containing
the next part of ${RESTORE}."
  sleep 2
  mount -r -t iso9660 ${CDROM} /mnt/cdrom >/dev/null 2>&1
  sleep 3
  if [ -f /cdrom/${CDrecDate}_${volno} ]; then
	break
  fi
done


# reset RESTORE and MORE_TO_COME before going back to pastestream
# RESTORE can be e.g. hda1._usr.tgz_

if [ -f ${RESTORE} ]; then	# name still ends with _
   # next part is still a splitted backup (more to come)
   MORE_TO_COME=1
else
   # last part of set tgz_ becomes tgz
   RESTORE=`echo ${RESTORE} | sed -e 's/_$//'`
   MORE_TO_COME=0
fi
echo ${RESTORE} > /tmp/restore
echo ${MORE_TO_COME} > /tmp/more_to_come
# before we quit restore STDout
exec 1<&5 5<&-
