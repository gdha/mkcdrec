#!/bin/bash
#       Make CD-ROM Recovery (Mkcdrec)
#       Copyright (C) 2000-2008 by Gratien D'haese (IT3 Consultants)
#       Please read LICENSE in the source directory
#
# dialog script for doing our tar backup + start makeISO9660.sh script
# $Id: tar-it.sh,v 1.42 2008/07/09 13:35:52 gdha Exp $
. Config.sh 2>/dev/null
. ${SCRIPTS}/ansictrl.sh 2>/dev/null

#set -x
do_cleanup () {
echo >/dev/null
rm -f /tmp/LINUX_KERNEL /tmp/my_tty /tmp/modprobe.sh /tmp/cutstream.h
#rm -rf ${TMP_DIR}
}

Check_available_space () {
#^^^^^^^^^^^^^^^^^^^^^^^
# do a test on the available disk space we have
size_Kb=`df -kP ${1} | tail -1 | awk '{print $4}'`
return ${size_Kb}
}

Check_used_space () {
#^^^^^^^^^^^^^^^^^^
size_Kb=`df -kP ${1} | tail -1 | awk '{print $3}'`
return ${size_Kb}
}

Minus_excluded_dirs () {
###################
# do not take into account space of excluded dirs (with total space used)
minus_sum=0
echo "0" >${TMP_DIR}/minus_sum
Fs=${1}
OLDPW=`pwd`
cd ${Fs}
Dev_Fs=`df -kP .|tail -n 1| awk '{print $1}'`	# /dev/hdb5
cat ${TMP_DIR}/exclude_list |grep -v "/proc"|grep "${Fs}" | sort -u| { while read Line
do
 echo "${Line}" | grep "*" >/dev/null 2>&1
 if [ $? -eq 0 ]; then
  minus_sum=`cat ${TMP_DIR}/minus_sum`
  minus_Kb=`du -sk ${Line} | awk 'BEGIN {sum=0} {sum += $1} END {print sum}'`
  minus_sum=$((minus_sum+minus_Kb))
  echo $minus_sum > ${TMP_DIR}/minus_sum
 else
  cd $Line 2>/dev/null
  if [ $? -eq 0 ]; then
   minus_sum=`cat ${TMP_DIR}/minus_sum`
   Dev_Line=`df -kP .|tail -n 1| awk '{print $1}'`	# /dev/something
   if [ "${Dev_Line}" = "${Dev_Fs}" ]; then		# on same dev only
     minus_Kb=`du -skx . 2>/dev/null | awk '{print $1}'` # size in Kb
     if [ -z "${minus_Kb}" ]; then
	minus_Kb=0
     fi
     minus_sum=$((minus_sum+minus_Kb))
     echo $minus_sum > ${TMP_DIR}/minus_sum
   fi
  fi
 fi
done
}
cd ${OLDPW}
minus_Kb=`cat ${TMP_DIR}/minus_sum`
rm -f ${TMP_DIR}/minus_sum
echo "Filesystem $Fs minus_Kb $minus_Kb" >>  ${TMP_DIR}/FS_min.kb
return ${minus_Kb}
}

Make_zerofile () {
################
# to improof compression ratio fill up remaining space with zeroes
echo "Fill remaining space of ${Fs} with zeroes. Be patient" | tee -a ${LOG}
echo "The compress factor improves a lot with zeroes ;-))" | tee -a ${LOG}
echo "Notice: operation can take a while (but has no impact on Windows)" | tee -a ${LOG}
i=1
FS_writable=`mount|grep "${Fs}"| awk '{print $6}'|sed -e 's/[()]//g'`
if [ "${FS_writable}" = "ro" ]; then
   warn "${Fs} is a read-only DOS filesystem. I cannot compress it. Exclude it."
fi
while dd if=/dev/zero of=/${Fs}/zerofile.${i} bs=512k count=2k; do i=$((i+1)); done
#cat /dev/zero > ${Fs}/zerofile 2>/dev/null
rm -f ${Fs}/zerofile.*
echo "Now removed the zerofile(s) again..." | tee -a ${LOG}
echo "Unmount ${Fs} to have a consistent dump." | tee -a ${LOG}
cd ${MKCDREC_DIR}
umount ${Fs} 2>/dev/null
if [ $? -eq 1 ]; then
   echo "Could not un-mount ${Fs}. Continue with dump, but no guarantees!" | tee -a ${LOG}
fi
}

