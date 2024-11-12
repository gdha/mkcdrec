#!/bin/bash
# $Id: mkmakeISO9660.sh,v 1.17 2007/11/13 14:38:13 gdha Exp $
. Config.sh 2>/dev/null
MKCDREC_DIR=`pwd`
SCRIPTS=${MKCDREC_DIR}/scripts

cp ${SCRIPTS}/makeISO9660.in ${SCRIPTS}/makeISO9660.sav	# save original in file
sed -e 's;%MKCDREC_DIR%;MKCDREC_DIR='${MKCDREC_DIR}';' < ${SCRIPTS}/makeISO9660.sav > ${SCRIPTS}/makeISO9660.in
# do the following to remove all comments - to not confuse sed command
#grep -v "^#" Config.sh | sed -e '/\#.*/s///' | tr -d '[ \t]'  >/tmp/Config.sh
cat /etc/mkcdrec.conf Config.sh 2>/dev/null | grep -v "^#" | sed -e '/\#.*/s///' | tr -d '[ \t]'  >/tmp/Config.sh

for var in LOG PATH BOOTARCH TMP_DIR ISOFS_DIR CDREC_ISO_DIR BURNCDR CDRECORD CDRECORDOPT WRITERSPEED MKISOFS BLANK_CDRW CD_EJECT DVD_Drive
do
  sed -e 's;%'${var}'%;'`grep ${var}= /tmp/Config.sh | head -n 1`';' < ${SCRIPTS}/makeISO9660.in > ${SCRIPTS}/makeISO9660.tmp
  mv ${SCRIPTS}/makeISO9660.tmp ${SCRIPTS}/makeISO9660.in 
done
# If in Config.sh a variable is defined twice we may not blindly do above trick
sed -e 's;%SCSIDEVICE%;SCSIDEVICE='${SCSIDEVICE}';' < ${SCRIPTS}/makeISO9660.in > ${SCRIPTS}/makeISO9660.tmp
mv ${SCRIPTS}/makeISO9660.tmp ${SCRIPTS}/makeISO9660.in
sed -e 's;%MAXCDSIZE%;MAXCDSIZE='${MAXCDSIZE}';' < ${SCRIPTS}/makeISO9660.in > ${SCRIPTS}/makeISO9660.tmp
mv ${SCRIPTS}/makeISO9660.tmp ${SCRIPTS}/makeISO9660.in
sed -e 's;%ISOVFY%;ISOVFY='${ISOVFY}';' < ${SCRIPTS}/makeISO9660.in > ${SCRIPTS}/makeISO9660.sh

chmod +x ${SCRIPTS}/makeISO9660.sh

# restore original in file
mv -f ${SCRIPTS}/makeISO9660.sav ${SCRIPTS}/makeISO9660.in

# remove /tmp/Config.sh helper script
rm -f /tmp/Config.sh
