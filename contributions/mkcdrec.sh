#!/bin/bash
# Small mkCDrec script running from cron to automate system DR backup
# Copyright (C) 2002-2007 - IT3 Consultants bvba - GPL2
######
# $Id: mkcdrec.sh,v 1.2 2007/11/13 14:38:13 gdha Exp $
######
# cd to $MKCDREC_DIR - wherever you have installed it (edit following line!!!)
cd /root/src/mkcdrec

# clean up first and make CD-ROM archives to disk (not to CDR) as nobody
# is around to put CDRs into the drive (however the ISOs are included into
# the normal backup procedure). On disaster we have first to burn the images
# to a CDR (which is not optimal but we can live with it).
# Tip: use scp to copy the freshly made images to a remote destination.
make clean
make CD-ROM
# clean up old archives older then 2 weeks
DIR=`grep CDREC_ISO_DIR= Config.sh | grep -v \#| cut -d= -f2`
find $DIR ! -ctime -15 -print -exec rm -f {} \;