#############
# Main part #
#############

echo "-------------< Entering `basename $0` >-------------" | tee -a ${LOG}
# Do we have to make a backup?
#  YES: if DESTINATION_PATH or TAPE_DEV is NOT empty
#   NO: skip tar-it.sh
DO_BACKUP=0	# default: no backup

# pick up the MODE we're in
MODE=`cat ${TMP_DIR}/MODE`

# pick up the ENC_PROG_PASSWD
ENC_PROG_PASSWD="`cat ${TMP_DIR}/ENC_PROG_PASSWD 2>/dev/null`"

# if DESTINATION_PATH contains no path then skip backups.
DESTINATION_PATH=`cat ${TMP_DIR}/DESTINATION_PATH 2>/dev/null`
if [ ! -z "${DESTINATION_PATH}" ]; then
	DO_BACKUP=1
	Check_available_space ${DESTINATION_PATH}
	Total_available_space=${size_Kb}
fi
if [ -f ${TMP_DIR}/TAPE_DEV ]; then
	DO_BACKUP=1
	DESTINATION_PATH=`cat ${TMP_DIR}/TAPE_DEV`
	# try to find the capacity of the tape drive, still to be implemented
	# DDS1 60/90m: density code 0x13 (61000bpi)
	# DDS3 : density code 0x25 (unknown)
	# DDS1 (60m) with compressing is about 2.1 Gb, and 90m 4 Gb.
	# maybe have to define a variable in Config.sh?
	CAPACITY=2100000
	SetTapeDensity	# function sets tape density and CAPACITY
	Total_available_space=${CAPACITY}
fi

if  [ ${DO_BACKUP} -eq 1 ] && [ -f ${TMP_DIR}/To_Backup ]; then
# YES: do the backup if there is something to archive
# Calculate the space used vs. available before doing tar
Total_Kb=0

{ while read Line
do
	Fs=`echo ${Line} | awk '{print $2}'`
	Check_used_space ${Fs}
	Minus_excluded_dirs ${Fs}	# do not count excluded dirs
	Total_Kb=$((size_Kb-minus_Kb+Total_Kb))
#	echo "DEBUG: $Fs $Total_Kb $size_Kb $minus_Kb"
done
} < ${TMP_DIR}/To_Backup

# ${Total_available_space} is not yet filled in for tape!
# Assume 40% compression ratio (not very optimistic - 50% is more realistic)
if [ x$MODE = "xinteractive" ]; then
if [ $((Total_Kb*60/100)) -gt ${Total_available_space} ]; then
   if [ "${DESTINATION_PATH}" = "${ISOFS_DIR}" ]; then
	# CDROM
	warn "The calculated zipped backups ($((Total_Kb*60/100)) Kb) exceed the available space (${Total_available_space} Kb) on destination path ${DESTINATION_PATH}!
Will make multi volume media sets."
    else
	# tape/disk/NFS
	warn "The calculated zipped backups ($((Total_Kb*60/100)) Kb) exceed the available space (${Total_available_space} Kb) on destination path ${DESTINATION_PATH}!"
    fi
fi
fi # MODE

# select a compression extention (e.g. gz) according CMP_PROG
case ${CMP_PROG} in
     gzip) CmpExt=gz ;;
     bzip2) CmpExt=bz2 ;;
     compress) CmpExt=Z ;;
     lzop) CmpExt=lzo ;;
     *) CmpExt=z ;;
esac

if [ -z "${ENC_PROG_CIPHER}" ]; then
    EncExt=""
else
    EncExt=.${ENC_PROG_CIPHER}
fi

# time to check the options for the compress program
echo ${CMP_PROG_OPT} | grep c >/dev/null 2>&1
if [ $? -eq 1 ]; then
   # The "c" option is mandatory - add it to the list
   CMP_PROG_OPT=`echo ${CMP_PROG_OPT}`"c"
fi
echo ${CMP_PROG_OPT} | grep "-" >/dev/null 2>&1
if [ $? -eq 1 ]; then
   # option list starts with a -, missing? add it
   CMP_PROG_OPT="-"`echo ${CMP_PROG_OPT}`
fi

# tar -cf - . | bzip2 -9cv >file => bzip2: -c expects at least one filename.
# Solution is to remove "c" option with bzip2 (22/06/2001 - gdha)
if [ "${CMP_PROG}" = "bzip2" ]; then
   CMP_PROG_OPT=`echo ${CMP_PROG_OPT} | sed -e 's/c//'`
fi

#========== free the block size ==========
if [ -f ${TMP_DIR}/TAPE_DEV ]; then
   # archive to tape
   echo "${MT} -f ${TAPE_DEV} setblk 0" | tee -a ${LOG}
   ${MT} -f ${TAPE_DEV} setblk 0
fi

if [ -f ${TMP_DIR}/OBDR ]; then
	  # OBDR pre-backup steps
	  # 1) make empty header on tape
	  echo ${MT} -f ${TAPE_DEV} compression off | tee -a ${LOG}
	  ${MT} -f ${TAPE_DEV} compression off  # backups are gzip/bzip2
	  echo ${MT} -f ${TAPE_DEV} rewind | tee -a ${LOG}
	  ${MT} -f ${TAPE_DEV} rewind
	  echo ${MT} -f ${TAPE_DEV} setblk 512  | tee -a ${LOG}
	  ${MT} -f ${TAPE_DEV} setblk 512
	  echo dd if=/dev/zero of=${TAPE_DEV} bs=512 count=20  | tee -a ${LOG}
	  dd if=/dev/zero of=${TAPE_DEV} bs=512 count=20 2>/dev/null
	  echo "OBDR: Header written successfully" | tee -a ${LOG}

	  # 2) create ISO image and write (append) to tape
	  echo "OBDR: create ISO image and append to tape" | tee -a ${LOG}
	  echo ${MT} -f ${TAPE_DEV} setblk 2048  | tee -a ${LOG}
	  ${MT} -f ${TAPE_DEV} setblk 2048
	  . ${SCRIPTS}/makeISO9660.sh
	  if [ ! -f ${CDREC_ISO_DIR}/CDrec.iso ]; then
	     Fail "OBDR: Cannot find ISO image ${CDREC_ISO_DIR}/CDrec.iso"
	  fi
	  echo "OBDR: append CDrec.iso image to tape" | tee -a ${LOG}
	  echo dd if=${CDREC_ISO_DIR}/CDrec.iso of=${TAPE_DEV} bs=2048 | tee -a ${LOG}
	  dd if=${CDREC_ISO_DIR}/CDrec.iso of=${TAPE_DEV} bs=2048 2>/dev/null
	  echo "OBDR ISO Boot Image written" | tee -a ${LOG}

	  # 3) write (append) rd-image to tape
	  echo "${MT} -f ${TAPE_DEV} setblk 0" | tee -a ${LOG}
	  ${MT} -f ${TAPE_DEV} setblk 0	# free the block size
	  echo "OBDR: append the root-base image to tape" | tee -a ${LOG}
	  echo dd if=${ISOFS_DIR}/rd-base.img.bz2 of=${TAPE_DEV} | tee -a ${LOG}
	  dd if=${ISOFS_DIR}/rd-base.img.bz2 of=${TAPE_DEV}
	  # 4) append the backup
	  # continue...and process the To_Backup file
fi

# Disable SELinux enforcing mode if requested!
if [ "${Disable_SELinux_during_backup}" = "true" ]; then
   echo "Changing SElinux mode into permissive mode during backup" | tee -a ${LOG}
   cat /selinux/enforce >/tmp/selinux.mode
   echo "0" >/selinux/enforce
fi

# OK, we have a destination path and choose to continue (if warned) with backups
cat ${TMP_DIR}/To_Backup | { while read Line
do
   ParseDevice ${Line}
   # returns Dev and _Dev (all / became _)
   Fs=`echo ${Line} | awk '{print $2}'`
   _Fs=`echo ${Fs} | tr "/" "_"`
   FStype=`echo ${Line} | awk '{print $3}'`
   # from now on we gonna follow a dual track:
   # one for trusted FS (ext2, ext3, reiserfs,...) use tar, and
   # untrusted FS as msdos, fat, vfat, ntfs,... use dd
   echo "************************************************************"
   if [ -f ${TMP_DIR}/TAPE_DEV ]; then
    # archive to tape
    echo "Start backup of device /dev/${Dev} containing filesystem ${Fs} to tape" | tee -a ${LOG}
   else
    # archive to disk/CD
    case ${FStype} in
    ext2|ext3|auto|minix|reiserfs|xfs|jfs)
       echo "Start backup of device /dev/${Dev} containing filesystem ${Fs} as ${DESTINATION_PATH}/${_Dev}.${_Fs}.tar.${CmpExt}${EncExt}" | tee -a ${LOG}
     ;;
    *)
     echo "Start dumping (and compressing) device /dev/${Dev}"
     ;;
    esac
   fi
   DONE="N"	# a FLAG that is only usefull with multi volume sets
   # and indicates that a backup of FS is done or not.
   export DONE	# makeISO9660.sh will pick it up
   cd ${Fs}
   Build_exclude_list # call subroutine

   echo "** Started to backup ${Fs} at `date`" | tee -a ${LOG}


   if [ -f ${TMP_DIR}/TAPE_DEV ]; then
       DESTINATION=`cat ${TMP_DIR}/TAPE_DEV`
       # make sure it is norewinding (e.g. /dev/nst0)
       # erase the tape (mt understands HOST:FILE format)
       ${MT} -f ${DESTINATION} status
       if [ $? -eq 1 ]; then
	  warn "Please insert the recovery tape into the drive!"
       fi
       # is it a local or remote tape drive (or FILE)?
       grep ":" ${TMP_DIR}/TAPE_DEV > /dev/null
       if [ $? -eq 0 ]; then
	  # remote HOST:TAPE or HOST:FILE
	  RHOST=`cat ${TMP_DIR}/TAPE_DEV | cut -d":" -f 1`
	  DESTINATION=`cat ${TMP_DIR}/TAPE_DEV | cut -d":" -f 2` 
	  # do not set remote TapeDensity (yet) FIXME
       else
	  # local TAPE (norewinding)
	  REMOTE_COMMAND=""	#empty
	  RHOST=""		#empty
	  ${MT} -f ${DESTINATION} compression off  # backups are gzip/bzip2
       fi
       case ${FStype} in
       ext2|ext3|auto|minix|reiserfs|xfs|jfs)
         echo "The logging of tar is done in ${ISOFS_DIR}/${_Dev}.${_Fs}.log" | tee -a ${LOG}
         # we use "CMP_PROG" as compression mechanism to (remote) tape
         (${DEBUG} tar --create --verbose --same-owner --blocking-factor=512 \
	  --preserve-permissions --exclude-from=${TMP_DIR}/${_Fs}.exclude_list \
	  --one-file-system --file - . | ${CMP_PROG} ${CMP_PROG_OPT} | \
	  ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} | \
	  ${REMOTE_COMMAND} ${RHOST} \
	  dd of=${DESTINATION} obs=512 ) 1>> ${ISOFS_DIR}/${_Dev}.${_Fs}.log 2>&1
	;;
       *)	# all we do NOT know about
	Make_zerofile	# fill with zeroes (=Microsoft)
	echo "Start ${CMP_PROG} ${CMP_PROG_OPT} < /dev/${Dev} | dd of=${DESTINATION} bs=512" | tee -a ${LOG}
	(${CMP_PROG} ${CMP_PROG_OPT} < /dev/${Dev} | ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} | ${REMOTE_COMMAND} ${RHOST} dd of=${DESTINATION} bs=512) 1>> ${LOG} 2>&1
	echo "Filesystem ${Fs} archived successfully." | tee -a ${LOG}
        echo "Remounting ${Fs}" | tee -a ${LOG}
        mount -t ${FStype} /dev/${Dev} ${Fs}
        if [ $? -eq 0 ]; then
           echo "/dev/${Dev} successfully mounted on ${Fs}" | tee -a ${LOG}
        else
           echo "Could not mount /dev/${Dev} on ${Fs}" | tee -a ${LOG}
        fi
	;;
       esac
   else
       ########################
       # CDR/disk/NFS/SMB etc.#
       ########################
       
       # CAPACITY is the free space left on CDR before the tar (in Kb)
       UsedByIsofs=`(cd ${ISOFS_DIR};du -skx .|awk '{print $1}')`
       # For CD we do something special (cutstream)
       if [ -f ${TMP_DIR}/Backups_on_cd ]; then
			####################
          # in fact Total_available_space-UsedByIsofs should be used instead
          # of next line (drawback could be that Cd<650Mb) gdha: 17/2/2001
          CAPACITY=$((MAXCDSIZE-UsedByIsofs))
          echo "Capacity left on CD for images is ${CAPACITY} Kb." | tee -a ${LOG}
	  if [ ${CAPACITY} -lt 0 ]; then
		warn "The capacity left on CD is ${CAPACITY}, which is weird."    
	  fi
          CUTSTREAM="cutstream"	# cut stream to fit on CDR
          # CAPACITY and MAKE_ISO9660 are env. var. read by cutstream
          export CAPACITY
          MAKE_ISO9660="${SCRIPTS}/makeISO9660.sh" 
          export MAKE_ISO9660
          VOLNO_FILE="${TMP_DIR}/volno"	# volume nr (#Cds)
          export VOLNO_FILE
	  case ${FStype} in
	  ext2|ext3|auto|minix|reiserfs|xfs|jfs)
	  DESTINATION=${DESTINATION_PATH}/${_Dev}.${_Fs}.tar.${CmpExt}${EncExt}
	  export DESTINATION
	  echo "Busy with tar: do a \"tail -f ${TMP_DIR}/${_Dev}.${_Fs}.log\" to see progress"

          echo "tar --create --verbose --same-owner --blocking-factor=512 \
	  --preserve-permissions --exclude-from=${TMP_DIR}/${_Fs}.exclude_list \
	  --one-file-system --file - . | ${CMP_PROG} ${CMP_PROG_OPT} | \
	  ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} | \
	  ${CUTSTREAM}) 2>>${TMP_DIR}/${_Dev}.${_Fs}.log" | tee -a $LOG
          (${DEBUG} tar --create --verbose --same-owner --blocking-factor=512 \
	  --preserve-permissions --exclude-from=${TMP_DIR}/${_Fs}.exclude_list \
	  --one-file-system --file - . | ${CMP_PROG} ${CMP_PROG_OPT} | \
	  ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} | \
	  ${CUTSTREAM}) 2>>${TMP_DIR}/${_Dev}.${_Fs}.log
	  ;;
	  *)
	  DESTINATION=${DESTINATION_PATH}/${_Dev}.${_Fs}.dd.${CmpExt}${EncExt}
	  export DESTINATION
          Make_zerofile
          echo "Start ${CMP_PROG} ${CMP_PROG_OPT} < /dev/${Dev} | dd bs=512 | ${CUTSTREAM}" | tee -a ${LOG}
          (${CMP_PROG} ${CMP_PROG_OPT} < /dev/${Dev} | ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} | dd bs=512 | ${CUTSTREAM}) 1>> ${LOG} 2>&1
	  echo "Finished with /dev/${Dev} at `date`" | tee -a ${LOG}
	  echo "Remounting ${Fs}" | tee -a ${LOG}
	  mount -t ${FStype} /dev/${Dev} ${Fs}
	  if [ $? -eq 0 ]; then
	     echo "/dev/${Dev} successfully mounted on ${Fs}" | tee -a ${LOG}
	  else
	     echo "Could not mount /dev/${Dev} on ${Fs}" | tee -a ${LOG}
	  fi
	  ;;
	  esac
          DONE="Y"	# gz_ or gz extention (only multi vol CDs)
       else
	  ##### backups on disk / NFS
	  Check_available_space ${DESTINATION_PATH}
          CAPACITY=${size_Kb}
	  # possible check for enough disk space?
	  case ${FStype} in
	  ext2|ext3|auto|minix|reiserfs|xfs|jfs)
	  DESTINATION=${DESTINATION_PATH}/${_Dev}.${_Fs}.tar.${CmpExt}${EncExt}
	  echo "Busy with tar: do a \"tail -f ${ISOFS_DIR}/${_Dev}.${_Fs}.log\" to view progress"

	  (${DEBUG} tar --create --verbose --same-owner --blocking-factor=512 \
	  --preserve-permissions --exclude-from=${TMP_DIR}/${_Fs}.exclude_list \
	  --one-file-system --file - . | ${CMP_PROG} ${CMP_PROG_OPT} | \
	  ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} \
          > ${DESTINATION}) 2>>${ISOFS_DIR}/${_Dev}.${_Fs}.log 1>&2
	  ;;
	  *)
	  Make_zerofile
	  DESTINATION=${DESTINATION_PATH}/${_Dev}.${_Fs}.dd.${CmpExt}${EncExt}
	  echo "Start ${CMP_PROG} ${CMP_PROG_OPT} < /dev/${Dev} | dd of=${DESTINATION} bs=512" | tee -a ${LOG}
          (${CMP_PROG} ${CMP_PROG_OPT} < /dev/${Dev} | ${ENC_PROG} ${ENC_PROG_CIPHER} ${ENC_PROG_PASSWD} | dd of=${DESTINATION} bs=512) 1>> ${LOG} 2>&1
	  echo "Finished with /dev/${Dev} at `date`" | tee -a ${LOG}
          echo "Remounting ${Fs}" | tee -a ${LOG}
          mount -t ${FStype} /dev/${Dev} ${Fs}
          if [ $? -eq 0 ]; then
             echo "/dev/${Dev} successfully mounted on ${Fs}" | tee -a ${LOG}
          else
             echo "Could not mount /dev/${Dev} on ${Fs}" | tee -a ${LOG}
          fi
	  ;;
	  esac
       fi

       # mv log file if backup is finished to final destination + compress
       ls ${TMP_DIR}/${_Dev}.${_Fs}.log >/dev/null 2>&1
       if [ $? -eq 0 ]; then
	  if [ "${DONE}" = "Y" ]; then
		mv ${TMP_DIR}/${_Dev}.${_Fs}.log ${ISOFS_DIR}
	  fi
       fi
       ${DEBUG} gzip -fv9 ${ISOFS_DIR}/${_Dev}.${_Fs}.log 2>/dev/null
   fi # end of [ -f ${TMP_DIR}/TAPE_DEV ]
done # end of while of To_Backup
DONE="Y"
}
echo "*********************************************************" | tee -a ${LOG}
echo "** Backups ended at `date`" | tee -a ${LOG}
fi # of [ ${DO_BACKUP} -eq 1 ]

############ Next part will always be executed ############
cd ${MKCDREC_DIR}
# to reduce space of log-files on CD we gzip them too
ls ${ISOFS_DIR}/*.log 2>/dev/null
if [ $? -eq 0 ]; then
	gzip -fv9 ${ISOFS_DIR}/*.log
fi

# at this point we're sure that we're finished (no more backups)
# make a dummy FLAG file indicating this is the LAST CD!
touch ${ISOFS_DIR}/LAST_CD

# increase volno if multi vol CDs before the last makeisofs (for VOLID)
volno=`cat ${TMP_DIR}/volno`
if [ ${volno} -gt 0 ]; then	# increase with multi-vols (not for single!)
	volno=$((volno+1))
	echo ${volno} > ${TMP_DIR}/volno
fi

# backups or not, make an ISO9660 image
if [ ! -f ${TMP_DIR}/OBDR ]; then
   # OBDR was already done, others do it now
   . ${SCRIPTS}/makeISO9660.sh
fi

# Execute PostExec if needed before quitting
if [ x$MODE != xrescue ] && [ ! -z "${PostExec}" ]; then
   echo "Executing ${PostExec}" | tee -a ${LOG}
   ${PostExec}
fi

if [ "${Disable_SELinux_during_backup}" = "true" ]; then
   echo "Changing SELinux mode back into original setting" | tee -a ${LOG}
   cat /tmp/selinux.mode >/selinux/enforce
   rm -f /tmp/selinux.mode
fi

echo "-------------< Leaving `basename $0` >-------------" | tee -a ${LOG}

do_cleanup
# reset the screen if in interactive mode
tty -s
[ $? -eq 0 ] && reset && printat 23 1 "mkCDrec finished on `date`"
echo "mkCDrec finished on `date`" >> ${LOG}
