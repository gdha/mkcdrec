#!/bin/bash
#======================================================
#       Make CD-ROM Recovery (mkCDrec)
#       Copyright (C) 2000-2010 by Gratien D'haese (IT3 Consultants)
#       Please read LICENSE in the source directory
#======================================================
# $Id: rd-base.sh,v 1.231 2011/01/14 09:09:53 gdha Exp $
# Version:
#---------
VERSION="`cat VERSION | cut -d_ -f 2`"
#

# Read in the Config.sh to set our variable parameters
#-----------------------------------------------------
# Normally only Config.sh should/may be changed by end-users
##############
cwd=`pwd`
. ./Config.sh 2>/dev/null
. ${SCRIPTS}/ansictrl.sh 2>/dev/null
##############
#set -x
# a safety check - check 2 basic variables (10/11/2000 gdha)
if [ -z "${basedir}" -o -z "${ROOTFS}" ]; then
        error 1 "**** Safety stop to avoid messing up your system ****"
fi

# Functions
#==========
#

# cleanup files left in an unfinished state
do_cleanup() {
#^^^^^^^^^^^
# remove the garbage
   rm -f rd-base.img*
   rm -f ${MKCDREC_DIR}/etc/rc.d/rc.network 2>&1 >/dev/null
}

Calculate_used_space () {
#^^^^^^^^^^^^^^^^^^^
# Input $1=$Dev, $2=$dsk
# output = space-in-use in Kb
local my_Dev=$1
local my_dsk=$2
local i
if [ -c /dev/.devfsd ]; then
   # a very strange trick to collect total amount of disk space in use
   my_dsk=`echo ${my_Dev} | cut -d"p" -f 1`part
fi
# If the Dev is a meta devices, then df output contains /dev/md0 etc..
echo ${my_Dev} | grep md >/dev/null 2>&1 && my_dsk=md
j=0
# make sure we grep both meta devices and dsk (in case not whole disk uses md)
for i in `df -kP | egrep "${my_dsk}|$2" | awk '{print $3}'`
do
  j=`expr ${j} + ${i}`
done
return $j
}

Check_available_space () {
#^^^^^^^^^^^^^^^^^^^^^^^
# do a test on the available disk space we have
size_Kb=`df -kP ${1} | tail -1 | awk '{print $4}'`
return ${size_Kb}
}

Show_mount_output () {
#################
# set a dummy Dev to please grep
Dev=/dev/dummy
Build_exclude_list
# we interested into $MKCDREC_TMP/exclude_list made by Build_exclude_list
# do not show excluded mount-points (gdha, 20/08/2001)
cat ${TMP_DIR}/exclude_list | sort -u > ${TMP_DIR}/exclude_list.candidates
> ${TMP_DIR}/exclude_list.MntPoints     # empty file
echo
# show the supported filesystems so far and exclude loopback (?) & floppy
if [ x${BACKUP_LOOP} = x1 ]; then
    SKIP="supermount|fd0|fd1|floppy|autofs|removable|mvfs"
else
    SKIP="loop=|supermount|fd0|fd1|floppy|autofs|removable|mvfs"
fi
# in next part we're concentrating on mount-points only which should be
# excluded or included in backup.
> ${TMP_DIR}/Backup.MntPoints   # make it empty
mount -v | egrep "ext2|ext3|ext4|auto|minix|reiserfs|fat|vfat|msdos|xfs|jfs|ntfs" | \
egrep -v "$SKIP" | sort -u | { while read Line
do
    MountPoint=`echo ${Line} | awk '{print $3}'`
    echo ${Line} >> ${TMP_DIR}/Backup.MntPoints
    exclude=0   # 0: include by default
    cat ${TMP_DIR}/exclude_list.candidates | grep -v proc | { while read Line2
    do
        # Line2 could be e.g. /mnt/* or /home
        # Therefore if Line2 contains a * we have to expand the list
        echo "${Line2}" | grep "*" >/dev/null 2>&1
        if [ $? -eq 0 ]; then   # expand list
         find `echo "${Line2}" | sed -e 's/\*//'` -type d -maxdepth 2 -mount 2>/dev/null | { while read Line3
         do
           #Line3 = expanded dir (max 2 deep to avoid looping)
           if [ "${Line3}" = "${MountPoint}" ]; then
                   # add MountPoint to list of excluded mount points
                   echo ${Line} >> ${TMP_DIR}/exclude_list.MntPoints
                   exclude=1
                   break
           fi
         done
         }
        else # no * in Line2 present
         if [ "${Line2}" = "${MountPoint}" ]; then
           # add MountPoint to list of excluded mount points
           echo ${Line} >> ${TMP_DIR}/exclude_list.MntPoints
           exclude=1
         fi
        fi
    done
    }
done
}
# at this point we have 2 important files:
# ${TMP_DIR}/exclude_list.MntPoints and ${TMP_DIR}/Backup.MntPoints
# where ${TMP_DIR}/Backup.MntPoints still contains the excluded MntPoints!
if [ -s ${TMP_DIR}/exclude_list.MntPoints ]; then
   # if there is something to exclude we do it here
   cat ${TMP_DIR}/Backup.MntPoints | grep -v "`cat ${TMP_DIR}/exclude_list.MntPoints`" > ${TMP_DIR}/Backup.MntPoints
fi

if [ x$MODE = "xinteractive" ]; then
   color yellow blue
   cat ${TMP_DIR}/Backup.MntPoints              # re-use this list later
   echo
   color white black
   warn "Only above listed filesystem(s) will be archived! OK?"
   echo
fi
# little cleanup here before leaving
rm -f ${TMP_DIR}/exclude_list.candidates
}

Tape_local_or_remote () {
#######################
echo ${tape_dev} | grep ":" > /dev/null
if [ $? -eq 0 ]; then
        # remote HOST:TAPE
        RHOST=`echo ${tape_dev} | cut -d":" -f 1`
        RESTORE=`echo ${tape_dev} | cut -d":" -f 2`
else
        RESTORE=${tape_dev}
        RHOST=""            # force it to be empty
        REMOTE_COMMAND=""   # force it to be empty
fi
}

Tar_dialog () {
#^^^^^^^^^^^

#
# dialog script for doing our tar backup
#

DESTINATION_PATH=""

printat 7 1 "${c_higreen}Enter your selection:${c_sel}\n"
print "\n ${c_hilight}1) Rescue CD-ROM only (no backups)${c_end}\n"
print " ${c_hilight}2) Rescue + backup into ${ISOFS_DIR} (to burn on CDROM)${c_end}\n"
print " ${c_hilight}3) Rescue + backup into ${ISOFS_DIR} (ISO filesystem only)${c_end}\n"
print " ${c_hilight}4) Enter another path (spare disk or NFS)${c_end}\n"
print " ${c_hilight}5) Enter (remote) tape device${c_end}\n"
print " ${c_hilight}6) Rescue + backup on USB key, enter USB device${c_end}\n"
print " ${c_hilight}7) Quit${c_end}\n\n"
selection 1-7
ANS=$?

case ${ANS} in
1) 
        print "No backup will be made - rescue only CD\n"
        MODE=rescue     # do process Mount-list, but do not show it
        Show_mount_output
        ;;
2)
        print "Backup will reside on CDR\n"
        DESTINATION_PATH=${ISOFS_DIR}
        Show_mount_output
        Check_available_space ${ISOFS_DIR}
        if [ $((size_Kb)) -lt 650000 ]; then
           warn "You have only ${size_Kb} available to make the ISO9660 filesystem"
        fi
        touch ${TMP_DIR}/Backups_on_cd  # a stupid FLAG file for tar-it.sh
        ;;
3)
	print "Backup in ISO filesystem\n"
	DESTINATION_PATH=${ISOFS_DIR}
	Show_mount_output
	Check_available_space ${ISOFS_DIR}
	if [ $((size_Kb)) -lt 650000 ]; then
	   warn "You have only ${size_Kb} available to make the ISO9660 filesystem"
	fi
	touch ${TMP_DIR}/Iso_only
	touch ${TMP_DIR}/Backups_on_cd	# a stupid FLAG file for tar-it.sh
	;;
4)
        Show_mount_output
        dttest=0
        while ( test ${dttest} -lt 1 )
        do
	clear
        print "\n\n${c_higreen}${PROJECT} ${VERSION} - Backing up your partitions${c_end}"
        printat  7 1 "${c_hiyellow}Enter the destination path, e.g. /foo${c_sel}\n"
        read dpath
        if [ -d "${dpath}" -o ! -z "${dpath}" ]; then
                dttest=1
        fi
        done
        DESTINATION_PATH=${dpath}
        ;;
5)      
        Show_mount_output
        if [ -z "${MT}" ]; then # MT gets defined in Config.sh
          error 1 "Could not find mt command - please install mt_st utilities first. Try at rpmfind.net"
        fi
        ${MT} --version | grep GNU >/dev/null
        if [ $? -eq 0 ]; then
           error 1 "GNU mt is braindead. Please use mt of mt_st instead."
        fi
        mttest=0
        tape_dev=${TAPE_DEV}
        Tape_local_or_remote    # local or remote tape drive?
        while ( test ${mttest} -lt 1 )
        do
        ${REMOTE_COMMAND} ${RHOST} ${MT} -f ${RESTORE} status >/tmp/tape_status 2>&1
        if [ $? -eq 1 ]; then   # tape_dev unknown
	   clear
           print "\n\n${c_higreen}${PROJECT} ${VERSION} - Backing up your partitions${c_end}"
           printat  7 1 "${c_hiyellow}Enter a no-rewinding tape device, e.g. ${TAPE_DEV}\n"
           printat 8 1 "Or, HOSTNAME:/dev/rmt/0mn is a remote tape drive.\n" 
           printat 9 1 "Check remote ~/.rhosts file for permissions.\n${c_sel}"
           echo -n "Tape Device? "
           read tape_dev
           Tape_local_or_remote
           $REMOTE_COMMAND ${RHOST} ${MT} -f ${RESTORE}  status >/tmp/tape_status 2>&1
           if [ $? -eq 0 ]; then
                echo ${tape_dev} > ${TMP_DIR}/TAPE_DEV
                mttest=1
           fi
        else
           echo ${tape_dev} > ${TMP_DIR}/TAPE_DEV
           mttest=1
        fi
        done
        # We have found a tape device, but before we continue
        # check if the tape is writable? WR_PROT means write protected
        grep -q WR_PROT /tmp/tape_status
        if [ $? -eq 0 ]; then
           # Tape is write protected. Force exit.
           Fail "Tape ${tape_dev} is \"write protected\". Correct it and restart."
        fi
        print "\n${c_hiyellow}Tape device ${tape_dev} accepted.${c_sel}\n"
        echo "Tape device ${tape_dev} accepted." >> ${LOG}
        rm -f /tmp/tape_status

        # Ask OBDR
        print "\n\n${c_higreen}${PROJECT} ${VERSION} - Backing up your partitions${c_end}"
        printat  7 1 "${c_hiyellow}One Button Disaster Recovery (OBDR) mode on ${TAPE_DEV}\n\n"
        printat 8 1 "Please make sure your setup qualifies for OBDR!\n" 
        printat 9 1 "Warning: mkCDrec will not test your hardware for OBDR\n\n${c_sel}"
        askyn N "OBDR ? "
        if [ $? -eq 1 ]; then
           # 0: is no OBDR; 1: yes make OBDR tape
           echo ${tape_dev} > ${TMP_DIR}/OBDR
        fi
        ;;
6)
        MODE=USB-KEY
        Show_mount_output
        dttest=0
        while ( test ${dttest} -lt 1 )
        do
        print "${c_higreen}${PROJECT} ${VERSION} - Backing up your partitions${c_end}"
        printat 21 1 "${c_hiyellow}Enter the device name of the USB key, e.g. /dev/sda1${c_end}\n"
        read ddev
        if [ -b ${ddev} ]; then
                dttest=1
        fi
        done
	USBKEY_DEV=${ddev}
        DESTINATION_PATH=${ISOFS_DIR}
	umount $USBKEY_DEV > /dev/null 2>&1
        Show_mount_output
	if ! mount -o shortname=winnt $USBKEY_DEV $DESTINATION_PATH >/dev/null 2>&1 ; then
             print "\nCannot mount the USB key, so I give up.\n"
	     exit 1
	fi
	empty=`find $DESTINATION_PATH -empty`
	if [ -z "$empty" -o "$empty" != "$DESTINATION_PATH" ] ; then
            print "${c_higreen}USB key is not empty, ${c_end}"
            askyn N "Clean USB key now ? "
            if [ $? -eq 0 ]; then
                exit 1
            fi
            rm -rf ${DESTINATION_PATH}/ > /dev/null 2>&1
	fi 
	# before continue check if USBKEY is FAT16 and bootable
	umount $USBKEY_DEV > /dev/null 2>&1
	Check_USBKEY_FileSystemType
	Check_USBKEY_bootable
	Check_USBKEY_MBR
	mount -o shortname=winnt $USBKEY_DEV $DESTINATION_PATH >/dev/null 2>&1
	;;
*)
        print "\nDo not know what to do, so I give up.\n"
        exit 1
        ;;
esac

# write our DESTINATION_PATH into a file (tar-it.sh will pick it up)
echo ${DESTINATION_PATH} > ${TMP_DIR}/DESTINATION_PATH
[ ! -z "${USBKEY_DEV}" ] && echo ${USBKEY_DEV} > ${TMP_DIR}/USBKEY_DEV

if [ -z "${ENC_PROG_CIPHER}" ]; then
        ENC_PROG_PASSWD=""
else
        print "${c_hiyellow}Enter your encryption password${c_sel}: "
        stty -echo > /dev/tty
        read passwd < /dev/tty
        print "\n${c_hiyellow}Enter it again${c_sel}: ${c_end}"
        read passwdverify < /dev/tty
        print "\n"
        stty echo > /dev/tty
        if [ ! "$passwd" = "$passwdverify" ]; then
                error 1 "Passwords entered were not consistent!"
        fi
        touch ${ENC_PROG_PASSWD_FILE}
        chmod 600 ${ENC_PROG_PASSWD_FILE}
        echo ${passwd} > ${ENC_PROG_PASSWD_FILE} # a sentence is ok
        ENC_PROG_PASSWD="-kfile ${ENC_PROG_PASSWD_FILE}"
        # key file will be used in tar-it.sh
        print "\nEncryption key accepted and written into ${ENC_PROG_PASSWD_FILE}.\n"
fi

# write our ENC_PROG_PASSWD into a file (tar-it.sh will pick it up)
touch ${TMP_DIR}/ENC_PROG_PASSWD
chmod 600 ${TMP_DIR}/ENC_PROG_PASSWD
echo "${ENC_PROG_PASSWD}" > ${TMP_DIR}/ENC_PROG_PASSWD

} # end of tar-dialog

Check_for_disk_labels () {
#^^^^^^^^^^^^^^^^^^^^^^^
# RedHat 7.x introduced the partitions labeling in /etc/fstab (eg. LABEL=/)
# Here we will check if the disks are labeled or not. And if so, we make a
# script in etc/recovery/mke2label.sh that will be executed at restore time
# after partitioning (added by G. D'haese 20/03/2001)
grep LABEL= /etc/fstab >/dev/null
if [ $? -eq 0 ]; then
  #LABEL=/      /       ext2    defaults        1       1
  #awk $1       $2      $3
  grep LABEL= /etc/fstab | { while read Line
  do
    FSType=`echo ${Line} | awk '{print $3}' | cut -d"," -f 1`
    FS=`echo ${Line} | awk '{print $2}'`
    LABEL=`echo ${Line} | awk '{print $1}' | cut -d"=" -f 2`
    DEV="`df -kP ${FS} | tail -n 1 | awk '{print $1}'`"
    if [ "${FSType}" = "ext2" ] || [ "${FSType}" = "ext3" ] || [ "${FSType}" = "ext4" ] || [ "${FSType}" = "auto" ]; then
        LABELPRG=e2label
    else
        LABELPRG=echo   # dummy statement as only ext2 labels exist currently
    fi
    if [ ! -z ${DEV} ]; then
     echo "${LABELPRG} ${DEV} ${LABEL}" >> ${ROOTFS}/etc/recovery/mke2label.sh
     echo_log "${LABELPRG} ${DEV} ${LABEL} (mke2label.sh)"
    fi
  done
  }
  chmod +x ${ROOTFS}/etc/recovery/mke2label.sh
fi
}

Check_for_swaplabel () {
###################
# Swap devices may have LABELs too - need to trace label if set
# Input: /dev/swap-dev
# Output: SWAPLABEL="" for no label, or "-L LABEL-swap" if label found
grep LABEL= /etc/fstab >/dev/null
if [ $? -eq 0 ]; then
   # LABEL=SWAP-dev  swap  swap  defaults 0  0
   grep LABEL= /etc/fstab | grep swap | { while read Line
   do
        LABEL=`echo ${Line} | awk '{print $1}' | cut -d"=" -f 2`
        dd if=$1 bs=1024 count=10 2>/dev/null | strings | grep -q ${LABEL}
        if [ $? -eq 0 ]; then
           # 0 means we found the LABEL in the swap_header_v1_1 area
           SWAPLABEL="-L ${LABEL}"
	   echo "${SWAPLABEL}" > /tmp/swaplabel
        fi
   done
   }
fi
}

create_parted_script_for_recovery () {
# AUTHOR: Guillaume RADDE ( Guillaume.Radde@Bull.net )
# DATE: 17/05/2004
# Modified by Gratien D'haese (new/old parted layout)
# DESCRIPTION:this function allows to create a script which partitions the disk with parted
SCRIPT_FILE=$1  # the file in which the script will be saved ( ex : parted.sda )
DEV=`echo $2 | sed -e 's;_;/;g'` # the device the scripts will format (cciss_c0d0 => cciss/c0d0)
DEVICE_PARTITION_FILE=$3         # the file containing the partition description of the device ( ex : partitions.sda)


echo_log "Check version /sbin/parted"
/sbin/parted -v | tee -a ${LOG}
grep -q ^Number ${DEVICE_PARTITION_FILE}
if [ $? -eq 0 ]; then
	echo_log "New type of parted layout"
	Parted_layout=NEW
else
	Parted_layout=OLD
	echo_log "Old type of parted layout"
fi


echo_log " begin to create the script to recover partitions with parted on scriptfile ${SCRIPT_FILE} for dev ${DEV}"

echo "[ -f /tmp/parted.${2}.done ] && exit" > ${SCRIPT_FILE}
echo "parted -i /dev/${DEV} mklabel gpt" >> ${SCRIPT_FILE}

NB_LINE=`cat ${DEVICE_PARTITION_FILE} | sed -e '/^$/d' | egrep -vi '^(Model|Disk|Minor|Partition|Sector|Number|Information)'| wc -l`

 let a=1
while [ $a -le $NB_LINE ]
do

        #we read each first line of the device partition file
        exp=${a}p
        line=`cat  ${DEVICE_PARTITION_FILE} | sed -e '/^$/d' | egrep -vi '^(Model|Disk|Minor|Partition|Sector|Number|Information)' | sed -n $exp`
	if [ "${Parted_layout}" = "NEW" ]; then
	# Number  Start   End     Size    File system  Name  Flags
        MINOR=`printf "${line}" |awk '{ print $1 }'`
        START=`printf "${line}" |awk '{ print $2 }'`
        END=`printf "${line}" |awk '{ print $3 }'`
	SIZE=`printf "${line}" |awk '{ print $4 }'`
        FILESYSTEM=`printf "${line}" |awk '{ print $5 }'`
        NAME_=`printf  "${line}" |awk 'BEGIN { FIELDWIDTHS = "8 8 8 8 13 9 10 20" } ;{ print $6 }'`
	NAME=`echo ${NAME_} | sed -e 's/ //g'` # remove blanks
        FLAGS=`printf "${line}" |awk 'BEGIN { FIELDWIDTHS = "8 8 8 8 13 9 10 20" } ;{ print $7 }'`
	echo "NAME=${NAME}" | tee -a ${LOG}
	echo "FLAGS=${FLAGS}" | tee -a ${LOG}
	else
	# OLD Parted_layout part
	# Minor    Start       End     Filesystem  Name                  Flags
        MINOR=`printf "${line}" |awk 'BEGIN { FIELDWIDTHS = "6 11 11 12 22 15" }
 ;{ print $1 }'`
        START=`printf "${line}" |awk 'BEGIN { FIELDWIDTHS = "6 11 11 12 22 15" }
 ;{ print $2 }'`
        END=`printf "${line}" |awk 'BEGIN { FIELDWIDTHS = "6 11 11 12 22 15" }
 ;{ print $3 }'`
        FILESYSTEM=`printf "${line}" |awk 'BEGIN { FIELDWIDTHS = "6 11 11 12 22 15" } ;{ print $4 }'`
        NAME_=`printf  "${line}" |awk 'BEGIN { FIELDWIDTHS = "6 11 11 12 22 15" } ;{ print $5 }'`
	NAME=`echo ${NAME_} | sed -e 's/ //g'` # remove blanks
        FLAGS=`printf "${line}" |awk 'BEGIN { FIELDWIDTHS = "6 11 11 12 22 15" } ;{ print $6 }'`

	fi
        #and we create the partition

        echo "parted /dev/${DEV} mkpart primary ${START} ${END}" >> ${SCRIPT_FILE}
        echo_log "entry -parted /dev/${DEV} mkpart primary ${START} ${END}- was created in /etc/recovery/partitions.${DEV}"

        # then we set its name if there is one

        if [ ! -z "${NAME}" ]; then
                echo "parted /dev/${DEV} name ${MINOR} ${NAME}" >> ${SCRIPT_FILE}
                echo_log "entry -parted /dev/${DEV} name ${MINOR} ${NAME}- was created in /etc/recovery/partitions.${DEV}"
        fi

        # and finally we set all the flags of the partition:

        FLAGS_=`echo ${FLAGS} | tr ',' ' '`      #(ex: FLAGS_="lvm lba boot" )
        for CURRENT_FLAG in ${FLAGS_}
        do
                echo "parted /dev/${DEV} set ${MINOR} ${CURRENT_FLAG} on" >> ${SCRIPT_FILE}
                echo_log "entry -parted /dev/${DEV} set ${MINOR} ${CURRENT_FLAG} on- was created in /etc/recovery/partitions.${DEV}"
        done
        let a=$[ $a + 1 ]
done

}

Save_diskinfo () {
#^^^^^^^^^^^^^^^
#
# Do we use swap?
echo_log "** Saving swap info to rootfs/etc/recovery **"
cat /proc/swaps | grep dev > /dev/null
if [ $? -eq 0 ];then
        echo_log "Swap space in use:"
        echo_log "`cat /proc/swaps`"
        for sw in `cat /proc/swaps | grep dev | awk '{print $1}'`
        do
          SWAPLABEL=""
	  echo "${SWAPLABEL}" > /tmp/swaplabel
          Check_for_swaplabel ${sw}     # function to trace LABEL for swap dev
	  # read back the swaplabel
	  SWAPLABEL="`cat /tmp/swaplabel`"
          echo "mkswap ${CHECK_BAD_BLOCKS} ${SWAPLABEL} -v1  ${sw}" >>${ROOTFS}/etc/recovery/mkswap.sh
          echo "swapon  ${sw}" >>${ROOTFS}/etc/recovery/mkswap.sh
        done
	rm -f /tmp/swaplabel
        echo "`free -k | tail -1 | awk '{print $2}'`" > ${ROOTFS}/etc/recovery/size.swap
        chmod +x ${ROOTFS}/etc/recovery/mkswap.sh
else
        echo_log "No swap space in use."
fi

# Save our disk partition layout of currently listed filesystems in /etc/fstab
# For the moment we only consider ext2 filesystems (would like to extend
# in the future with vfat, Reiserfs, LVM,...)

echo_log "** Saving our partition layout to roots/etc/recovery **"

# for not accidently doing a backup twice /it happened to me ;-/
rm -f ${TMP_DIR}/To_Backup

# EXT2 File systems mounted will be backup-ed (listed in /etc/fstab)
# Will use the output of 'mount' command, the exclude list in tar-it.sh
# will make sure that temp. fs are not backup-ed.
if [ -s ${TMP_DIR}/Backup.MntPoints ]; then
   # Save the partition layout per disk (hda/sda/md)
   cat ${TMP_DIR}/Backup.MntPoints | \
   { while read Line
   do
     # Line looks like '/dev/hda2 on / type ext2 (rw)'
     # FStype field is rather flexible under Debian 3, e.g. ext3,ext2
     # For recreation we need to capture ONLY the first one!
     FStype=`echo ${Line} | awk '{print $5}' | cut -d"," -f 1`  # ext2, ext3
     # check if FStype is a module && append it to modprobe.sh
     lsmod | grep -q ${FStype} && echo modprobe -q ${FStype} >>${ROOTFS}/etc/recovery/modprobe.sh
     # collect the mount options os $FS
     FSopt=`echo ${Line} | awk '{print $6}' | sed -e 's/(//' | sed -e 's/)//'`
     Device=`echo ${Line} | awk '{print $1}'`   # /dev/hda2
     FS=`echo ${Line} | awk '{print $3}'`       # /
     if [ -f ${Device} ]; then
         Major_nr="-1"
     else
         Major_nr=`ls -Ll ${Device} | awk '{print $5}' | cut -d"," -f 1`
     fi
     echo $Major_nr
     echo_log "Found device ${Device} mounted as ${FS} with type ${FStype}"
     case ${Major_nr} in
        # see linux/Documentation/devices.txt file for major numbers
        3|22|33|34|45|47|56|57|80|81|82|83|84|85|86|87|88|89|90) # IDE disks
          hd_sd_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        8|65|66|67|68|69|70|71|232) # Scsi disks
          hd_sd_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
	202) # Xen Virtual Devices
	  hd_sd_disk_types ${Device} ${FS} ${FStype} ${FSopt}
	  ;;
	147) # drbd device (Linux HA cluster)
	  hd_sd_disk_types ${Device} ${FS} ${FStype} ${FSopt}
	  ;;
        9)  # Software RAID md device
          software_raid ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        72|73|74)  # Compaq's SMART2 Intelligent Disk Array (/dev/ida[012]/)
          ida_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        104|105|106) # Compaq hardware raid controller (CCISS) /dev/cciss/c0d0p1
          ida_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        48|49|50|51|52|53|54|55) # Mylex DAC960 RAID (/dev/rd/c0d0p1)
          ida_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        114) # Promise FastTrack TX2 IDE RAID (dev/ataraid/d0p1)
          ida_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        117) # EVMS (/dev/evms/sda3)
          ida_disk_types ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        58|253|254) # LVM
          lvm ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        252) # EVMS 2.x / DeviceMapper or could also be LVM
	  if [ ! -f /etc/lvmtab -a ! -f /etc/lvm/lvm.conf ];
	  then
	    # EVMS 2.x
            ida_disk_types ${Device} ${FS} ${FStype} ${FSopt}
	  else
	    # LVM
	    lvm  ${Device} ${FS} ${FStype} ${FSopt}
	  fi
          ;;
        -1) # loopback
          loopback ${Device} ${FS} ${FStype} ${FSopt}
          ;;
        *)  # Oops, still an unsupported device (needs help ;-)
          error 1 "Device ${Device} is not yet supported by mkCDrec!
Please mail me the details of ${Device} with major nr ${Major_nr}"
          ;;
     esac
     done
     }
     chmod +x ${ROOTFS}/etc/recovery/sfdisk.* 2>/dev/null
     chmod +x ${ROOTFS}/etc/recovery/parted.* 2>/dev/null
     chmod +x ${ROOTFS}/etc/recovery/mkfs.*
     if [ -d ${ROOTFS}/etc/recovery/md ]; then
        # create a buildraid script which does it all in one go
        chmod +x ${ROOTFS}/etc/recovery/md/sfdisk.* 2>/dev/null
        chmod +x ${ROOTFS}/etc/recovery/md/parted.* 2>/dev/null
        chmod +x ${ROOTFS}/etc/recovery/md/mkfs.*
        # check if the raidtools are available or not:
        which lsraid >/dev/null 2>&1
        if [ $? -eq 1 ]; then
           # no raidtools found; we have mdadm instead
           Buildraid_with_mdadm
           Remake_To_Restore_md_for_mdadm
        else  # lsraid
           Buildraid_with_raidtools
        fi # lsraid
     fi

     if [ -d ${ROOTFS}/etc/recovery/lvm ]; then
        # found lvm - need to make a global lvm build script

#we use parted for ia64 and sfdisk for ia32

if [ x${BOOTARCH} = xia64 ] || [ x${BOOTARCH} = xsparc ]; then
        PARTITIONING_TOOL=parted
else
        PARTITIONING_TOOL=sfdisk
fi


cat <<EOF > ${ROOTFS}/etc/recovery/lvm/buildLVM.sh
###### buildLVM script ######
echo "
Logical Volume Manager Script
=============================
"
echo "If you run this script you will recreate from SCRATCH all LVM disks!
Is this what you really want?

Press q to quit or any other key to continue"
read an
if [ "\$an" = "q" ]; then
   exit 1
fi
mkmdnod
modprobe -q dm_mod 2>/dev/null
modprobe -q dm-mod  2>/dev/null
modprobe -q lvm-mod 2>/dev/null
vgscan  # will recreate an empty /etc/lvmtab file and /etc/lvmtab.d directory
rc=0
# Check if partitions.md has a size greater then zero
[ -f /etc/recovery/lvm/partitions.md ] && [ ! -s /etc/recovery/lvm/partitions.md ] && mv -f /etc/recovery/lvm/${PARTITIONING_TOOL}.md /etc/recovery/lvm/.${PARTITIONING_TOOL}.md

echo "Doing the ${PARTITIONING_TOOL} part..."
for s in \`ls /etc/recovery/lvm/${PARTITIONING_TOOL}.*\`
do
echo \$s
\$s
if [ \$rc -ne 0 ]; then
  echo "Something went wrong with \$s ?"
  exit 1
fi
done
udevstart # maybe it will clear the /dev first - FIXME
makedev   # to be sure, but what about lvm dev?
rc=0
# rm old /dev/vg_names/ directories, otherwise we cannot rebuild them
echo "Cleanup obsolete /dev/VolumeGroup directories - are rebuild anyway."

for s in \`ls /etc/recovery/lvm/mkfs.*\`
do
  VG=\`echo \$s | cut -d. -f2 |sed -e 's/%137/_/g'\`
  echo rm -r /dev/\$VG
  rm -r /dev/\$VG
done

EOF

vgdisplay | grep "VG Name" | awk '{print $3}' | { while read VG
do
  echo "rm -r /dev/$VG" >> ${ROOTFS}/etc/recovery/lvm/buildLVM.sh
done
}
                                                                                
cat <<EOF >> ${ROOTFS}/etc/recovery/lvm/buildLVM.sh

echo "Recreate /dev/mapper/control"
mkmdnod
#mkdir  /dev/mapper
#mknod  /dev/mapper/control c 10 63

echo "Doing the pvcreate part..."
for s in \`ls /etc/recovery/lvm/pvcreate.*\`
do
  echo \$s
  \$s
  if [ \$rc -ne 0 ]; then
    echo "Something went wrong with \$s :"
    case \$rc in
        1) echo "no physical volume on command line" ;;
        2) echo "error removing existing lvmtab entry for new physical volume" ;;
        3) echo "error setting up physical volume structure" ;;
        4) echo "error writing physical volume structure to disk" ;;
        5) echo "wrong partition type identifier" ;;
        6) echo "error physical volume name" ;;
        7) echo "error getting size of physical volume" ;;
        95) echo "driver/module not in kernel" ;;
        96) echo "invalid I/O protocol version" ;;
        97) echo "error locking logical volume manager" ;;
        98) echo "invalid lvmtab (run vgscan(8))" ;;
        99) echo "invalid command line" ;;
    esac
    exit 1
  fi
done
rc=0
echo "Doing the vgcreate part..."
/etc/recovery/lvm/vgcreate.sh
if [ \$rc -ne 0 ]; then
  echo "Something went wrong with \$s :"
  case \$rc in
   1) echo "no volume group and physical volume names on command line" ;;
   2) echo "no physical volume names on command line" ;;
   3) echo "invalid volume group name" ;;
   4) echo "error checking existence of volume group" ;;
   5) echo "maximum number of volume groups exceeded" ;;
   6) echo "error reading physical volume(s)" ;;
   7) echo "invalid physical volume name" ;;
   8) echo "error getting physical volume size" ;;
   9) echo "no new physical volume" ;;
   10) echo "physical volume occurs multiple times on command line" ;;
   11) echo "memory reallocation error" ;;
   12) echo "no valid physical volumes on command line" ;;
   13) echo "some invalid physical volumes on command line" ;;
   14) echo "physical volume is too small" ;;
   15) echo "error setting up VGDA" ;;
   16) echo "error writing VGDA to physical volumes" ;;
   17) echo "error creating VGDA in kernel" ;;
   18) echo "error inserting volume group into lvmtab" ;;
   19) echo "error doing backup of VGDA" ;;
   20) echo "error writing VGDA to lvmtab" ;;
   21) echo "volume group directory already exists in /dev" ;;
   95) echo "driver/module not in kernel" ;;
   96) echo "invalid I/O protocol version" ;;
   97) echo "error locking logical volume manager" ;;
   98) echo "invalid lvmtab (run vgscan(8))" ;;
   99) echo "invalid command line" ;;
  esac
  exit 1
fi
echo "Activate the volume group(s)."
vgchange -a y
echo "Doing the lvcreate part..."
/etc/recovery/lvm/lvcreate.sh
if [ \$rc -ne 0 ]; then
  echo "Something went wrong with \$s :"
  case \$rc in
       1) echo "  invalid volume group name" ;;
       2) echo "  error checking existence of volume group" ;;
       3) echo "  volume group inactive" ;;
       4) echo "  invalid logical volume name" ;;
       5) echo "  error getting status of logical volume" ;;
       6) echo "  error checking existence of logical volume" ;;
       7) echo "  invalid physical volume name" ;;
       8) echo "  invalid number of physical volumes" ;;
       9) echo "  invalid number of stripes" ;;
       10) echo " invalid stripe size" ;;
       11) echo " error getting status of volume group" ;;
       12) echo " invalid logical volume size" ;;
       13) echo " invalid number of free physical extents" ;;
       14) echo " more stripes than physical volumes requested" ;;
       15) echo " error reading VGDA" ;;
       16) echo " requested physical volume not in volume group" ;;
       17) echo " error reading physical volume" ;;
       18) echo " maximum number of logical volumes exceeded" ;;
       19) echo " not enoungh space available to create logical volume" ;;
       20) echo " error setting up VGDA for logical volume creation" ;;
       21) echo " error creating VGDA for logical volume in kernel" ;;
       22) echo " error writing VGDA to physical volume(s)" ;;
       23) echo " error creating device special for logical volume" ;;
       24) echo " error opening logical volume" ;;
       25) echo " error writing to logical volume" ;;
       26) echo " invalid read ahead sector count" ;;
       27) echo " no free logical volume manager block specials available" ;;
       28) echo " invalid snapshot logical volume name" ;;
       29) echo " error setting up snapshot copy on write exception table" ;;
       30) echo " error initializing snapshot copy on write exception table on disk" ;;
       31) echo " error getting status of logical volume from kernel" ;;
       32) echo " snapshot already exists" ;;
       95) echo " driver/module not in kernel" ;;
       96) echo " invalid I/O protocol version" ;;
       97) echo " error locking logical volume manager" ;;
       98) echo " invalid lvmtab (run vgscan(8))" ;;
       99) echo " invalid command line" ;;
  esac
  exit 1
fi
echo "Doing the mkfs part..."
for s in \`ls /etc/recovery/lvm/mkfs.*\`
do
  echo \$s
  \$s
  if [ \$rc -ne 0 ]; then
    echo "Something went wrong with \$s ?"
    exit 1
  fi
done
echo "Doing a vgcfgbackup..."
vgcfgbackup
#echo "Activate the volume group(s)."
#vgchange -a y

# probably best to do a "chroot /mnt/localfs vgcfgrestore" afterwards
# but first copy /etc/lvmconf/VG.conf to /mnt/localfs/etc/lvmconf
# these 2 steps have to be done just before lilo/grub config I guess
echo "Finished with buildLVM.sh script"
EOF
chmod +x ${ROOTFS}/etc/recovery/lvm/buildLVM.sh
echo_log "Finished with LVM script building"
fi # end of if LVM

else
     echo "No devices found to restore later - give me a reason..." | tee -a $
     mount >> ${LOG}
     ${SCRIPTS}/test.sh -v >> ${LOG}
fi # end of if ext2|ext3...
}


Buildraid_common_part1 () {
######################
        cat <<EOF > ${ROOTFS}/etc/recovery/md/buildraid.sh
###### buildraid script ######
rc=0
for s in \`ls /etc/recovery/md/sfdisk.*\`
do
\$s
if [ \$rc -ne 0 ]; then
  echo "Something went wrong with \$s ?"
  exit 1
fi
done
rc=0
EOF
}


Buildraid_common_part3 () {
######################
        cat <<EOF >>${ROOTFS}/etc/recovery/md/buildraid.sh
rc=0
for m in \`ls /etc/recovery/md/mkfs.*\`
do
\$m
if [ \$rc -ne 0 ]; then
  echo "Something went wrong with \$m ?"
  exit 1
fi
done
echo "Finished with the buildraid script"
EOF
        chmod +x ${ROOTFS}/etc/recovery/md/buildraid.sh
        echo_log "Finished with Software RAID script building"
}

Buildraid_with_raidtools () {
########################
Buildraid_common_part1  # sfdisk part
#&&& xar BEGIN
#&&& clean up ${ROOTFS}/etc/raidtab: remove "chunk-size 0" lines that
#&&& will prevent building RAID1 arrays
cp ${ROOTFS}/etc/recovery/raidtab ${ROOTFS}/etc/recovery/raidtab.tmp
cat ${ROOTFS}/etc/recovery/raidtab.tmp | \
    grep  -v -E '^[[:space:]]+chunk-size[[:space:]]+0$' \
    > ${ROOTFS}/etc/recovery/raidtab
#&&& xar END
# mkraid - part 2
grep '^raiddev' ${ROOTFS}/etc/recovery/raidtab | { while read md
        do
          cat <<EOF >>${ROOTFS}/etc/recovery/md/buildraid.sh
mkraid --really-force `echo ${md}|awk '{print $2}'`
if [ \$? -ne 0 ]; then
  echo "mkraid failed on device ${md}"
  echo "Check the Software RAID howto on how to proceed"
  exit 1
fi
EOF
        done
        } # end of while

Buildraid_common_part3  # mkfs part
} # end of Buildraid_with_raidtools

Buildraid_with_mdadm () {
####################
Buildraid_common_part1  # sfdisk part
# part 2: mdadm --create stuff (script made by Analyse_mdadm_conf routine)
echo "/etc/recovery/md/mdadm-create.sh" >>${ROOTFS}/etc/recovery/md/buildraid.sh
Buildraid_common_part3  # mkfs part
}

Remake_To_Restore_md_for_mdadm () {
##############################
# with mdadm for some unclear reason the md/To_Restore.md needed to clone
# a meta-device to an IDE/SCSI dev was screwed up. Remake it from scratch
> ${ROOTFS}/etc/recovery/md/To_Restore.md       # clear the file
cat ${TMP_DIR}/To_Backup | { while read Line
 do
   # Line = /dev/md0        /boot   ext3    rw
   # replace /dev/md0 with 2 line /dev/hda1 and /dev/hdb1
   MDdev=`echo ${Line} | awk '{print $1}' | cut -d"/" -f 3` # md0
   RestOfLine=`echo ${Line} | awk '{print $2, $3, $4}'`
   for dk in `cat /proc/mdstat | grep ${MDdev} | awk '{print $5, $6, $7, $8}'`
        do
          dsk=`echo ${dk} | cut -d"[" -f1`      # hda1
          echo "/dev/${dsk} ${RestOfLine}" >>${ROOTFS}/etc/recovery/md/To_Restore.md
        done
 done
 } # end of while
}

Check_fixed () {
#^^^^^^^^^^
# check whether a partition is in the list of fixed-size partitions
# first argument is partition name, second is disk name
  for i in ${FIXED_SIZE}
  do
    if [ "$i" = "$1" ]; then
      echo "$i" >> ${ROOTFS}/etc/recovery/fixed.$2
    fi
  done
}

loopback () {
###
echo_log "Start spitting out loopback configuration..."
Device=$1       # e.g. /home/user.img
FS=$2
FStype=$3
FSopt=$4
if [ "${FS}" = "${DESTINATION_PATH}" ]; then
   return       # do not backup our mounted DR disk!
fi
# FIXME: handle recreating encrypted loopback filesystems and things like that.
echo -e "$Device\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
}

lvm () {
###
echo_log "Start spitting out the LVM configuration..."
Device=$1       # e.g. /dev/vg_sd/lvol1
FS=$2
FStype=$3
FSopt=$4
if [ "${FS}" = "${DESTINATION_PATH}" ]; then
   return       # do not backup our mounted DR disk!
fi

# analyse system on LVM structure
if [ ! -f /etc/lvmtab -a ! -f /etc/lvm/lvm.conf ]; then
   Fail "LVM filesystem detected but no /etc/lvmtab or /etc/lvm/lvm.conf file found?"
fi
mkdir -p ${ROOTFS}/etc/recovery/lvm
echo_log "Run vgcfgbackup to have recent /etc/lvm[conf]/vg* backups"
vgcfgbackup >>${LOG} 2>&1
echo_log "Save LVM configuration files in ${ROOTFS}/etc/recovery/lvm"
# Determine if this is LVM1 or 2:
LVMversion=1
[ -c /dev/mapper/control ] && LVMversion=2
#[ -f /sbin/lvm.static ] && LVMversion=2

if [ ${LVMversion} -eq 1 ]; then
   lvm1 $1 $2 $3 $4
else
   lvm2 $1 $2 $3 $4
fi

# remove duplicate lines in [vg|lv]create.sh
cat ${ROOTFS}/etc/recovery/lvm/vgcreate.sh | sort -u >/tmp/vgcreate.sh
mv /tmp/vgcreate.sh ${ROOTFS}/etc/recovery/lvm/vgcreate.sh
echo "Created vgcreate.sh script:" | tee -a ${LOG}
cat ${ROOTFS}/etc/recovery/lvm/vgcreate.sh | tee -a ${LOG}
cat ${ROOTFS}/etc/recovery/lvm/lvcreate.sh | sort -u >/tmp/lvcreate.sh
mv /tmp/lvcreate.sh ${ROOTFS}/etc/recovery/lvm/lvcreate.sh
echo "Created lvcreate.sh script:" | tee -a ${LOG}
cat ${ROOTFS}/etc/recovery/lvm/lvcreate.sh | tee -a ${LOG}

rm -f /tmp/VG /tmp/PVs_VG
rm -f /tmp/LV /tmp/PVs_LV

# step 3: mkfs part per Lvol
# EXTRA_OPTS var. in case some fs needs special treatment
EXTRA_OPTS=""
if [ "${FStype}" = "reiserfs" -a "${kernel_minor_nr}" = "2" ]; then
   # Reiserfs on 2.2.* based kernels needs the -v 1 flag 
   EXTRA_OPTS="-v 1"
fi

if [ "${FStype}" = "reiserfs" -o "${FStype}" = "xfs" ]; then
   CHECK_BAD_BLOCKS=""  # reiserfs and xfs do not use ext2 concepts.
fi

if [ "${FStype}" = "xfs" ]; then
   EXTRA_OPTS="-f" # xfs needs the force option for mkfs to overwrite an existing part
fi
if [ "${FStype}" = "ext3" ] -o [ "${FStype}" = "ext4" ]; then
   JOURNAL="-j"
   CHECK_BAD_BLOCKS=""
else
   JOURNAL=""
fi

if [ "${FStype}" = "jfs" ]; then
   CHECK_BAD_BLOCKS=""
   JOURNAL="-f -L:jfs_`echo ${Device}|cut -d"/" -f3-`" # jfs_vg_sd/lvol1
fi

# generate extention for mkfs.* so it is conform our restore policy, e.g.
# sda, hda, md, vg00
VGdev=`echo ${Device}|cut -d"/" -f3` # /dev/vg_sd/lvol1 -> vg_sd
# check if VGdev contains an underscore - replace by %137 (ascii value)
VGdev=`echo ${VGdev}|sed -e 's/_/%137/g'`        # vg_sd -> vg%137sd
echo "modprobe ${FStype} 2>/dev/null" >> ${ROOTFS}/etc/recovery/lvm/mkfs.${VGdev}
echo "mkfs -t ${FStype} ${JOURNAL} ${EXTRA_OPTS} ${CHECK_BAD_BLOCKS} ${Device}" >> ${ROOTFS}/etc/recovery/lvm/mkfs.${VGdev}
echo "rc=\$((rc+\$?))" >> ${ROOTFS}/etc/recovery/lvm/mkfs.${VGdev}
chmod +x ${ROOTFS}/etc/recovery/lvm/*.sh
chmod +x ${ROOTFS}/etc/recovery/lvm/sfdisk.* 2>/dev/null
chmod +x ${ROOTFS}/etc/recovery/lvm/parted.* 2>/dev/null
chmod +x ${ROOTFS}/etc/recovery/lvm/pvcreate.*
chmod +x ${ROOTFS}/etc/recovery/lvm/mkfs.*

# make an entry in To_Backup
echo -e "${Device}\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
} # end of lvm


lvm1 () {
####
echo_log "Digging into the LVM1 configuration..."
Device=$1       # e.g. /dev/vg_sd/lvol1
FS=$2
FStype=$3
FSopt=$4

# LVM v1
cp /etc/lvmtab ${ROOTFS}/etc/recovery/lvm
cp -dpR /etc/lvmtab.d ${ROOTFS}/etc/recovery/lvm
cp -dpR /etc/lvmconf ${ROOTFS}/etc/recovery/lvm
vgdisplay -v >${ROOTFS}/etc/recovery/lvm/vgdisplay_v.txt

# here we need to analyse our LVM layout so we can rebuild it from scratch
# if necessary...
# step 1: collect all PVs first to get sfdisk info from it
vgdisplay -v | grep "PV Name" | awk '{print $4}' | { while read Line
do
  # Line = /dev/sda1
  ParseDevice ${Line}   # returns Dev=sda1 and _Dev=sda1
  ParseDisk ${Dev}      # returns dsk=sda and _dsk=sda

  if [ -f ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk} ]; then
        # if partitions.${_dsk} exists we have the info already
        return
  fi

  if [ x${BOOTARCH} = xia64 ] || [ x${BOOTARCH} = xsparc ]; then
        # for ia64 we use parted
        echo_log "Busy analyzing disk /dev/${dsk} with parted..."
        parted -s /dev/${dsk} print > ${ROOTFS}/etc/recovery/partitions.${_dsk}

        # move partitions file to lvm directory if no ide/sd is in use
        if [ -f ${ROOTFS}/etc/recovery/geometry.${_dsk} ]; then
                cp ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        else
                mv ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        fi
        create_parted_script_for_recovery ${ROOTFS}/etc/recovery/lvm/parted.${_dsk}   ${_dsk} ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}

        echo "rc=\$((rc+\$?))" >>${ROOTFS}/etc/recovery/lvm/parted.${_dsk}
        echo "touch /tmp/parted.${_dsk}.done" >>${ROOTFS}/etc/recovery/lvm/parted.${_dsk}

   else
        #for ia32 we use sfdisk
        echo_log "Busy analyzing disk /dev/${dsk} with sfdisk..."
        sfdisk -d /dev/${dsk} > ${ROOTFS}/etc/recovery/partitions.${_dsk}
        Check_partition_file
        # move partitions file to lvm directory if no ide/sd is in use
         if [ -f ${ROOTFS}/etc/recovery/geometry.${_dsk} ]; then
                cp ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        else
                mv ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        fi
        echo "sfdisk --force /dev/${dsk} < /etc/recovery/lvm/partitions.${_dsk}" > \
        ${ROOTFS}/etc/recovery/lvm/sfdisk.${_dsk}
        echo "rc=\$((rc+\$?))" >>${ROOTFS}/etc/recovery/lvm/sfdisk.${_dsk}
        echo "touch /tmp/sfdisk.${_dsk}.done" >>${ROOTFS}/etc/recovery/lvm/sfdisk.${_dsk}

fi
  # save the disk geometry too (at restore time compare disks)
  sfdisk -g /dev/${dsk} > ${ROOTFS}/etc/recovery/lvm/geometry.${_dsk}
  # save the disk size too
  sfdisk -s /dev/${dsk} > ${ROOTFS}/etc/recovery/lvm/size.${_dsk}
  Is_dsk_bootable ${dsk} ${_dsk}
  # calculate used disk space/disk. FIXME: no much sense on LVM
  echo 100 > ${ROOTFS}/etc/recovery/lvm/used.${_dsk}   # dummy nr.

  # Line = /dev/sda1
  # we can make the pvcreate-script on the fly (force per disk)
  echo "pvcreate -y -ff ${Line}" >> ${ROOTFS}/etc/recovery/lvm/pvcreate.${_dsk}
done
}
# step 2: collect PVs per VG, LVs per VG and PVs per LV
strings -1 /etc/lvmtab | { while read VG
do
  # make the vgcreate.sh script
  PVs_VG=""
  vgdisplay -v ${VG} | grep "PV Name" | awk '{print $4}' | { while read Line
  do
    # collect PVs per VG
    PVs_VG="${PVs_VG} ${Line} "
    echo ${PVs_VG} > /tmp/PVs_VG        # needed for out while loop
  done
  } # end of while of vgdisplay -v ${VG} | grep "PV Name"
  vgdisplay ${VG} > /tmp/VG
  PVs_VG=`cat /tmp/PVs_VG`
  Max_LV=`grep -i "MAX LV  " /tmp/VG | awk '{print $3}'`        # -l option
  Max_PV=`grep -i "MAX PV" /tmp/VG | awk '{print $3}'`          # -p option
  PE_Size=`grep -i "PE Size" /tmp/VG | awk '{print $3$4}'|sed -e 's/B//'` # 32M
  PE_Size_Suffix=`echo ${PE_Size} | sed -e 's/[0-9]//g' -e 's/.//'` #M or K
  PE_Size=`echo ${PE_Size} |cut -d. -f1 | cut -d, -f1 | sed -e 's/[a-zA-Z]//'` # no suffix
  echo "vgcreate -A n -v -l ${Max_LV} -p ${Max_PV} -s ${PE_Size}${PE_Size_Suffix} ${VG} ${PVs_VG}" >> ${ROOTFS}/etc/recovery/lvm/vgcreate.sh
  # make lvcreate.sh script
  vgdisplay -v ${VG} | grep "LV Name" | awk '{print $3}' | { while read Lvol
  do
    # Lvol = /dev/vg_sd/lvol1
    # collect PVs per Lvol
    PVs_LV=""
    lvdisplay -v ${Lvol} | awk '{print $1}' | grep "^/dev" | { while read Line
    do
      # device per Lvol, e.g. /dev/sda1
      PVs_LV="${PVs_LV} ${Line}"
      echo ${PVs_LV} > /tmp/PVs_LV
    done
    } # end of while lvdisplay -v ${Lvol} 

    lvdisplay ${Lvol} > /tmp/LV
    PVs_LV=`cat /tmp/PVs_LV`
    LV_name=`echo ${Lvol} | cut -d"/" -f4-`             # lvol1
    VG_name=`grep -i  "VG Name" /tmp/LV | awk '{print $3}'` # vg_sd
    LE=`grep -i  "Current" /tmp/LV | awk '{print $3}'`  # option l
    R=`grep -i  "Read ahead sectors" /tmp/LV | awk '{print $4}'` # option r
    echo "lvcreate -A n -v -l ${LE} -r ${R} -n ${LV_name} ${VG_name} ${PVs_LV}" >> ${ROOTFS}/etc/recovery/lvm/lvcreate.sh
  done
  } # end of while vgdisplay -v ${VG} | grep "LV Name"
done
} # end of while of strings /etc/lvmtab for LVM1
}


lvm2 () {
####
echo_log "Digging into the LVM2 configuration..."
Device=$1       # e.g. /dev/vg_sd/lvol1
FS=$2
FStype=$3
FSopt=$4

cp -dpR /etc/lvm ${ROOTFS}/etc/recovery/lvm
vgdisplay -v >${ROOTFS}/etc/recovery/lvm/vgdisplay_v.txt

# here we need to analyse our LVM layout so we can rebuild it from scratch
# if necessary...
# step 1: collect all PVs first to get sfdisk info from it
vgdisplay -v | grep "PV Name" | awk '{print $3}' | { while read Line
do
  # Line = /dev/sda1
  ParseDevice ${Line}   # returns Dev=sda1 and _Dev=sda1
  ParseDisk ${Dev}      # returns dsk=sda and _dsk=sda

  ## commented out because of SF#1867501
  #if [ -f ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk} ]; then
        # if partitions.${_dsk} exists we have the info already
  #      return
  #fi

  if [ x${BOOTARCH} = xia64 ] || [ x${BOOTARCH} = xsparc ]; then
        # for ia64 we use parted
        echo_log "Busy analyzing disk /dev/${dsk} with parted..."
        parted -s /dev/${dsk} print > ${ROOTFS}/etc/recovery/partitions.${_dsk}

        # move partitions file to lvm directory if no ide/sd is in use
        if [ -f ${ROOTFS}/etc/recovery/geometry.${_dsk} ]; then
                cp ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        else
                mv ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        fi
        create_parted_script_for_recovery ${ROOTFS}/etc/recovery/lvm/parted.${_dsk}   ${_dsk} ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}

        echo "rc=\$((rc+\$?))" >>${ROOTFS}/etc/recovery/lvm/parted.${_dsk}
        echo "touch /tmp/parted.${_dsk}.done" >>${ROOTFS}/etc/recovery/lvm/parted.${_dsk}

  else
        #for ia32 we use sfdisk
        echo_log "Busy analyzing disk /dev/${dsk} with sfdisk..."
        sfdisk -d /dev/${dsk} > ${ROOTFS}/etc/recovery/partitions.${_dsk}
        Check_partition_file
        # move partitions file to lvm directory if no ide/sd is in use
         if [ -f ${ROOTFS}/etc/recovery/geometry.${_dsk} ]; then
                cp ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        else
                mv ${ROOTFS}/etc/recovery/partitions.${_dsk} \
                ${ROOTFS}/etc/recovery/lvm/partitions.${_dsk}
        fi
        echo "sfdisk --force /dev/${dsk} < /etc/recovery/lvm/partitions.${_dsk}" > \
        ${ROOTFS}/etc/recovery/lvm/sfdisk.${_dsk}
        echo "rc=\$((rc+\$?))" >>${ROOTFS}/etc/recovery/lvm/sfdisk.${_dsk}
        echo "touch /tmp/sfdisk.${_dsk}.done" >>${ROOTFS}/etc/recovery/lvm/sfdisk.${_dsk}

fi
  # save the disk geometry too (at restore time compare disks)
  sfdisk -g /dev/${dsk} > ${ROOTFS}/etc/recovery/lvm/geometry.${_dsk}
  # save the disk size too
  sfdisk -s /dev/${dsk} > ${ROOTFS}/etc/recovery/lvm/size.${_dsk}
  Is_dsk_bootable ${dsk} ${_dsk}
  # calculate used disk space/disk. FIXME: no much sense on LVM
  echo 100 > ${ROOTFS}/etc/recovery/lvm/used.${_dsk}   # dummy nr.

  # Line = /dev/sda1
  # we can make the pvcreate-script on the fly (force per disk)
  echo "pvcreate -y -ff ${Line}" >> ${ROOTFS}/etc/recovery/lvm/pvcreate.${_dsk}
done
}
# step 2: collect PVs per VG, LVs per VG and PVs per LV
vgdisplay | grep "VG Name" | awk '{print $3}' | { while read VG
do
  # make the vgcreate.sh script
  PVs_VG=""
  vgdisplay -v ${VG} 2>/dev/null | grep "PV Name" | awk '{print $3}' | { while read Line
  do
    # collect PVs per VG
    PVs_VG="${PVs_VG} ${Line} "
    echo ${PVs_VG} > /tmp/PVs_VG        # needed for out while loop
  done
  } # end of while of vgdisplay -v ${VG} | grep "PV Name"
  vgdisplay ${VG} > /tmp/VG
  PVs_VG=`cat /tmp/PVs_VG`
  Max_LV=`grep -i "MAX LV  " /tmp/VG | awk '{print $3}'`        # -l option
  Max_PV=`grep -i "MAX PV" /tmp/VG | awk '{print $3}'`          # -p option
  PE_Size=`grep -i "PE Size" /tmp/VG | awk '{print $3$4}'|sed -e 's/B//'` # 32M
  PE_Size_Suffix=`echo ${PE_Size} | sed -e 's/[0-9]//g' -e 's/.//'` #M or K
  PE_Size=`echo ${PE_Size} |cut -d. -f1 | cut -d, -f1 | sed -e 's/[a-zA-Z]//'` # no suffix

  echo "vgcreate -A n -v -l ${Max_LV} -p ${Max_PV} -s ${PE_Size}${PE_Size_Suffix} ${VG} ${PVs_VG}" >> ${ROOTFS}/etc/recovery/lvm/vgcreate.sh
  # make lvcreate.sh script
  vgdisplay -v ${VG} 2>/dev/null | grep "LV Name" | awk '{print $3}' | { while read Lvol
  do
    # Lvol = /dev/vg_sd/lvol1
    # collect PVs per Lvol
    PVs_LV=""
    lvdisplay -m ${Lvol} | grep "Physical volume" | awk '{print $3}' | { while read Line
    do
      # Is the PV allready in $PVs_LV ?
      echo ${PVs_LV}|grep ${Line} > /dev/null
        if [ $? -ne 0 ]; then
              # device per Lvol, e.g. /dev/sda1
              PVs_LV="${PVs_LV} ${Line}"
              echo ${PVs_LV} > /tmp/PVs_LV
        fi
    done
    } # end of while lvdisplay -v ${Lvol} 

    lvdisplay ${Lvol} > /tmp/LV
    PVs_LV=`cat /tmp/PVs_LV`
    LV_name=`echo ${Lvol} | cut -d"/" -f4-`             # lvol1
    VG_name=`grep -i  "VG Name" /tmp/LV | awk '{print $3}'` # vg_sd
    LE=`grep -i  "Current LE" /tmp/LV | awk '{print $3}'`  # option l
    R=`grep -i  "Read ahead sectors" /tmp/LV | awk '{print $4}'` # option r
    # find the stripes & stripesizes
    #LV:VG:Attr:LSize:Origin:Snap%:Move:Copy%:#Str:Stripe
    #lvvsp:VolGroup00:-wi-ao:20971.52M:::::1:0M
    # on FC4 STRIPES is field 9, but on RHEL it is 10 - hack around with sed
    STRIPES=`lvs --units M --separator : -o +stripes | tail -n 1 | cut -d: -f9- | sed -e 's/://g'`
    STRSIZE=`lvs --units M --separator : -o +stripesize | tail -n 1 | cut -d: -f9- | sed -e 's/://g'`
    STRIPE_OPTIONS=""
    if [ -n "${STRIPES}" -a "${STRIPES}" -gt 1 -a -n "${STRSIZE}" -a "${STRSIZE}" != "0M" ]; then
        STRIPE_OPTIONS="-i ${STRIPES} -I ${STRSIZE}"
    fi
    echo "lvcreate -A n -v -l ${LE} -r ${R} ${STRIPE_OPTIONS} -n ${LV_name} ${VG_name} ${PVs_LV}" >> ${ROOTFS}/etc/recovery/lvm/lvcreate.sh
  done
  } # end of while vgdisplay -v ${VG} | grep "LV Name"
done
} # end of while of vgdisplay -v ${VG} | grep "LV Name" (outerloop)
}

software_raid () {
################
Device=$1       # e.g. /dev/md0
FS=$2
FStype=$3
FSopt=$4
if [ "${FS}" = "${DESTINATION_PATH}" ]; then
   return       # do not backup our mounted DR disk!
fi

# check if the raidtools are available or not:
which lsraid >/dev/null 2>&1
if [ $? -eq 1 ]; then
   # no raidtools found; do we have mdadm instead?
   which mdadm >/dev/null 2>&1
   if [ $? -eq 1 ]; then
        # no raidtools, no mdadm found => fail
        Fail "Sorry, did not find raidtools nor mdadm."
   else # mdadm
        # create (if not present) a /etc/mdadm.conf file
        Analyse_mdadm_conf
   fi # mdadm
else  # lsraid
        Analyse_raidtools_conf
fi # lsraid
}

Analyse_raidtools_conf () {
######################
# analyse /etc/raidtab and make the approriate sfdisk.devices (for multiple
# disks). => raidtools
# Debian keeps it raidtab file in /etc/raid
# $Device e.g. /dev/md0, $FS, $FStype and $FSopt are enherited from software_raid()
if [ ! -f /etc/raidtab ] && [ ! -f /etc/raid/raidtab ]; then
   echo "Warning: Software raid detected but no /etc/[raid/]raidtab file found?" | tee -f ${LOG}
   echo "Will try to create a /etc/raidtab.mkcdrec for you - if possible!!!" |tee -f ${LOG}
  lsraid -R -p > /etc/raidtab.mkcdrec
   [ -f /etc/raidtab.mkcdrec ] && echo "!!! /etc/raidtab.mkcdrec CREATED !!!" | tee -f ${LOG}
fi
[ -f /etc/raidtab ] && cp /etc/raidtab  ${ROOTFS}/etc/recovery/
[ -f /etc/raid/raidtab ] && cp /etc/raid/raidtab  ${ROOTFS}/etc/recovery/
[ -f /etc/raidtab.mkcdrec ] && cp /etc/raidtab.mkcdrec ${ROOTFS}/etc/recovery/raidtab
cat /proc/mdstat >  ${ROOTFS}/etc/recovery/mdstat
[ ! -f ${ROOTFS}/etc/recovery/raidtab ] && Fail "Did not found a valid raidtab file!"

mkdir -p ${ROOTFS}/etc/recovery/md      # put info of md disks separate
start_md_analyse=0
# first part: identify all disks and save their info (sfdisk...)
awk ' /dev/ {print $2}' ${ROOTFS}/etc/recovery/raidtab | \
{ while read MDline
do
  echo ${MDline} | grep md >/dev/null 2>&1
  if [ $? -eq 0 ]; then         # this line starts a md description
    # $Device (and maybe $MDline) can be /dev/md/0 and/or /dev/md0 (devfs or not)
    # therefore a trick is needed
    TmpMDline=`echo ${MDline}  | cut -d"/" -f3-|sed -e 's;/;;'` # md0
    TmpDevice=`echo ${Device}  | cut -d"/" -f3-|sed -e 's;/;;'`
    if [ "${TmpMDline}" = "${TmpDevice}" ]; then
        #MD_dev=${MDline}       #  save /dev/md0 (from raidtab)
        MD_dev=${Device}        #  save /dev/md0 or /dev/md/0 (as mounted)
        start_md_analyse=1
        continue
    else
        start_md_analyse=0
    fi
  fi
  if [ ${start_md_analyse} -eq 1 ]; then        # devices of /dev/md0 follow
        Analyse_md_device ${MDline} ${MD_dev}   # e.g. /dev/hda1 /dev/md0
  fi # end of [ ${start_md_analyse} -eq 1 ]
done
} # end of while MDline
# ${ROOTFS}/etc/recovery/md/mkfs.${_md} file contains too much commands
# for each disk once, therefore trim down to execute commands only once
#ed ${ROOTFS}/etc/recovery/md/mkfs.${_md} <<EOD >/dev/null 2>&1
#/rc
#.+1,\$d
#w
#q
#EOD
# Keep fs list apart to tar-ball later

# track any md? swap devices and append the line to /etc/recovery/md/df.`hostname`
md_swap_tracking

MD_dev=`cat /tmp/MDdev`
rm -f /tmp/MDdev
echo -e "${MD_dev}\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
} # end of function Analyse_raidtools_conf

md_swap_tracking () {
################
#### BEGIN md swap tracking ####
# track down swap meta-device and translate it into source devices into
# md/df.$HOSTNAME file (we might need it for cloning a md device to a single IDE/SCSI device)
for sw in `cat /proc/swaps | grep dev | awk '{print $1}'`
do
  # $sw looks like /dev/md2 ?
  echo ${sw} | grep md >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    # yes, swap is a md dev
    md_sw=`echo ${sw} | cut -d"/" -f 3` # md2
    # md2 : active raid1 hda3[0] hdb3[1] (for other raid? 2 more dev show)
    for swdev in `cat /proc/mdstat | grep ${md_sw} | awk '{print $5, $6, $7, $8}'`
    do
      # swdev looks like hda3[0]
      swdev=`echo ${swdev} | sed -e 's/\[.*//'` # hda3
      echo "/dev/${swdev} swap 0 0 0 0 ${md_sw}" >> ${ROOTFS}/etc/recovery/md/df.`hostname`
    done
  fi # of grep md
done
# for every loop 'swap' is listed, make sure it is listed only once (gdha)
cp ${ROOTFS}/etc/recovery/md/df.`hostname` /tmp/x.$$
cat /tmp/x.$$ | sort -u > ${ROOTFS}/etc/recovery/md/df.`hostname`
rm -f /tmp/x.$$
#### END of md swap tracking ####
}

Analyse_md_device () {
################# 
# input parameters: ${MDline} ${MD_dev}   # e.g. /dev/hda1 /dev/md0
# $Device e.g. /dev/md0, $FS, $FStype and $FSopt are enherited from software_raid()
# routine is responsible mainly for the sfdisk scripts and mkfs scripts (for md re-creation)
    MDline=$1
    MD_dev=$2
    ParseDevice ${MDline}       # returns Dev=hdb5 and _Dev=hdb5
    ParseDisk ${Dev}            # returns dsk=hdb and _dsk=hdb
    
    echo_log "Busy analyzing disk /dev/${dsk} with sfdisk..."
    sfdisk -d /dev/${dsk} > ${ROOTFS}/etc/recovery/partitions.${_dsk}
    Check_partition_file
    mv ${ROOTFS}/etc/recovery/partitions.${_dsk} \
        ${ROOTFS}/etc/recovery/md/partitions.${_dsk}
    echo "sfdisk --force /dev/${dsk} < /etc/recovery/md/partitions.${_dsk}" > \
     ${ROOTFS}/etc/recovery/md/sfdisk.${_dsk}
    echo "rc=\$((rc+\$?))" >>${ROOTFS}/etc/recovery/md/sfdisk.${_dsk}
    echo "touch /tmp/sfdisk.${_dsk}.done" >>${ROOTFS}/etc/recovery/md/sfdisk.${_dsk}
    # save the disk geometry too (at restore time compare disks)
    sfdisk -g /dev/${dsk} > ${ROOTFS}/etc/recovery/md/geometry.${_dsk}
    # save the disk size too
    sfdisk -s /dev/${dsk} > ${ROOTFS}/etc/recovery/md/size.${_dsk}
    Is_dsk_bootable ${dsk} ${_dsk}
    Calculate_used_space ${MD_dev} ${dsk}
    echo ${j} > ${ROOTFS}/etc/recovery/md/used.${_dsk}

    # check if MD_dev is swap; yes -> return (no FS to create)
    [ "`cat /proc/swaps | grep ^/dev | awk '{print $1}'`" = "${MD_dev}" ] && return
    # second part: make the mkfs scripts
    # EXTRA_OPTS var. in case some fs needs special treatment
    EXTRA_OPTS=""

    if [ "${FStype}" = "reiserfs" -a "${kernel_minor_nr}" = "2" ]; then
      # Reiserfs on 2.2.* based kernels needs the -v 1 flag
      EXTRA_OPTS="-v 1"
    fi
    
    if [ "${FStype}" = "reiserfs" -o "${FStype}" = "xfs" ]; then
      CHECK_BAD_BLOCKS=""  # reiserfs and xfs do not use ext2 concepts. 
    fi

    if [ "${FStype}" = "xfs" ]; then
      EXTRA_OPTS="-f" # xfs needs the force option for mkfs to overwrite an existing part
    fi

    if [ "${FStype}" = "ext3" ] -o [ "${FStype}" = "ext4" ]; then
      JOURNAL="-j"
      CHECK_BAD_BLOCKS="" #doing bad block checking while mkraid is busy is slow
    else
      JOURNAL=""
    fi

    # MD_dev can be e.g. /dev/md0 or /dev/md/0, _md is used as extention
    _md=`echo ${MD_dev} | cut -d"/" -f3- | sed -e 's;/;;'`      # e.g. md0
    # save MD_dev for writing to To_Backup
    echo ${MD_dev} > /tmp/MDdev

    if [ "${FStype}" = "jfs" ]; then
      CHECK_BAD_BLOCKS=""
      JOURNAL="-f -L:jfs_${_md}"
    fi

    echo "modprobe -q ${FStype} >/dev/null 2>&1" > ${ROOTFS}/etc/recovery/md/mkfs.${_md}
    #grep raid-level ${ROOTFS}/etc/recovery/raidtab | sort -u | \
    cat /proc/mdstat | grep raid | awk '{print $4}' | sort -u | \
    { while read RaidLevel
    do
        # e.g. raid0
        [ ! -z "${RaidLevel}" ] && \
        echo "modprobe -q ${RaidLevel} >/dev/null 2>&1" >> ${ROOTFS}/etc/recovery/md/mkfs.${_md}
    done
    }
    lsmod | grep -q dm_mod && echo "modprobe -q dm_mod >/dev/null 2>&1" >> ${ROOTFS}/etc/recovery/md/mkfs.${_md}
    lsmod | grep -q dm-mod && echo "modprobe -q dm-mod >/dev/null 2>&1" >> ${ROOTFS}/etc/recovery/md/mkfs.${_md}
    echo "mkfs -t ${FStype} ${JOURNAL} ${EXTRA_OPTS} ${CHECK_BAD_BLOCKS} ${MD_dev}" >> ${ROOTFS}/etc/recovery/md/mkfs.${_md}
    echo "rc=\$((rc+\$?))" >> ${ROOTFS}/etc/recovery/md/mkfs.${_md}

    # Link meta-device (_md, e.g. md0) to $Dev (e.g. hda1) with output of df
    # We may need this to clone meta-device to a single IDE/SCSI disk
    _md_df=`df -P ${MD_dev} | tail -n 1 | awk '{print $2, $3, $4, $5, $6}'`
    echo "/dev/${Dev} ${_md_df} ${_md}" >> ${ROOTFS}/etc/recovery/md/df.`hostname`
    # prepare a To_Restore file for cloning md to single IDE/SCSI
    echo -e "/dev/${Dev}\t${FS}\t${FStype}\t${FSopt}" >> ${ROOTFS}/etc/recovery/md/To_Restore.md
}


########################

Analyse_mdadm_conf () {
##################
# Software RAID controlled by mdadm
# is there a mdadm.conf file present? Not really needed, but advisable!
# we have to go through all these steps only once - make lock file.
if [ -f /tmp/Analyse_mdadm_conf.lck ]; then
        # ok, seen this meta-device - make entry in To_Backup
        echo -e "${Device}\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
        return
fi

echo_log "Entering the Software Raid analysis phase with mdadm.conf"
touch /tmp/Analyse_mdadm_conf.lck # create the lock file
#if [ ! /etc/mdadm.conf ] || [ ! /etc/mdadm/mdadm.conf ]; then
   #  file not found
   echo_log "Create an /etc/mdadm.conf.mkcdrec file for you:"
   # let us create one to begin with - start with the DEVICE line (very generic)
   echo "DEVICE /dev/hd* /dev/sd*" > /etc/mdadm.conf.mkcdrec
   # append the ARRAY lines
   mdadm --detail --scan >> /etc/mdadm.conf.mkcdrec
   cat /etc/mdadm.conf.mkcdrec | tee -a ${LOG}
#fi

mkdir -p ${ROOTFS}/etc/recovery/md
# copy the /etc/mdadm.conf file
[ -f /etc/mdadm.conf ] && cp -f /etc/mdadm.conf ${ROOTFS}/etc/recovery/
[ -f /etc/mdadm/mdadm.conf ] && cp -f /etc/mdadm/mdadm.conf ${ROOTFS}/etc/recovery/
[ -f /etc/mdadm.conf.mkcdrec ] && cp -f /etc/mdadm.conf.mkcdrec ${ROOTFS}/etc/recovery/mdadm.conf
[ ! -f ${ROOTFS}/etc/recovery/mdadm.conf ] && Fail "No mdadm.conf to analyse."
cat /proc/mdstat >  ${ROOTFS}/etc/recovery/mdstat


# Analyse the lines so we can create the sfdisk scripts, etc...
for i in 0 1 2 3 4 5 6 7 8 9
do
 echo "mknod /dev/md${i} b 9 ${i}" >>${ROOTFS}/etc/recovery/md/mdadm-create.sh
done

egrep "(ARRAY|devices)"  ${ROOTFS}/etc/recovery/mdadm.conf | { while read Inline
do
        # we must glue the ARRAY line with a devices line
        echo ${Inline} | grep -q ^ARRAY 2>/dev/null
        if [ $? -eq 0 ]; then
           # line starts with ARRAY
           echo ${Inline} | while read junk MD_dev level numdev uuid
           do
                echo ${level} | grep  -q ^level && \
                  MD_raidlevel=`echo ${level} | cut -d= -f2 | sed -e 's/raid//'` # e.g. 1
                echo ${numdev} | grep  -q ^num && \
                  MD_numdev=`echo ${numdev} | cut -d= -f2 | sed -e 's/num-devices=//'` # e.g. 2
		echo "mdadm --stop ${MD_dev}" >>${ROOTFS}/etc/recovery/md/mdadm-create.sh

                # We need the physical partition for routine Analyse_md_device
		ParseDevice ${MD_dev}       # returns Dev=md0
		# FIXME: gdha WIP
		for dk in `cat /proc/mdstat | grep ${Dev} | awk '{print $5, $6, $7, $8}'`
		do
		  part=`echo ${dk} | cut -d"[" -f1`      # hda1
		  Analyse_md_device /dev/${part} ${MD_dev}
		  echo "mdadm --zero-superblock /dev/${part}" >> ${ROOTFS}/etc/recovery/md/mdadm-create.sh
		  echo -n "/dev/${part} " >> /tmp/MD_devices
		done
		MD_devices="`cat /tmp/MD_devices`"
		rm -f /tmp/MD_devices
		# we have enough info to start making mdadm-create script
                echo "mdadm --create --verbose ${MD_dev} --level=${MD_raidlevel} --raid-devices=${MD_numdev} ${MD_devices}" >> ${ROOTFS}/etc/recovery/md/mdadm-create.sh
           done # end of Inline
        else
           # line starts with devices
           MD_devices=`echo ${Inline} | cut -d= -f2 | sed -e 's/,/ /'` # e.g. /dev/hda1 /dev/hdb1
           echo "mdadm --stop ${MD_dev}" >>${ROOTFS}/etc/recovery/md/mdadm-create.sh
           for MDline in ${MD_devices}
           do
                Analyse_md_device ${MDline} ${MD_dev}   # e.g. /dev/hda1 /dev/md0
                echo "mdadm --zero-superblock ${MDline}" >> ${ROOTFS}/etc/recovery/md/mdadm-create.sh
           done
           # we have enough info to start making mdadm-create script
           echo "mdadm --create --verbose ${MD_dev} --level=${MD_raidlevel} --raid-devices=${MD_numdev} ${MD_devices}" >> ${ROOTFS}/etc/recovery/md/mdadm-create.sh
        fi
done
chmod +x ${ROOTFS}/etc/recovery/md/mdadm-create.sh
} # end of egrep "(ARRAY|devices)" 

# track any md? swap devices and append the line to /etc/recovery/md/df.`hostname`
md_swap_tracking

echo -e "${Device}\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
} # END OF FUNCTION 

hd_sd_disk_types () {
#^^^^^^^^^^^^^^^
# make the scripts to restore disk layouts of IDE/SCSI disks
Device=$1       # e.g. /dev/hda2
FS=$2
FStype=$3
FSopt=$4
if [ "${FS}" = "${DESTINATION_PATH}" ]; then
   return       # do not backup our mounted DR disk!
fi
ParseDevice ${Device}
# Output of above routine results in 2 newly defined variables
# Dev = hda2
# _Dev = hda2 (If / was present it is replaced by _)
# dsk = hda (whole disk)

if [ -c /dev/.devfsd ]; then
   # e.g. disc=ide/host0/bus0/target0/lun0/disc
   disc=`echo ${Dev} | cut -d"p" -f 1`disc
   if [ -b /dev/${disc} ]; then # I'm paranoid I know
     # to please sfdisk we have to backtrace the old style name (hda)
     dsk=`ls -l /dev | grep ${disc} | awk '{print $9}'`
   else
     # maybe devfs was configured in old style only?
     dsk=`echo ${Dev} | sed -e 's/[0-9]//g'`      # hda
   fi
else
   dsk=`echo ${Dev} | sed -e 's/[0-9]//g'`      # hda
fi
_dsk=`echo ${dsk} | tr "/" "_"`

if [ x${BOOTARCH} = xia64 ] || [ x${BOOTARCH} = xsparc ]; then
        echo_log "Busy analyzing disk /dev/${dsk} with parted..."
        parted -s /dev/${dsk} print > ${ROOTFS}/etc/recovery/partitions.${_dsk}

        create_parted_script_for_recovery ${ROOTFS}/etc/recovery/parted.${_dsk} ${_dsk} ${ROOTFS}/etc/recovery/partitions.${_dsk}
else
        echo_log "Busy analyzing disk /dev/${dsk} with sfdisk..."
        sfdisk -d /dev/${dsk} > ${ROOTFS}/etc/recovery/partitions.${_dsk}
        Check_partition_file


        # make the sfdisk.sh in the fly ;-)
        echo "[ -f /tmp/sfdisk.${_dsk}.done ] && exit" >${ROOTFS}/etc/recovery/sfdisk.${_dsk}
        echo "sfdisk --force /dev/${dsk} < /etc/recovery/partitions.${_dsk}" >> \
  ${ROOTFS}/etc/recovery/sfdisk.${_dsk}

fi

# save the disk geometry too (at restore time compare disks)
sfdisk -g /dev/${dsk} > ${ROOTFS}/etc/recovery/geometry.${_dsk}
# save the disk size too
sfdisk -s /dev/${dsk} > ${ROOTFS}/etc/recovery/size.${_dsk}
Is_dsk_bootable ${dsk} ${_dsk}

Calculate_used_space ${Dev} ${dsk}
#if [ -c /dev/.devfsd ]; then
   # a very strange trick to collect total amount of disk space in use
#   dsk=`echo ${Dev} | cut -d"p" -f 1`part
#fi
#j=0
#for i in `df -kP | grep ${dsk} | awk '{print $3}'`
#do
#  j=`expr ${j} + ${i}`
#done
echo ${j} > ${ROOTFS}/etc/recovery/used.${_dsk}

# Create the mkfs.sh script for the recovery process (/dev/hda1)

# EXTRA_OPTS var. in case some fs needs special treatment
EXTRA_OPTS=""

if [ "${FStype}" = "reiserfs" -a "${kernel_minor_nr}" = "2" ]; then
   # Reiserfs on 2.2.* based kernels needs the -v 1 flag
   EXTRA_OPTS="-v 1"
fi

if [ "${FStype}" = "reiserfs" -o "${FStype}" = "xfs" ]; then
   CHECK_BAD_BLOCKS=""  # reiserfs and xfs do not use ext2 concepts. good stuff.
fi

if [ "${FStype}" = "xfs" ]; then
   EXTRA_OPTS="-f" # xfs needs the force option for mkfs to overwrite an existing part
fi

if [ "${FStype}" = "ext3" ] -o [ "${FStype}" = "ext4" ]; then
   JOURNAL="-j"
else
   JOURNAL=""
fi

if [ "${FStype}" = "jfs" ]; then
   CHECK_BAD_BLOCKS=""
   JOURNAL="-f -L:jfs_${Dev}"
fi

case ${FStype} in
  ext2|auto|reiserfs|minix|xfs|jfs)
   echo "mkfs -t ${FStype} ${JOURNAL} ${EXTRA_OPTS} ${CHECK_BAD_BLOCKS} /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   Check_fixed /dev/${Dev} ${_dsk}
   ;;
  ext3|ext4)
   #there are some problems with mkfs.ext3 so we use mkfs.ext2 and tune2fs
   echo "mkfs -t ext2 ${EXTRA_OPTS} ${CHECK_BAD_BLOCKS} /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "tune2fs -j /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   Check_fixed /dev/${Dev} ${_dsk}
   ;;
  msdos|fat)
   echo "dd if=/dev/zero of=/dev/${Dev} bs=512 count=1" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "mkdosfs -F 16 /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   ;;
  vfat|ntfs)
   echo "dd if=/dev/zero of=/dev/${Dev} bs=512 count=1" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "mkdosfs -F 32 /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "/dev/${Dev}" >> ${ROOTFS}/etc/recovery/fixed.${_dsk}
   ;;
esac
# Keep fs list apart to tar-ball later
echo -e "/dev/${Dev}\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
}

ida_disk_types () {
#^^^^^^^^^^^^^
# make the scripts to restore disk layouts of Compaq's SMART2 Intelligent 
# Disk Array (ida devices)
# Another Compaq Raid is CCISS, eg. /dev/cciss/c0d0p1
Device=$1                       # eg. /dev/ida/c0d0p1
FS=$2
FStype=$3
FSopt=$4
if [ "${FS}" = "${DESTINATION_PATH}" ]; then
   return       # do not backup our mounted DR disk!
fi
#dsk=`echo ${Device} | cut -d"/" -f 3- | cut -dp -f1`    # ida/c0d0
dsk=`echo ${Device} | cut -d"/" -f 3- | sed -e "s/p[0-9]$//"`    # ida/c0d0
_dsk=`echo ${dsk} | tr "/" "_"`                         # ida_c0d0

if [ x${BOOTARCH} = xia64 ] || [ x${BOOTARCH} = xsparc ]; then
   echo_log "Busy analyzing disk /dev/${dsk} with parted..."
   parted -s /dev/${dsk} print > ${ROOTFS}/etc/recovery/partitions.${_dsk}

   create_parted_script_for_recovery ${ROOTFS}/etc/recovery/parted.${_dsk} ${_dsk} ${ROOTFS}/etc/recovery/partitions.${_dsk}
else
   echo_log "Busy analyzing disk /dev/${dsk} with sfdisk..."
   sfdisk -d /dev/${dsk} > ${ROOTFS}/etc/recovery/partitions.${_dsk}
   Check_partition_file

   # make the sfdisk.sh in the fly ;-)
   echo "[ -f /tmp/sfdisk.${_dsk}.done ] && exit" >${ROOTFS}/etc/recovery/sfdisk.${_dsk}
   echo "sfdisk --force /dev/${dsk} < /etc/recovery/partitions.${_dsk}" >> \
        ${ROOTFS}/etc/recovery/sfdisk.${_dsk}
fi

# save the disk geometry too (at restore time compare disks)
sfdisk -g /dev/${dsk} > ${ROOTFS}/etc/recovery/geometry.${_dsk}
# save the disk size too
sfdisk -s /dev/${dsk} > ${ROOTFS}/etc/recovery/size.${_dsk}
Is_dsk_bootable ${dsk} ${_dsk}

# Create the mkfs.sh script for the recovery process (/dev/ida/c0d0p1)
ParseDevice ${Device}
# Dev = ida/c0d0p1
#_Dev = ida_c0d0p1

# calculate the total USED disk space on this disk (all partitions)
Calculate_used_space ${Dev} ${dsk}
echo ${j} > ${ROOTFS}/etc/recovery/used.${_dsk}

# EXTRA_OPTS var. in case some fs needs special treatment
EXTRA_OPTS=""

if [ "${FStype}" = "reiserfs" -a "${kernel_minor_nr}" = "2" ]; then
   # Reiserfs on 2.2.* based kernels needs the -v 1 flag
   EXTRA_OPTS="-v 1"
fi

if [ "${FStype}" = "reiserfs" -o "${FStype}" = "xfs" ]; then
   CHECK_BAD_BLOCKS=""  # reiserfs and xfs do not use ext2 concepts. good stuff.
fi

if [ "${FStype}" = "xfs" ]; then
   EXTRA_OPTS="-f" # xfs needs the force option for mkfs to overwrite an existing part
fi

if [ "${FStype}" = "ext3" ] -o [ "${FStype}" = "ext4" ]; then
   JOURNAL="-j"
else
   JOURNAL=""
fi

if [ "${FStype}" = "jfs" ]; then
   CHECK_BAD_BLOCKS=""
   JOURNAL="-f -L:jfs_${Dev}"
fi

case ${FStype} in
  ext2|ext3|ext4|auto|reiserfs|minix|xfs|jfs)
   echo "mkfs -t ${FStype} ${JOURNAL} ${EXTRA_OPTS} ${CHECK_BAD_BLOCKS} /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   Check_fixed /dev/${Dev} ${_dsk}
   ;;
  msdos|fat)
   echo "dd if=/dev/zero of=/dev/${Dev} bs=512 count=1" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "mkdosfs -F 16 /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   ;;
  vfat|ntfs)
   echo "dd if=/dev/zero of=/dev/${Dev} bs=512 count=1" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "mkdosfs -F 32 /dev/${Dev}" >> ${ROOTFS}/etc/recovery/mkfs.${_dsk}
   echo "/dev/${Dev}" >> ${ROOTFS}/etc/recovery/fixed.${_dsk}
   ;;
esac

# Keep fs list apart to tar-ball later
echo -e "/dev/${Dev}\t${FS}\t${FStype}\t${FSopt}" >> ${TMP_DIR}/To_Backup
}

Is_dsk_bootable () {
#^^^^^^^^^^^^^^^^^
# function args: $dsk $_dsk
# function output: create mbr.$_dsk file is disk exists
# we will use sfdisk on ia32 and parted on ia64

# skip investigation for MBR on disk if mbr.$_dsk already exist.
if [ ! -f ${ROOTFS}/etc/recovery/mbr.$2 ]; then
 echo_log "${ROOTFS}/etc/recovery/mbr.$2 not found. Check for MBR:"
 case "${BOOTARCH}" in
 "ia64"|"sparc")
    parted /dev/$1 print 2>/dev/null | grep boot > /dev/null
    if [ $? -eq 0 ]; then
        dd if=/dev/$1 of=${ROOTFS}/etc/recovery/mbr.$2 bs=512 count=2 >/dev/null
        echo_log "Copy the 2 first sectors of /dev/$1 on etc/recovery/mbr.$2"
    else
        echo "Disk /dev/$1 is not a boot disk." | tee -a ${LOG}
    fi
    ;;
 *) # ia32, ppc goes here
    sfdisk -d /dev/$1 2>/dev/null | grep bootable  >/dev/null
    if [ $? -eq 0 ]; then
        dd if=/dev/$1 of=${ROOTFS}/etc/recovery/mbr.$2 bs=512 count=1 >/dev/null
        echo_log "Dump the Master Boot Record of /dev/$1 to etc/recovery/mbr.$2"
        echo_log "${ROOTFS}/etc/recovery/mbr.$2 created."
    else
        echo "Disk /dev/$1 is not a boot disk." | tee -a ${LOG}
    fi
    ;;
 esac
fi # ! -f ${ROOTFS}/etc/recovery/mbr.$2
}

Check_Bootloader () {
#^^^^^^^^^^^^^^^^^^
# Are we using LILO, GRUB, others
if [ ! -z "`ls ${ROOTFS}/etc/recovery/mbr.* 2>/dev/null`" ]; then
  strings ${ROOTFS}/etc/recovery/mbr.* > /tmp/bootloader
  grep LILO /tmp/bootloader >/dev/null 2>&1
  if [ $? -eq 0 ]; then
        echo "LILO" > ${ROOTFS}/etc/recovery/BOOTLOADER
  fi
  grep GRUB /tmp/bootloader >/dev/null 2>&1
  if [ $? -eq 0 ]; then
        echo "GRUB" > ${ROOTFS}/etc/recovery/BOOTLOADER
  fi
  rm -f  /tmp/bootloader
fi

if [ x${BOOTARCH} = xsparc ]; then
  echo "SILO" > ${ROOTFS}/etc/recovery/BOOTLOADER
fi

if [ x${BOOTARCH} = xia64 ]; then
  echo "ELILO" > ${ROOTFS}/etc/recovery/BOOTLOADER
fi

BOOTLOADER=`cat ${ROOTFS}/etc/recovery/BOOTLOADER`
echo_log "Bootloader in use is ${BOOTLOADER}"

if [ x${BOOTLOADER} = xUNKNOWN ]; then
   echo_log "Bootloader is unknown: checking all local disks and partitions"
   cat /proc/partitions | awk '{print $4}' |grep -v name | { while read Line
   do
    if [ -b /dev/$Line ]; then
     MBRfound=0
     echo_log "Check if /dev/${Line} contains a master boot record: "
     _disk=`echo ${Line} | tr "/" "_"`
     # check if we find a bootloader info on disk/partition?
     dd if=/dev/${Line} bs=512 count=1 > /tmp/${_disk}.$$ 2>/dev/null
     strings /tmp/${_disk}.$$ | grep -q LILO
     if [ $? -eq 0 ]; then
        MBRfound=1
        cp -f /tmp/${_disk}.$$ ${ROOTFS}/etc/recovery/mbr.${_disk}
        echo "LILO" > ${ROOTFS}/etc/recovery/BOOTLOADER
     fi
     strings /tmp/${_disk}.$$ | grep -q GRUB
     if [ $? -eq 0 ]; then
        MBRfound=1
        cp -f /tmp/${_disk}.$$ ${ROOTFS}/etc/recovery/mbr.${_disk}
        echo "GRUB" > ${ROOTFS}/etc/recovery/BOOTLOADER
     fi
     rm -f /tmp/${_disk}.$$
     if [ ${MBRfound} -eq 1 ]; then
        echo_log "yes"
        echo "/dev/${Line} uses `cat ${ROOTFS}/etc/recovery/BOOTLOADER` and MBR is saved into etc/recovery/mbr.${_disk}" | tee -a ${LOG}
     else
        echo_log "no"
     fi
    fi # [ -b /dev/$Line ]
   done
   }
fi # BOOTLOADER = UNKNOWN
cp ${ROOTFS}/etc/recovery/BOOTLOADER ${ROOTFS}/etc/recovery/BOOTLOADER.save
}


Check_partition_file () {
#^^^^^^^^^^^^^^^^^^^^^^
# Sometimes we have a warning message in the partitions.$_dsk file which
# makes sfdisk fail at restore time (we will remove those lines)
grep -i "^warning" ${ROOTFS}/etc/recovery/partitions.${_dsk} >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "WARNING: ${ROOTFS}/etc/recovery/partitions.${_dsk}" | tee -a ${LOG}
  echo "`head -n 2 ${ROOTFS}/etc/recovery/partitions.${_dsk}`" | tee -a ${LOG}
  cat ${ROOTFS}/etc/recovery/partitions.${_dsk} | grep -vi "^warning" | \
    grep -vi "^dos" > ${ROOTFS}/etc/recovery/partitions.${_dsk}_tmp
  # piping from same file to self could make it 0 length, move it instead
  mv ${ROOTFS}/etc/recovery/partitions.${_dsk}_tmp ${ROOTFS}/etc/recovery/partitions.${_dsk}
  echo "Note: removed above 2 listed lines from partitions.${_dsk}" | tee -a ${LOG}
fi

# If LANG is not set to C (it should be) and sfdisk is still producing French
# comments like "N° table de partition de " then we should replace the "N"
# with hash(#) sign.
head -n 2 ${ROOTFS}/etc/recovery/partitions.${_dsk} | grep "#" >/dev/null 2>&1
if [ $? -eq 1 ]; then
  echo "WARNING: ${ROOTFS}/etc/recovery/partitions.${_dsk}" | tee -a ${LOG}
  echo "`head -n 2 ${ROOTFS}/etc/recovery/partitions.${_dsk}`" | tee -a ${LOG}
  echo "Comment must start with #" | tee -a ${LOG}
  sed -e 's/^N/#/' <${ROOTFS}/etc/recovery/partitions.${_dsk} >${ROOTFS}/etc/recovery/partitions.${_dsk}_tmp
  mv ${ROOTFS}/etc/recovery/partitions.${_dsk}_tmp ${ROOTFS}/etc/recovery/partitions.${_dsk}
fi
}

Miscellaneous () {
#^^^^^^^^^^^^^^^
# Do things that don't fit in other modules
touch ${ROOTFS}/var/run/utmp
touch ${ROOTFS}/var/log/wtmp
chmod 664 ${ROOTFS}/var/run/*
chown root.tty ${ROOTFS}/var/run/*
touch ${ROOTFS}/etc/mtab
chmod 664 ${ROOTFS}/etc/mtab
chown root.root ${ROOTFS}/etc/mtab
}

Make_symlinks () {
#^^^^^^^^^^^^^^^
# make symbolic links inside rootfs (use list LINKS from Config.sh)
# e.g. /bin=sh=bash => cd /bin; ln -sf bash sh
cd ${stagedir}
for i in `echo ${LINKS}`
do
    cd ${stagedir}
    linkdir=.`echo $i | cut -d= -f 1`
    from=`echo $i | cut -d= -f 3`
    to=`echo $i | cut -d= -f 2`
    case $from in
    gzip|bzip2) # it will automatically find the right dir
        echo_log "Change linkdir ${linkdir} listed in Config.sh of $from into "
        linkdir=`find . -name $from | sed -e 's;'${from}';;'`
        echo_log "${linkdir}"
        ;;
    *) ;;
    esac
    cd $linkdir || Fail "rd-base.sh: Make_symlinks: linkdir $linkdir not found"
    if [ -f $to ]; then
       echo_log "Library $to already existed. Skipped linking"
    else
      echo_log "cd $linkdir; ln -sf $from $to"
      ln -sf $from $to
      #cd ${stagedir}
    fi
done
}

# reads all the binaries for their dependencies
build_lib_list() {
#^^^^^^^^^^^^^^^
    cd ${ROOTFS}
    pushd $stagedir > /dev/null
    a=`ldd \`find . -perm +111 -a ! -type d -a ! -type l 2> /dev/null | grep -v /dev\` | grep -v linux-gate | \
            grep "=>" | sort | awk '{print $3}' | grep -v '^dynamic$' | uniq`
    LIBDIR="${LIBDIR} ${a}"
    popd > /dev/null
}

Make_libs () {
#^^^^^^^^^^^
# LIBRARIES ###########################################################
echo_log "Copying the libraries we need..."
for i in `echo $LIBDIR /lib/libnss_files.so.2`
do
    echo "$i" | grep -q "^(0x0" && continue
    LibPath=`Find_path_of_file $i`
    [ -d $stagedir/${LibPath} ] || mkdir -p ${stagedir}${LibPath}
    echo_log strip_copy_lib $i ${stagedir}${LibPath}/`basename $i`
    strip_copy_lib $i ${stagedir}${LibPath}/`basename $i` 
done

if [ x${BOOTARCH} = xx86_64 ]; then
   # some specials needed for x86_64
   echo_log "${BOOTARCH}: copy ld-linux-x86-64.so.2 into /lib64"
#   rmdir $stagedir/lib64 2>/dev/null
#   (cd $stagedir/; ln -s lib lib64)
   strip_copy_lib /lib64/ld-linux-x86-64.so.2 ${stagedir}/lib64/ld-linux-x86-64.so.2
   strip_copy_lib /lib64/libnss_files.so.2 ${stagedir}/lib64/libnss_files.so.2
fi
if [ x${BOOTARCH} = xia64 ]; then
   # libs needed for ia64
   if [ -f /lib/ld-linux-ia64.so.2 ]; then
      echo_log "${BOOTARCH}: copy ld-linux-ia64.so.2"
      strip_copy_lib /lib/ld-linux-ia64.so.2 $stagedir/lib/ld-linux-ia64.so.2
   fi
fi

if [ -d /lib/security ]; then
   echo_log "`cp -dpR /lib/security/ ${stagedir}/lib`"
   strip ${stagedir}/lib/security/* >/dev/null 2>/dev/null
fi

# Copy /lib/udev
if [ -d /lib/udev ]; then
   cp -dpR /lib/udev/ ${stagedir}/lib/
fi

# make sure we do have libncurses copied (needed by mkCDrec utilities)
for i in `find /usr/lib -name "libncurses.so.*"`; do
    if [ -f $i ]; then
       echo_log strip_copy_lib ${i} ${stagedir}${i}
       strip_copy_lib ${i} ${stagedir}${i}
    fi
done

# copy EVMS utilities libraries
for d in `find /lib/evms /usr/lib/evms -type d`; do
    if [ -d "$d" ]; then
        mkdir ${stagedir}${d}
        for i in `find $d -name "*.so*"`; do
            if [ -f "$i" ]; then
               echo_log strip_copy_lib ${i} ${stagedir}${i}
               strip_copy_lib ${i} ${stagedir}${i}
            fi
        done
    fi
done

# copy clamav virus libraries
if [ -d /var/lib/clamav ]; then
    mkdir -p ${stagedir}/var/lib/clamav
    for i in `find /var/lib/clamav -name "*.cvd"`; do
        if [ -f "$i" ]; then
           echo_log strip_copy_lib ${i} ${stagedir}${i}
           strip_copy_lib ${i} ${stagedir}${i}
        fi
    done
fi

# Check if we have /lib/ld-linux.so.2 copied (symlink in Config.sh is removed)
if [ ! -f ${stagedir}/lib/ld-linux.so.2 ]; then
   echo_log strip_copy_lib /lib/ld-linux.so.2 ${stagedir}/lib/ld-linux.so.2
   strip_copy_lib /lib/ld-linux.so.2 ${stagedir}/lib/ld-linux.so.2
fi

# ldconfig must be done prior to SYMLINKS.  SYMLINKS creates links to libs that
# don't exist yet, and ldconfig doesn't like that, so it removes them.
echo_log "++++++++++++++ ldconfig +++++++++++++"
echo_log "`/sbin/ldconfig -v -r ${stagedir}/`"
if [ $? -eq 1 ]; then
        error 1 "Oops. I guess the ramdisk is full: `df -kP $stagedir | tail -1`"
fi
}

Copy_terminfo () {
#^^^^^^^^^^^^^^^
# Create the necessary terminfo entries
echo_log "Copy some basic terminfo's to rootfs"
mkdir -p ${ROOTFS}/usr/share/terminfo/v
cp /usr/share/terminfo/v/vt*  ${ROOTFS}/usr/share/terminfo/v
mkdir -p ${ROOTFS}/usr/share/terminfo/l
cp /usr/share/terminfo/l/linux ${ROOTFS}/usr/share/terminfo/l
mkdir -p ${ROOTFS}/usr/share/terminfo/x
cp /usr/share/terminfo/x/xterm ${ROOTFS}/usr/share/terminfo/x
if [ -d /usr/share/misc ]; then
   cp -dpR /usr/share/misc/ ${ROOTFS}/usr/share/
fi
}

Copy_man_pages () {
#^^^^^^^^^^^^^
echo_log "Copy man pages listed in MAN_PAGES to rootfs"
for manpage in `echo ${MAN_PAGES}`
do
   man ${manpage} > /tmp/mantmp 2>/dev/null
   if [ $? -eq 0 ]; then
      ul -t dumb /tmp/mantmp | gzip -c > ${ROOTFS}/usr/man/${manpage}.gz
      if [ $? -eq 1 ]; then
        Fail "No Space left on ram disk!"
      fi
      echo_log "Found man page ${manpage}"
   fi
done
rm -f /tmp/mantmp
}

Copy_binaries () {
#^^^^^^^^^^^^^^^
# Copy binaries mentioned in [S]BIN_BINARIES to rootfs
echo_log "Copy binaries to rootfs"
cd ${ROOTFS}
for binary in `echo ${BINARIES}`
do
    targetbin=`which ${binary} 2>/dev/null` > /dev/null 2>&1
    if [ $? -eq 0 ]; then       # targetbin found
        
        if [ -x ${targetbin} ]; then
           # sanity check - did busybox/tinylogin already made a link?
           if [ -L .${targetbin} ]; then
             echo_log "WARNING: skip ${targetbin} - is a busybox link (${binary})"
             if echo ${binary} | egrep "(umount)" >/dev/null; then
                 echo "Overwriting umount with ${targetbin} anyway" | tee -a ${LOG}
                 rm .${targetbin}
                 echo_log strip_copy ${targetbin} .${targetbin}
                 strip_copy ${targetbin} .${targetbin}
             fi
           else
                #if [ ! -z `file ${targetbin} | grep shell >/dev/null` ]; then
                # foresee perl scripts too (future)
                if  `file ${targetbin} | egrep "(shell|perl)" >/dev/null`; then
                  echo_log cp ${targetbin} .${targetbin}
                  cp ${targetbin} .${targetbin}
                else
                  echo_log strip_copy ${targetbin} .${targetbin}
                  strip_copy ${targetbin} .${targetbin}
                fi # file check
           fi # -L check
        else
           echo "WARNING: ${targetbin} is not an executable (did not copy)" \
                | tee -a ${LOG}
        fi # -x targetbin check
    else
        echo "WARNING: ${binary} was not found.  Skipped." | tee -a ${LOG}
    fi # which check
done
# Copy bash version to rootfs/bin
Major_bash_ver=`echo $BASH_VERSION | cut -d"." -f 1`
if [ ${Major_bash_ver} -eq 1 ]; then
   targetbin=`which bash2 2>/dev/null`
else
   targetbin=`which bash 2>/dev/null`  || targetbin=`which bash2 2>/dev/null`
fi
echo_log strip_copy ${targetbin} ./bin/bash
strip_copy ${targetbin} ./bin/bash      # force bash2 to become bash (gdha)
if [ $? -eq 1 ]; then
        warn "bin/bash was NOT copied to the ram disk!"
fi
# add check for /bin/sh - rm /bin/sh as we link bash to sh later (gdha, 14 Oct)
[ -f ./bin/sh ] && rm -f ./bin/sh && echo "rm -f ./bin/sh" >> ${LOG}

# special treatment for insmod & friends depending on kernel_minor_nr
# Kernels < 2.5 need to use insmod.old instead of insmod (if existing)
for kmod in insmod modprobe depmod
do
 case ${kernel_minor_nr} in
    2|4)
       if [ -f /sbin/${kmod}.old ]; then
        echo_log strip_copy /sbin/${kmod}.old ${stagedir}/bin/${kmod}
        strip_copy /sbin/${kmod}.old ${stagedir}/bin/${kmod}
       elif [ -f /sbin/${kmod}.modutils ]; then # for Debian 3.1
        echo_log strip_copy /sbin/${kmod}.modutils ${stagedir}/bin/${kmod}
        strip_copy /sbin/${kmod}.modutils ${stagedir}/bin/${kmod}
       else
        echo_log strip_copy /sbin/${kmod} ${stagedir}/bin/${kmod}
        strip_copy /sbin/${kmod} ${stagedir}/bin/${kmod}
       fi
       ;;
      *)
       echo_log strip_copy /sbin/${kmod} ${stagedir}/bin/${kmod}
       strip_copy /sbin/${kmod} ${stagedir}/bin/${kmod}
       ;;
 esac
done

# Hereafter come to special cases such lvmiopversion (Debian 3.0) wrapper
# kludge. Need the output of command lvmiopversion to find real executables.
# FIXME
if [ -f /sbin/lvmiopversion ]; then
   echo "LVM: /sbin/lvmiopversion found: recopy lvm to rootfs/sbin" | tee -a ${LOG}
   rsync -a --force /etc/alternatives/lvm-default/* ${stagedir}/sbin
   cp -f /sbin/lvmiopversion ${stagedir}/sbin
fi

cd ${MKCDREC_DIR}
LIBDIR=
}

Copy_Perl_Environment () {
#####################
# Purpose is to add perl and its libraries to the rootfs
PERL_EXE=`which perl`
PERL_VERSION=`${PERL_EXE} -v | head -2 | tail -n 1 | awk '{print $4}' | sed -e 's/v//'
`
echo_log strip_copy ${PERL_EXE} ${stagedir}/${PERL_EXE}
strip_copy ${PERL_EXE} ${stagedir}/${PERL_EXE}
mkdir -p ${stagedir}/usr/lib/perl5
echo_log "Copy the /usr/lib/perl5/${PERL_VERSION} to ROOTFS"
cp -dpR /usr/lib/perl5/${PERL_VERSION} ${stagedir}/usr/lib/perl5
}

Make_cutstream () {
#^^^^^^^^^^^^^^^^
# Compile/install cutstream
cd ${CUTSTREAM_DIR}
echo_log "Compile/install cutstream"
make clean
#echo "#define MAXCDSIZE " ${MAXCDSIZE} >config.h
make >> ${LOG} 2>&1
cp cutstream ${MKCDREC_DIR}/bin || Fail "cutstream: compilation failed - check MAXCDSIZE in Config.sh"
cd ${MKCDREC_DIR}
}

Make_pastestream () {
#^^^^^^^^^^^^^^^^^^
# Compile/install pastestream
cd ${PASTESTREAM_DIR}
echo_log "Compile/install pastestream"
make >> ${LOG} 2>&1
echo_log strip_copy pastestream ${ROOTFS}/sbin/pastestream
strip_copy pastestream ${ROOTFS}/sbin/pastestream
cd ${MKCDREC_DIR}
}

Make_udhcp () {
#^^^^^^^^^^^^
# needed when FORCE_DHCP_SUPPORT=y
cd udhcp
echo "Compile/install udhcpc" | tee -a ${LOG}
make >> ${LOG} 2>&1
echo_log strip_copy udhcpc ${ROOTFS}/sbin/udhcpc
strip_copy udhcpc ${ROOTFS}/sbin/udhcpc
# config files are already on their proper place within mkCDrec
}

Make_isomd5 () {
#^^^^^^^^^^^^^
# compile/install check/implantisomd5
cd mediacheck
echo "compile/install check/implantisomd5" | tee -a ${LOG}
make >> ${LOG} 2>&1
echo_log strip_copy checkisomd5 ${ROOTFS}/sbin/checkisomd5
strip_copy checkisomd5 ${ROOTFS}/sbin/checkisomd5
echo_log cp checkisomd5 ${MKCDREC_DIR}/bin/checkisomd5
cp ${ROOTFS}/sbin/checkisomd5 ${MKCDREC_DIR}/bin/checkisomd5
echo_log strip_copy implantisomd5 ${MKCDREC_DIR}/bin/implantisomd5
strip_copy implantisomd5 ${MKCDREC_DIR}/bin/implantisomd5
cd ${MKCDREC_DIR}
}

Copy_pcmcia () {
#^^^^^^^^^^^^^
# Copy /etc/pcmcia/* to rootfs/etc
if [ ! -d /etc/pcmcia ]; then
        echo_log "No /etc/pcmcia directory found - skip..."
else
        echo_log "*** Copy /etc/pcmcia/* files to ROOTFS/etc ***"
        for d in `find /etc/pcmcia -type d`
        do
          mkdir -p ${ROOTFS}${d} 
        done
#### Following line by BNV. Do not copy directory
        for i in `find /etc/pcmcia ! -name "*.O" ! -type d`
#### Original:
#       for i in `find /etc/pcmcia ! -name "*.O"`
#### End BNV
        do
          cp ${i} ${ROOTFS}${i}
          echo_log "cp ${i} ${ROOTFS}${i}"
        done
fi
}

Copy_etc () {
#^^^^^^^^^^
# Copy files from /etc/* and/or $MKCDREC_DIR/etc/* to rootfs/etc
echo_log "Start filling up rootfs/etc directory..."

# RedHat has a non-standard rc.d/init.d layout
if [ -d /etc/rc.d/init.d ]; then
   cp -dpR /etc/rc.d/ ${ROOTFS}/etc/
   # (cd ${ROOTFS}/etc; ln -sf rc.d init.d)
   [ -d ${ROOTFS}/etc/init.d ] && rm -rf ${ROOTFS}/etc/init.d 
   (cd ${ROOTFS}/etc; ln -sf rc.d/init.d init.d)
   rcdtarget=${ROOTFS}/etc/rc.d
elif [ -d /etc/init.d ]; then
   cp -dpR /etc/init.d/ ${ROOTFS}/etc/
   (cd ${ROOTFS}/etc; ln -sf init.d rc.d)
   rcdtarget=${ROOTFS}/etc/init.d
fi

#
# Debian has some init.d support files in /lib/{init,lsb}
#
if [ -r /lib/lsb/init-functions ]; then
   mkdir -p ${ROOTFS}/lib/lsb
   cp -p /lib/lsb/init-functions ${ROOTFS}/lib/lsb
fi
if [ -d /lib/init ]; then
   mkdir -p ${ROOTFS}/lib
   cp -dpR /lib/init ${ROOTFS}/lib
   if grep -q egrep ${ROOTFS}/lib/init/vars.sh 2>/dev/null ; then
      # probably needs "egrep -w" which busybox does
      # not provide, therefore make it empty
      echo '# empty' > ${ROOTFS}/lib/init/vars.sh
   fi
fi

#
# Copy some canned files.  Note, we cannot just recursively
#  copy the ${MKCDREC_DIR}/etc directory because it contains
#  the rc.d directory, which may be a link on our system, so
#  We copy all the files in the etc directory, then copy the
#  subdirectories to the right place -- for rc.d it is ${rcdtarget}
#
cp -p ${MKCDREC_DIR}/etc/* ${ROOTFS}/etc/
cp -dpR ${MKCDREC_DIR}/etc/rc.d/*  ${rcdtarget}
cp -dpR ${MKCDREC_DIR}/etc/pam.d/ ${ROOTFS}/etc/
[ -f ${ROOTFS}/etc/rc.d/rc.local ] && mv ${ROOTFS}/etc/rc.d/rc.local \
	${ROOTFS}/etc/rc.d/rc.local.orig
# Debian rc.local is not usable
[ -f /etc/debian_version ] && [ -f ${ROOTFS}/etc/rc.d/rc.local.orig ] && \
	rm -f ${ROOTFS}/etc/rc.d/rc.local.orig
( cd ${ROOTFS}/etc/rc.d/; ln -s flavors/rc.${INIT_FLAVOR} rc.local )
[ -f ${ROOTFS}/etc/rc.d/rc.local.orig ] && \
	cat ${ROOTFS}/etc/rc.d/rc.local.orig >> ${ROOTFS}/etc/rc.d/rc.local
cat /dev/null > ${ROOTFS}/etc/rc.d/rc.inits
chmod 755 ${ROOTFS}/etc/rc.d/rc.inits
for i in $INITS; do
   if [ -f $i ]; then
      echo_log "`cp -v $i ${rcdtarget}`"
      echo_log "echo $i start >> ${rcdtarget}/rc.inits"
      case "$i" in
         *udev*)
	    # CHW: udev might be already running, thus killall
	    echo 'killall udevd 2>/dev/null' >> ${rcdtarget}/rc.inits
	    ;;
      esac
      echo "[ -x $i ] && $i start" >> ${rcdtarget}/rc.inits
   else 
      echo "WARNING: $i was not found. Skipped." | tee -a ${LOG}
   fi
done

# Debian 4.0: need to fix .../etc/init.d/udev script for cp
if [ -r ${rcdtarget}/udev ]; then
   perl -pi -e 's/cp.*--archive.*--update/cp -a/g' ${rcdtarget}/udev
   perl -pi -e 's/cp.*--archive/cp -a/g' ${rcdtarget}/udev
fi

cd /etc
for fi in $ETC_FILES
do
   if [ `dirname ${fi}` != . ]; then
      mkdir -p ${ROOTFS}/etc/`dirname ${fi}` 2>/dev/null
   fi
   if [ -f ${fi} ]; then
      echo_log "cp ${fi} ${ROOTFS}/etc/`dirname ${fi}`"
      cp ${fi} ${ROOTFS}/etc/`dirname ${fi}`
   fi
done

if [ ! -f /etc/HOSTNAME ]; then
   ##cat /proc/sys/kernel/hostname > ${ROOTFS}/etc/HOSTNAME
   uname -n > ${ROOTFS}/etc/HOSTNAME
fi
cat > ${MKCDREC_DIR}/etc/fstab <<EOF
/dev/ram1       /       ${ROOT_FS}      defaults        1 1
proc            /proc   proc    defaults        0 0
EOF
# recopy and append /etc/passwd and /etc/shadow files
cp -fp  /etc/passwd ${ROOTFS}/etc/passwd
cat ${MKCDREC_DIR}/etc/passwd >> ${ROOTFS}/etc/passwd
cp -fp  /etc/shadow ${ROOTFS}/etc/shadow
cat ${MKCDREC_DIR}/etc/shadow >> ${ROOTFS}/etc/shadow
chmod 600 ${ROOTFS}/etc/shadow
chmod 644 ${ROOTFS}/etc/passwd
# we create a recovery directory under rootfs/etc and put stuff in it usefull
# in case of emergency (such as a disaster recover)
echo_log "etc/recovery directory needed for disaster recovery"
mkdir -p ${ROOTFS}/etc/recovery 2>/dev/null

# we dump out current keymap into our recovery dir (rc.sysinit will get it)
dumpkeys | gzip > ${ROOTFS}/etc/recovery/kbd.map.gz
if [ -f /etc/termcap ]; then
   cp -fp /etc/termcap ${ROOTFS}/etc/
fi

# SuSE 10.1
if [ -f /etc/rc.status ]; then
   cp -fp /etc/rc.status ${ROOTFS}/etc/
fi

# copy the whole sysconfig directory
if [ -d /etc/sysconfig ]; then
   rm -rf ${ROOTFS}/etc/sysconfig
   cp -dpR /etc/sysconfig/ ${ROOTFS}/etc/
fi
# copy also the locale en_US.UTF-8
if [ -d /usr/share/locale/en_US ]; then
   mkdir -p ${ROOTFS}/usr/share/locale/en_US
   cp -dpR /usr/share/locale/en_US ${ROOTFS}/usr/share/locale
fi
#if [ -d /usr/share/X11/locale/en_US.UTF-8 ]; then
#   mkdir -p ${ROOTFS}/usr/share/X11/locale
#   cp -dpR /usr/share/X11/locale/en_US.UTF-8  ${ROOTFS}/usr/share/X11/locale
#fi

# comment out HWADDR in any ifcfg-eth* file, otherwise ifconfig won't start
for i in `ls ${ROOTFS}/etc/sysconfig/network*/ifcfg-eth*`
do
  grep ^HWADDR $i >/dev/null 2>&1
  if [ $? -eq 0 ]; then
     sed -e 's/HWADDR/#HWADDR/' < $i > /tmp/temp.$$
     mv -f /tmp/temp.$$ $i
     echo_log "Commented the HWADDR line in $i"
  fi
done

# if serial console is used change the inittab file accordingly
# uncomment the correct line (ttyS0 or ttyS1) and fill in correct baudrate
# if SERIAL=ttyS0 on IA64 platform then the LAN console is used (do not activate
# the ttyS0 in inittab otherwise console and ttyS0 have a login conflict)
if [ x${BOOTARCH} = xia64 ]; then
        : # do not activate ttyS0 in /etc/inittab
else
 if [ ! -z "${SERIAL}" ]; then
 cat ${ROOTFS}/etc/inittab | sed -e 's/#'${SERIAL}'//'  \
    > ${ROOTFS}/etc/inittab
 cat ${ROOTFS}/etc/inittab | sed -e 's/BAUDRATE/'${BAUDRATE}'/'  \
    > ${ROOTFS}/etc/inittab
 fi
fi

# SF bug report 1273933 by lizard
if [ -f /lib/modules/modprobe.conf ]; then
   cp /lib/modules/modprobe.conf ${ROOTFS}/lib/modules/
fi
cd ${MKCDREC_DIR}
}

Copy_dev () {
#^^^^^^^^^^
echo_log "Copy /dev/* to rootfs"
rmdir ${ROOTFS}/dev # fixes a 'no more space' issue (Stephen Farrugia)
mkdir -p ${ROOTFS}/dev # better to mkdir it again (Christian Werner)
#cp -dpR /dev ${ROOTFS}
# fix for /dev/shm massive usage by SAP - fix of Rainer Anschober
echo rsync -a --exclude dev/shm/* /dev ${ROOTFS} >> ${LOG}
rsync -a --exclude dev/shm/* /dev ${ROOTFS}
# 22/11/2000: gdha /dev/ram trouble (should be ram0 instead of ram1)
cd ${ROOTFS}/dev
rm -f ram
ln -s ram0 ram
# Add some block devices for UML
mknod --mode=660 ubd0 b 98 0
mknod --mode=660 ubd1 b 98 16
mknod --mode=660 ubd2 b 98 32
mknod --mode=660 ubd3 b 98 48

ps ax | grep -i udev | grep -v grep >/dev/null 2>&1
if [ $? -eq 0 ]; then
  # udev is running - create some spare devices for the CD
  echo_log "Warning: udev is active. Create some extra devices."
  [ "${MAKEDEV}" = "/sbin/makedev" ] && MAKEDEV="/sbin/makedev ."
  mknod -m 0660 initrd b 1 250
  chown root.root initrd
  ${MAKEDEV} scd >/dev/null 2>&1
  ${MAKEDEV} sda sdb sdc sdd >/dev/null 2>&1
  ${MAKEDEV} hda hdb hdc hdd hde hdf hdg >/dev/null 2>&1
  ${MAKEDEV} ram >/dev/null 2>&1
  ${MAKEDEV} mem >/dev/null 2>&1
  ${MAKEDEV} kmem >/dev/null 2>&1
  ${MAKEDEV} console >/dev/null 2>&1
  ${MAKEDEV} ttyS0 >/dev/null 2>&1
  ${MAKEDEV} null >/dev/null 2>&1
  ${MAKEDEV} zero >/dev/null 2>&1
fi

cd ${MKCDREC_DIR}
}

###################
# Added 09/May/2006 by Schlomo Schapiro
###################
Make_nsr () {
if [ ! -d "${NSR_ROOT_DIR}" ] ; then
        echo "Oops ! You defined NSR_RESTORE=\"y\" in Config.sh, but ${NSR_ROOT_DIR} does not exist." | tee -a ${LOG}
        echo "Warning: Skipping the Legato Networker setup phase." | tee -a ${LOG}
        return
fi
echo_log "Adding files for Legato Networker backup/restore system..."
for lnf in ${NSR_FILES}
do
   if [ `dirname ${lnf}` != . ]; then
        mkdir -p ${ROOTFS}`dirname ${lnf}`
   else
     echo "** WARNING ** :: No directory found for file ${lnf}!" | tee -a ${LOG}
   fi
   echo_log "cp ${lnf} ${ROOTFS}`dirname ${lnf}`"
   cp ${lnf} ${ROOTFS}`dirname ${lnf}`
done
echo_log "cp ${MKCDREC_DIR}/contributions/nsr-restore.sh ${ROOTFS}/etc/recovery/"
cp ${MKCDREC_DIR}/contributions/nsr-restore.sh ${ROOTFS}/etc/recovery/
savefs -p 2>&1 | awk -F '(=|,)' '/path/ { printf("%s ",$2) }' >${ROOTFS}/etc/recovery/nsr_paths.txt
echo "Legato Networker will recover these filesystems: $(cat ${ROOTFS}/etc/recovery/nsr_paths.txt)" | tee -a ${LOG}
}
#

###################
# Added 30/Dec/2003 -- Chris Strasburg
###################
Make_tsm () {
#
# Copy files necessary for tivoli tsm to function
echo_log "Adding files for tivoli tsm backup/restore system..."
for tf in ${TSM_FILES}
do
        if [ `dirname ${tf}` != . ]; then
                mkdir -p ${ROOTFS}`dirname ${tf}`
        else
                echo "** WARNING ** :: No directory found for file ${tf}!" | tee -a ${LOG}
        fi
        echo_log "cp ${tf} ${ROOTFS}`dirname ${tf}`"
        cp ${tf} ${ROOTFS}`dirname ${tf}`
done
echo_log "cp ${MKCDREC_DIR}/contributions/tsm-restore.sh ${ROOTFS}/etc/recovery/"
cp ${MKCDREC_DIR}/contributions/tsm-restore.sh ${ROOTFS}/etc/recovery/
}
#################

# Module sponsored by Hewlett-Packard Belgium
Make_Data_Protector () {
if [ ! -d ${DP_ROOT_DIR} ]; then
   echo "Oops! You defined DP_RESTORE=\"y\" in Config.sh, but ${DP_ROOT_DIR} does not exist." | tee -a ${LOG}
   echo "Warning: skipping the Data Protector setup phase." | tee -a ${LOG}
   rm -f ${ROOTFS}/etc/recovery/Backup_made_with_DP
   return
fi
echo_log "Adding files and libraries for HP Openview Data Protector."
for dpf in ${DP_FILES}
do
        if [ `dirname ${dpf}` != . ]; then
                mkdir -p ${ROOTFS}`dirname ${dpf}`
        else
                echo "** WARNING ** :: No directory found for file ${dpf}!" | tee -a ${LOG}
        fi
        echo_log "cp ${dpf} ${ROOTFS}`dirname ${dpf}`"
        cp ${dpf} ${ROOTFS}`dirname ${dpf}`
done
# Possible we need to create rootfs/etc/rc.d/rc.omni file (for inet)?
echo "${DP_DATALIST_NAME}" > ${ROOTFS}/etc/recovery/DP_DATALIST_NAME
cp ${MKCDREC_DIR}/contributions/dp-restore.sh ${ROOTFS}/etc/recovery/
}


#################
Make_tinylogin () {
#^^^^^^^^^^^^^^^^
# Compile & install tinylogin
cd ${TINYLOGIN_DIR}
echo_log "*** Tinylogin compilation/installation started ***"
if [ -f Makefile ]; then
   make PREFIX="${ROOTFS}" all >> ${LOG} 2>&1
   make PREFIX="${ROOTFS}" install >> ${LOG} 2>&1
else
   ./install.sh ${ROOTFS}
fi
cd ${MKCDREC_DIR}
}

Make_busybox () {
#^^^^^^^^^^^
# Compile and install busybox
cd ${BUSYBOX_DIR}
echo "*** Busybox compilation started. This can take some time. ***" | tee -a ${LOG}

# .config.bb is our pre-configured .config file for busybox-1.x
if [ -f ${MKCDREC_DIR}/.config.bb ]; then
   # make distclean would remove .config file (to release new mkcdrec version)
   echo_log "Busybox: use preconfigured .config file: ../.config.bb"
   echo_log "`cp -v ${MKCDREC_DIR}/.config.bb .config`"
fi

if [ -f Makefile ]; then
   make PREFIX="${ROOTFS}" install >> ${LOG} 2>&1
fi

# add check to see whether busybox was compiled
if [ ! -x ./busybox ]; then
   error 1 "Compilation error occured with busybox, please check mkcdrec.log for further details."
else
	applets/install.sh ${ROOTFS} --symlinks
	echo "Copied busybox to ${ROOTFS}/bin/busybox" | tee -a ${LOG}
fi

cd ${MKCDREC_DIR}

# check if ROOTFS/bin/tar exists? If positive, then remove it - will use gnutar
if [ -L ${ROOTFS}/bin/tar ]; then
        rm -f ${ROOTFS}/bin/tar
fi
if [ -L ${ROOTFS}/sbin/modprobe ]; then
        rm -f ${ROOTFS}/sbin/modprobe
fi

# make busybox SUID to root (gdha, 20/Aug/2008)
chmod u+s ${ROOTFS}/bin/busybox
}


Init_rootfs () {
#^^^^^^^^^^^^^
# Make the initial necessary root directories in our rootfs
# we need to restore which dirs existed in / (make a script)
# let's make the recovery dir now
mkdir -p ${ROOTFS}/etc/recovery 2>/dev/null

# Make all the dirs under your current / file system
echo_log "Initial population of the rootfs"
echo_log "Create mkdirs.sh script for the creation of mountpoints"
for dir in `ls -1 /`
do
        if [ -d /${dir} ]; then
                mkdir ${ROOTFS}/${dir} 2>/dev/null
                # Make mkdirs.sh script needed by start-restore.sh
                echo "mkdir -p ${dir} >/dev/null 2>&1" >> ${ROOTFS}/etc/recovery/mkdirs.sh
        fi
done
# create also mounted excluded mountpoints (F. Van Liedekerke)
for dir in `mount | egrep -v "devfs|devpts|${Dev}" | awk '{print $3}' | cut -c2-`
     do
          [ "${dir}" = "" ] && continue
          echo "mkdir -p ${dir} >/dev/null 2>&1" >> ${ROOTFS}/etc/recovery/mkdirs.sh
     done # end of for excluded mountpoints
# create all listed mountpoint from the /etc/fstab file (deeper nested mntpt)
echo mkdir -p `cat /etc/fstab | egrep "^[^#]" | awk '{print $2}' | egrep -v "devfs|proc|swap|pts" | cut -c2-` >> ${ROOTFS}/etc/recovery/mkdirs.sh
# extra's needed for mountpoints under /mnt which is listed in EXCLUDE_LIST
echo "mkdir -p mnt/cdrom mnt/disk mnt/floppy mnt/cdrom2 mnt/cdrom1 mnt/res mnt/windows" >> ${ROOTFS}/etc/recovery/mkdirs.sh
# create separation dir for sshd
echo "mkdir -p var/lib/empty" >> ${ROOTFS}/etc/recovery/mkdirs.sh
# create /dev/shm when devfs is not used (bug #570469)
if [ ! -c /dev/.devfsd ]; then
   grep tmpfs /etc/fstab >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo "mkdir -p dev/shm" >> ${ROOTFS}/etc/recovery/mkdirs.sh
      echo "chmod 1777 dev/shm" >> ${ROOTFS}/etc/recovery/mkdirs.sh
   fi
fi
# always make sure a /tmp exists with proper permission (gdha, 25/07/2002)
echo "mkdir -p tmp ; chmod 1777 tmp" >> ${ROOTFS}/etc/recovery/mkdirs.sh
chmod +x ${ROOTFS}/etc/recovery/mkdirs.sh

cd ${ROOTFS}

echo_log "mkdir -p ${MKDIR_LIST}"
mkdir -p ${MKDIR_LIST} || Fail "rd-base.sh: Init_rootfs: mkdir $MKDIR_LIST failed"

echo_log "Copy ${MKCDREC_DIR}/usr to ${ROOTFS} ..."
echo_log "${MKCDREC_DIR}/usr contains man, share and bin dirs."
cp -dpR ${MKCDREC_DIR}/usr  ${ROOTFS}

ln -s var/log var/adm
rmdir ${ROOTFS}/lost+found 2>/dev/null
echo "The ROOTFS/usr directory layout:" | tee -a ${LOG}
ls -l ${ROOTFS}/usr | tee -a ${LOG}
cd ${MKCDREC_DIR}
}

Make_rootfs () {
#^^^^^^^^^^^^^
# make a rootfs in ram
if [ x$MODE = xsuperrescue ]; then
   RAMDISK_SIZE=64
fi
echo_log "Creating an empty file 'rd-base.img' to hold the filesystem"
dd if=/dev/zero of=rd-base.img bs=1k count=$((RAMDISK_SIZE*1024))
case ${ROOT_FS} in
     ext2) /sbin/mkfs.ext2 -Fq rd-base.img  -m 0 -N $((RAMDISK_SIZE*1024)) > /dev/null 2>&1 || Fail "Failed to make root filesystem of type ${ROOT_FS}"
	   echo "Doing a fsck on rd-base.img..." | tee -a ${LOG}
	   /sbin/e2fsck -y -v rd-base.img | tee -a ${LOG}
	   ;;
     ext3|ext4) /sbin/mkfs.ext2 -j -Fq rd-base.img  -m 0 -N $((RAMDISK_SIZE*1024)) > /dev/null 2>&1 || Fail "Failed to make root filesystem of type ${ROOT_FS}" ;;
     reiserfs) /sbin/mkreiserfs -fq rd-base.img > /dev/null 2>&1 || Fail "Failed to make root filesystem of type ${ROOT_FS}" ;;
     xfs) /sbin/mkfs.xfs rd-base.img > /dev/null 2>&1 || Fail "Failed to make root filesystem of type ${ROOT_FS}" ;;
     minix) /sbin/mkfs.minix rd-base.img -i $((RAMDISK_SIZE*1024)) > /dev/null 2>&1 || Fail "Failed to make root filesystem of type ${ROOT_FS}" ;;
     ramfs) echo_log "Building rootfs using type ${ROOT_FS}" ;;
     *) Fail "Don't know how to build a root filesystem of type $ROOT_FS." ;;
esac

echo_log "Root filesystem successfully made with type ${ROOT_FS}"
case ${ROOT_FS} in
     ramfs) rm -rf ${ROOTFS} # cleanup old traces
	mkdir -p --mode=777 ${ROOTFS} ;;
     *) echo_log "Mounting the rootfs on ${ROOTFS}"
	mkdir -p --mode=777 ${ROOTFS} 2>/dev/null
	/bin/mount -o loop rd-base.img ${ROOTFS}
	if [ $? -eq 1 ]; then
	  error 1 "The loopback mount of rd-base.img failed. Please investigate your linux kernel on loopback device capabilities."
	fi
	#rmdir ${ROOTFS}/lost+found 2>/dev/null
	;;
esac
}

List_loadable_modules () {
#^^^^^^^^^^^^^^^^^^^^^^^
# first we gonna create the necessary subdirectories under lib/modules
echo_log "Copy loadable modules to rootfs..."

#### following line by BNV, some modules may be behind a symlink,
#### which is the case for Debian kernel 2.2.17 and alsa 0.5:
#### gdha - 11/07/2001 - Mdk break its neck on next line with 2.4.x kernels
#### default is NOT to follow symlinks (until a better solution is given)
#for DIR in `find /lib/modules/${Kernel_Version}/ -type d -follow`
#### original:
for DIR in `find /lib/modules/${Kernel_Version}/ -type d`
#### end BNV - gdha
do
        if [ -d ${DIR} ]; then
                echo_log "mkdir -p ${ROOTFS}${DIR}"
                mkdir -p ${ROOTFS}${DIR} 2>/dev/null
        fi
done

# check the current loaded modules and copy these to our ROOTFS
for mod in `cat /proc/modules | cut -d ' ' -f 1`
do
    #### following lines by BNV, some modules may be behind a symlink:
    # Redhat/Mdk have problems with following symlinks (gdha)
    #fmod=`find /lib/modules/${Kernel_Version}/ -name "${mod}.o*" -follow`
    # "head -n 1" solves the 3cxxx.o problem not being copied! gdha
    if [ ${kernel_minor_nr} -ge 6 ]; then
     fmod=`find /lib/modules/${Kernel_Version}/ -name "${mod}.ko*" | head -n 1`
    else
     fmod=`find /lib/modules/${Kernel_Version}/ -name "${mod}.*o*" | head -n 1`
    fi
    # this line help to solve problem with uhci-hcd whose real name is uhci_hcd
    if [ -z ${fmod} ]; then
        mod=`echo ${mod} | sed -e 's/_/-/g'`
        fmod=`find /lib/modules/${Kernel_Version}/ -name "${mod}.*o*" | head -n 1`
    fi
    if [ ! -z ${fmod} ]; then
       echo_log "Copying ${fmod} to ${ROOTFS}${fmod}"
       echo_log "`cp -v ${fmod} ${ROOTFS}${fmod}`"
    fi
done

# check if loop is available as module?
modloop=`find /lib/modules/${Kernel_Version}/ -name "loop.*o*"`
if [ -f "${modloop}" ]; then
        echo_log "Copy module loop to ${ROOTFS}${modloop}"
        echo_log "`cp -v ${modloop} ${ROOTFS}${modloop}`"
fi

# SCSI devices (as defined in Config.sh) which we certaintly need for this
# system (think on tapes, SCSI disks, cdroms,...)
for mod in `echo ${SCSI_MODULES} ${OTHER_MODULES} ${NETWORK_MODULES}`
do
        fmod=`find /lib/modules/${Kernel_Version}/ -name "${mod}.*o*"`
        if [ ! -z "${fmod}" ]; then
                cp ${fmod} ${ROOTFS}/${fmod}
                echo_log "Copying ${mod} to ${ROOTFS}/${fmod}"
        fi
done

if [ -f /lib/modules/${Kernel_Version}/modules.dep ]; then
   echo_log cp /lib/modules/${Kernel_Version}/modules.dep ${ROOTFS}/lib/modules/${Kernel_Version}/
   cp /lib/modules/${Kernel_Version}/modules.dep ${ROOTFS}/lib/modules/${Kernel_Version}/
fi

# New option: EXCLUDE_MODULES: now we will remove these modules again from
# mkCDrec in order to avoid problems when restoring to e.g. SAN based storage
mkdir -p ${ROOTFS}/lib/modules/${Kernel_Version}/.hidden
for mod in `echo ${EXCLUDE_MODULES}`
do
        fmod=`find  ${ROOTFS}/lib/modules/${Kernel_Version}/ -name "${mod}.*o*"`
        if [ ! -z "${fmod}" ]; then
           mv -f ${fmod} ${ROOTFS}/lib/modules/${Kernel_Version}/.hidden
           echo "WARNING: module ${fmod} moved to /lib/modules/${Kernel_Version}/.hidden on CD." | tee -a ${LOG} 
        fi
done
}

Check_for_sshd () {
#^^^^^^^^^^^^^^^^
# add SSHD support to mkCDrec CD (useful for remote invention with ssh)
SSHD_CONFIG=`find /etc -name sshd_config 2>/dev/null`
if [ ! -z "${SSHD_CONFIG}" ]; then
   mkdir -p ${ROOTFS}/etc/ssh
   echo_log "`cp -v  /etc/ssh/* ${ROOTFS}/etc/ssh`"
   # make it possible to sftp to a system in need
   mkdir -p ${ROOTFS}/usr/libexec/openssh
   if [ -f /usr/libexec/openssh/sftp-server ]; then
      echo_log strip_copy /usr/libexec/openssh/sftp-server ${ROOTFS}/usr/libexec/openssh/sftp-server
      strip_copy /usr/libexec/openssh/sftp-server ${ROOTFS}/usr/libexec/openssh/sftp-server
   fi
fi

}

Check_kernel_for_rd () {
#^^^^^^^^^^^^^^^^^^^^^
# Is devfsd running? Need to know for root=/dev/ram0 or root=/dev/rd/0
ls -b /dev/.devfsd >/dev/null 2>&1   # empty when no DEVFS active
DEVFSD=$?
if [ x${DEVFS} = x0 ] || [ x${DEVFSD} = 1 ]; then
   # devfsd not running
   RAM0=/dev/ram0
else
   RAM0=/dev/rd/0
fi
dd if=/dev/zero of=${RAM0} count=1 > /dev/null 2>&1
if [ $? -eq 1 ]; then
        echo "Please recompile kernel and enable options:
Loopback device support (N/m/y/?) y or m
Ram disk support (N/m/y/?) y
Initial Ram disk (initrd) support (N/y/?) y

After a successful rebuild try again ;-)" | tee -a ${LOG}
error 1 "Recompile Linux kernel with above options included."
fi

# gdha (17/05/2001): force a 'modprobe loop' to be sure the loop module
# is triggered (harmless ;-)
modprobe -q loop >/dev/null 2>&1

}

Gather_info () {
#^^^^^^^^^^^^^
#Allow user to identify kernel version when manually specifying LINUX_KERNEL
Kernel_Version=${LINUX_VERSION:-`uname -r`}
Kernel_Modules="/lib/modules/${Kernel_Version}"
if [ ! -d "$Kernel_Modules" ];then
   BOOT_FILE_NAME=`cat /proc/cmdline | sed -e 's/^.*BOOT_FILE=//' | sed -e 's/ .*$//'`
   if [ -L "$BOOT_FILE_NAME" ]; then
      # Translate the boot file symlink to a real filename (Debian)
      BOOT_FILE_NAME=`ls -L "$BOOT_FILE_NAME" | sed 's/^.* -> //'`
   fi
   # at this point is e.g. BOOT_FILE_NAME=/boot/vmlinuz-2.4.7
   # usual the kernel name starts with vmlin, but it could also be bzImage
   KERNEL_NAME=`echo $BOOT_FILE_NAME| cut -d/ -f2-|cut -d/ -f2-|cut -d/ -f2-`
   BOOT_DIR=`echo $BOOT_FILE_NAME | sed -e 's/'${KERNEL_NAME}'.*//'`
   grep init_modules ${BOOT_DIR}/System.map-${LINUX_VERSION} >/dev/null 2>&1
   if [ $? -eq 1 ]; then
        error 1 "Kernel Modules directory does not exist: $Kernel_Modules"
   fi
fi
${MKISOFS} 2>/dev/null
MKISOERR=$?
if [ ${MKISOERR} -gt 1 ]
then
        echo "Required ${MKISOFS} not found." | tee -a ${LOG}
        echo "I'll continue, and will use my mkisofs instead" | tee -a ${LOG}
fi

# verify when BURNCDR=y if SCSIDEVICE is really a CD-writer - else exit
if [ "${BURNCDR}" = "y" ] && [ ${DVD_Drive} -eq 0 ]; then
   ${CDRECORD} -atip dev=${SCSIDEVICE} 2>/dev/null | egrep '(CD-R|DVD-R)' > /dev/null
   if [ $? -ne 0 ]; then
      error 1 "Did not find a CD/DVD-writer, run \"make test\" to find out why"
   fi
fi

# check our current eth* dev in use (if any)
if [ "${FORCE_DHCP_SUPPORT}" = "y" ] || [ "${FORCE_DHCP_SUPPORT}" = "Y" ]; then
   echo_log "Force DHCP Support in mkCDrec"
   for mod in `echo  ${NETWORK_MODULES}`; do
       echo "modprobe -q ${mod}" >> ${MKCDREC_DIR}/etc/rc.d/rc.network
   done
   echo "/sbin/udhcpc" >> ${MKCDREC_DIR}/etc/rc.d/rc.network
else
echo_log "Gathering your current network configuration into rc.network"
ifconfig | grep eth 2>&1 >/dev/null
have_eth=$?
if [ $have_eth -eq 0 ]; # OK, eth was found
then
   for mod in `echo  ${NETWORK_MODULES}`; do
       echo "modprobe -q ${mod}" >> ${MKCDREC_DIR}/etc/rc.d/rc.network
   done
   for nr in 0 1 2 3 4 5 6
     do
        ifconfig | grep eth${nr} 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
           # sorry, no IPv6 yet (submit the code - thx)
           ifc=`ifconfig eth${nr} | grep -v inet6 | grep inet`  
           ADDR=`echo ${ifc} | cut -f 2 -d ' ' | cut -f 2 -d ':'`
           BROADCAST=`echo ${ifc} | cut -f 3 -d ' ' | cut -f 2 -d ':'`  
           NETMASK=`echo ${ifc} | cut -f 4 -d ' ' | cut -f 2 -d ':'`
           # added by Schlomo Schapiro 2006-05-11
           # create correct ifconfig calls for interfaces without address
           if [ "$ADDR" ] ; then
              echo "/sbin/ifconfig eth${nr} ${ADDR} broadcast ${BROADCAST} netmask ${NETMASK} up" >> ${MKCDREC_DIR}/etc/rc.d/rc.network
              echo_log "/sbin/ifconfig eth${nr} ${ADDR} broadcast ${BROADCAST} netmask ${NETMASK} up"
           else
              echo "/sbin/ifconfig eth${nr} up" >> ${MKCDREC_DIR}/etc/rc.d/rc.network
              echo_log "/sbin/ifconfig eth${nr} up"
           fi
        fi
     done # of for 0 1 2 3

     # added by Schlomo Schapiro 2006-05-11
     ## check for and configure bonding devices
     for if in bond{0,1,2} ; do
         if [ -r /proc/net/bonding/$if ] ; then
            # create array of addr,broadcast,netmask
            ipconfig=($(ifconfig $if | grep inet\ | tr -s " \t" : | cut -d : -f 4,6,8 | tr : " "))
            echo "modprobe -o $if bonding miimon=100 mode=1 use_carrier=0"  >> ${MKCDREC_DIR}/etc/rc.d/rc.network
            echo "/sbin/ifconfig $if ${ipconfig[0]} broadcast ${ipconfig[1]} netmask ${ipconfig[2]} up" | tee -a ${MKCDREC_DIR}/etc/rc.d/rc.network ${LOG}
            # enslave slave interfaces which we read from the /proc status file
            ifslaves=($(cat /proc/net/bonding/${if} | grep "Slave Interface:" | cut -d : -f 2))
            echo "ifenslave $if ${ifslaves[*]}" | tee -a ${MKCDREC_DIR}/etc/rc.d/rc.network ${LOG}
         fi
     done # for bond{0,1,2}

     netstat -rn | grep "^0.0.0.0"  2>&1 >/dev/null
     if [ $? -eq 0 ]; then
        GW=`netstat -rn | grep "^0.0.0.0"| awk '{print $2}'`
        echo "/sbin/route add default gw ${GW} metric 1" >> ${MKCDREC_DIR}/etc/rc.d/rc.network
        echo_log "/sbin/route add default gw ${GW} metric 1"
     fi
fi # have_eth
fi # FORCE_DHCP_SUPPORT
[ -f ${MKCDREC_DIR}/etc/rc.d/rc.network ] && chmod 755 ${MKCDREC_DIR}/etc/rc.d/rc.network

# now we will enable usb devices
echo_log "gathering usb configuration"
rm -f ${MKCDREC_DIR}/etc/rc.d/rc.usb
for i in ${USB_MODULES}
do
        echo "modprobe -q $i" >> ${MKCDREC_DIR}/etc/rc.d/rc.usb
        echo_log "modprobe -q $i"
done
echo "lsmod " >> ${MKCDREC_DIR}/etc/rc.d/rc.usb

chmod 755 ${MKCDREC_DIR}/etc/rc.d/rc.usb
}

Check_which_command () {
###################
echo_log "Checking which command:"
which=`whereis which | awk '{print $2}'`
echo_log ${which}
if [ -z ${which} ]; then
   alias which='type -p'
   echo_log "which: using alias instead"
fi
}

#============#
# MAIN body  #
#============#

MODE=interactive
ARG=""

USAGE="[OPTION]...

  -m mode  mode ${0##*/} should run in            [ $MODE ]
  -a arg   argument for path/device/USB-KEY modes [ no default ]"

while :;
        do case "$1" in
                -h | "-?" )
                        echo -e usage: ${0##*/} "$USAGE" >&2
                        exit 1 ;;
                -m )
                        MODE=$2
                        shift ;;
                -a )
                        ARG=$2
                        shift ;;
                * )
                        break ;;
        esac
        shift
done

if [ x$MODE != xinteractive \
  -a x$MODE != xrescue \
  -a x$MODE != xsuperrescue \
  -a x$MODE != xCD-ROM \
  -a x$MODE != xISO-ONLY \
  -a x$MODE != xpath \
  -a x$MODE != xOBDR \
  -a x$MODE != xUSB-KEY \
  -a x$MODE != xdevice ]; then
        echo -e usage: ${0##*/} "$USAGE" >&2
        exit 1
fi

if [ x$MODE = xpath ] && [ -z $ARG ]; then
        echo -e usage: ${0##*/} "$USAGE" >&2
        exit 1
fi

if [ x$MODE = xUSB-KEY ] && [ -z $ARG ]; then
        echo -e usage: ${0##*/} "$USAGE" >&2
        exit 1
fi

# preserve original umask settings and force ours during make rd-base making
UMASK_RESTORE="`umask -p`"; umask 022

# add title
clear
#color white black
print "\n\n${c_higreen}Make CD-ROM recovery (mkCDrec ${VERSION})${c_sel} by Gratien D'haese${c_end}\n"

# Save old mkcdrec.log for sanity ;-)
if [ -f ${LOG} ]; then
        mv -f ${LOG} ${LOG}.old
fi

# Write start time to our log file $LOG (new log file)
echo "mkCDrec started on `date`" > ${LOG}

# We need to be root (uid=0) or equivalent
if [ `id --user` -ne 0 ]; then
        echo "Script $0 needs ROOT priviledges!" | tee -a ${LOG}
        exit 1
fi

# cleanup the tmp dir
rm -rf ${TMP_DIR}/*
echo ${MODE} > ${TMP_DIR}/MODE  # so other scripts can pick it up

# Allow user to identify kernel version when manually specifying LINUX_KERNEL
if [ -z "$LINUX_VERSION" ];then
        Kernel_Version=`uname -r`
else
        Kernel_Version=${LINUX_VERSION:-`uname -r`}
fi

# Kernels 2.2.x will return 2, kernel 2.4.x returns 4
kernel_minor_nr=`echo ${Kernel_Version} | cut -d. -f2`

# Is ramdisk enabled in this kernel?
Check_kernel_for_rd

if [ x$MODE = xrescue ]; then
        print "No backup will be made - rescue only CD\n"
        Show_mount_output       # to make tmp/Backup.MntPoints file
elif [ x$MODE = xsuperrescue ]; then
        print "***** SuperRescue Mode *****\n"
        print "======= Experimental =======\n\n"
        Show_mount_output       # to make tmp/Backup.MntPoints file
elif [ x$MODE = xCD-ROM ]; then
        print "Backup will reside on CDR\n"
        DESTINATION_PATH=${ISOFS_DIR}
        # write our DESTINATION_PATH into a file (tar-it.sh will pick it up)
        echo ${DESTINATION_PATH} > ${TMP_DIR}/DESTINATION_PATH
        touch ${TMP_DIR}/Backups_on_cd  # a stupid FLAG file for tar-it.sh
        Show_mount_output       # to make tmp/Backup.MntPoints file
elif [ x$MODE = xISO-ONLY ]; then
	print "Backup in ISO filesystem\n"
	DESTINATION_PATH=${ISOFS_DIR}
	# write our DESTINATION_PATH into a file (tar-it.sh will pick it up)
	echo ${DESTINATION_PATH} > ${TMP_DIR}/DESTINATION_PATH
	touch ${TMP_DIR}/Iso_only
	touch ${TMP_DIR}/Backups_on_cd  # a stupid FLAG file for tar-it.sh
	Show_mount_output	# to make tmp/Backup.MntPoints file
elif [ x$MODE = xpath ]; then
        grep : ${ARG} > /dev/null 2>&1
        if [ $? -eq 0 ]; then
           # hum, NFS path given
           NFS_TMPDIR=`mktemp -d -p /tmp nfs.$$`
           echo_log "Mount ${ARG} under ${NFS_TMPDIR}"
           mount -t nfs ${ARG} ${NFS_TMPDIR}
           if [ $? -eq 1 ]; then
                echo "Could not mount NFS ${ARG} onto ${NFS_TMPDIR}."
                echo "Please try to mount it manually."
                exit 1
           fi
           ARG=${NFS_TMPDIR}
        fi
        if [ ! -d ${ARG} ]; then
                print "${ARG} does not exist.\n"
                exit 1
        fi
        DESTINATION_PATH=${ARG}
        echo ${DESTINATION_PATH} > ${TMP_DIR}/DESTINATION_PATH
        Show_mount_output
elif [ x$MODE = xdevice ]; then
        tape_dev=${TAPE_DEV}    # as defined in Config.sh
        Tape_local_or_remote
        ${REMOTE_COMMAND} ${RHOST} ${MT} -f ${RESTORE} rewind >/dev/null
        if [ $? -ne 0 ]; then   # tape_dev unknown
                print "${TAPE_DEV} is not ready.\n"
                exit 1
        fi
        Show_mount_output
        echo ${TAPE_DEV} > ${TMP_DIR}/TAPE_DEV
elif [ x$MODE = xOBDR ]; then
        tape_dev=${TAPE_DEV}    # as defined in Config.sh
        Tape_local_or_remote
        ${REMOTE_COMMAND} ${RHOST} ${MT} -f ${RESTORE} rewind >/dev/null
        if [ $? -ne 0 ]; then   # tape_dev unknown
                print "${TAPE_DEV} is not ready.\n"
                exit 1
        fi
        Show_mount_output
        echo ${TAPE_DEV} > ${TMP_DIR}/TAPE_DEV
        echo ${TAPE_DEV} > ${TMP_DIR}/OBDR
elif [ x$MODE = xUSB-KEY ]; then
	print "Backup on USB key\n"
	DESTINATION_PATH=${ISOFS_DIR}
        USBKEY_DEV=$ARG
	umount $USBKEY_DEV > /dev/null 2>&1
        if ! mount -o shortname=winnt $USBKEY_DEV $DESTINATION_PATH >/dev/null 2>&1 ; then
             print "\nCannot mount the USB key, so I give up.\n"
	     exit 1
	fi
	empty=`find $DESTINATION_PATH -empty`
	if [ -z "$empty" -o "$empty" != "$DESTINATION_PATH" ] ; then
            print "${c_higreen}USB key is not empty, ${c_end}"
            askyn N "Clean USB key now ? "
            if [ $? -eq 0 ]; then
		exit 1
	    fi
            rm -rf ${DESTINATION_PATH}/ > /dev/null 2>&1
	fi
	# before continue check if USBKEY is FAT16 and bootable
	umount $USBKEY_DEV > /dev/null 2>&1
	Check_USBKEY_FileSystemType
	Check_USBKEY_bootable
	Check_USBKEY_MBR
	mount -o shortname=winnt $USBKEY_DEV $DESTINATION_PATH >/dev/null 2>&1
	# write our DESTINATION_PATH into a file (tar-it.sh will pick it up)
	echo ${DESTINATION_PATH} > ${TMP_DIR}/DESTINATION_PATH
	echo ${USBKEY_DEV} > ${TMP_DIR}/USBKEY_DEV
	Show_mount_output	# to make tmp/Backup.MntPoints file
else
        Tar_dialog
fi

echo "
              ------- ${PROJECT} ${VERSION} -------
" >> ${LOG}
# mark the log file
echo "-------------< Entering `basename $0` >------------" >> ${LOG}

# check Encryption prerequisites
################################
echo_log "Checking encryption prerequisites and schemes"
if [ "${ENC_PROG}" = "openssl" ]; then 
   case "${ENC_PROG_CIPHER}" in
        base64) ;;
        bf|bf-cbc|bf-cfb|bf-ecb|bf-ofb) ;;
        cast|cast-cbc|cast5-cbc|cast5-cfb|cast5-ecb|cast5-ofb) ;;
        des|des-cbc|des-cfb|des-ecb|des-ofb) ;;
        des-ede|des-ede-cbc|des-ede-cfb|des-ede-ofb) ;;
        des3|des-ede3|des-ede3-cbc|des-ede3-cfb|des-ede3-ofb) ;;
        desx) ;;
        idea|idea-cbc|idea-ecb|idea-cfb|idea-ofb) ;;
        rc2|rc2-cbc|rc2-cfb|rc2-ecb|rc2-ofb|rc2-64-cbc|rc2-40-cbc) ;;
        rc4|rc4-64|rc4-40) ;;
        rc5|rc5-cbc|rc5-cfb|rc5-ecb|rc5-ofb) ;;
        *) echo "
*******************************************************************
* WARNING: Encryption with openssl requires an encryption cipher! *
*          As \"${ENC_PROG_CIPHER}\" is not supported by openssl  *
*          I will enforce NO encryption at all!!                  *
*******************************************************************" | tee -a ${LOG}
          ENC_PROG="cat" 
          ENC_PROG_CIPHER="" # force it to be empty 
          ;;
   esac
fi
if [ "${ENC_PROG}" = "openssl" ]; then 
   if [ "${MODE}" = "interacive" ]; then
        :       # will be prompted for a key (do nothing)
   else
        # check if key file exits
        if [ ! -f ${ENC_PROG_PASSWD_FILE} ]; then
           echo "FAIL: Encryption: Key file not found! ENC_PROG_PASSWD_FILE in Config.sh" | tee -a ${LOG}
           exit 255
        else
           touch ${TMP_DIR}/ENC_PROG_PASSWD
           chmod 600 ${TMP_DIR}/ENC_PROG_PASSWD
           echo "-kfile ${ENC_PROG_PASSWD_FILE}" >${TMP_DIR}/ENC_PROG_PASSWD
        fi
   fi
fi

# Execute PreExec command when not empty and non-rescue situation
if [ x$MODE != xrescue ] && [ ! -z "${PreExec}" ]; then
   echo_log "Executing ${PreExec}"
   ${PreExec}
fi

Check_which_command

# Gather general system info
Gather_info

# Prepare a ROOTFS in RAM
Make_rootfs

# Initial pupulation of the rootfs (create the necessary directories)
Init_rootfs

# Compile (if necessary) Busybox distribution and install it in rootfs
Make_busybox

# start filling the ROOTFS with our loadable modules in use
if [ x$MODE = xsuperrescue ]; then
   echo_log "Superrescue: link all loadable modules to our rootfs"
   mkdir -p ${ROOTFS}/lib
   #cp -Rv /lib/modules/${Kernel_Version}/ ${ROOTFS}/lib/modules/
   cd ${ROOTFS}/lib
   ln -s /mnt/cdrom/superrescue/lib/modules modules
   cd ${ROOTFS}/usr/lib
   ln -s /mnt/cdrom/superrescue/usr/lib/perl5 perl5
   cd ${MKCDREC_DIR}
else
   List_loadable_modules
fi

DEVFSD=`ps ax | grep devfsd | grep -v grep 2>/dev/null`
if [ x${DEVFS} = x0 ] || [ -z "${DEVFSD}" ]; then
        # Copy our /dev/* to our rootfs
        Copy_dev
fi

# Start populating the rootfs/etc directory (from /etc and/or $MKCDREC_DIR/etc)
Copy_etc

# PCMCIA config files to rootfs/etc/pcmcia
Copy_pcmcia

# Compile and install cutstream (a smart cat which takes MAXCDSIZE bytes
# a time and start MakeISO9660.sh script until EOF)
echo ${MAXCDSIZE} >/tmp/cutstream.h
if [ ! -x ${MKCDREC_DIR}/bin/cutstream ]; then
   Make_cutstream
fi

# Pastestream to stick together splitted backups again
if [ ! -x ${MKCDREC_DIR}/bin/pastestream ]; then
   Make_pastestream
else
   # need for rpm version
   echo_log strip_copy pastestream ${ROOTFS}/sbin/pastestream
   strip_copy ${MKCDREC_DIR}/bin/pastestream ${ROOTFS}/sbin/pastestream
fi

# Compile and install checkisomd5 and implantisomd5
if  [ ! -x ${MKCDREC_DIR}/bin/implantisomd5 ]; then
    Make_isomd5
else
    echo_log strip_copy checkisomd5 ${ROOTFS}/sbin/checkisomd5
    strip_copy ${MKCDREC_DIR}/bin/checkisomd5 ${ROOTFS}/sbin/checkisomd5
fi

# Fill up rootfs/[s]bin directory with binaries from list defined in Config.sh
Copy_binaries

###############
# Added 2006-05-09 by Schlomo Schapiro
###############
# If specified, copy Legato Networker files
if [ "${NSR_RESTORE}" = "y" ] ; then
        Make_nsr
fi

###############
# Added 12-30-03 -- Chris Strasburg
###############
# If specified, copy TSM files:
if [ "${TSM_RESTORE}" = "y" ]; then
        Make_tsm
fi
###############
if [ "${DP_RESTORE}" = "y" ]; then
   Make_Data_Protector
fi

###############
if [ x${BACULA_RESTORE} = xy ]; then
   ${SCRIPTS}/make_bacula
fi


# check space free on stage directory - if above 90% warn
Check_stage_capacity

# Terminfo stuff
Copy_terminfo

# RedHat 7.x introduced LABEL statement in /etc/fstab. Next routine makes
# the necessary script if needed
Check_for_disk_labels

# Make the shared libs for our rootfs
build_lib_list
Make_libs

# check space free on stage directory - if above 90% warn
Check_stage_capacity

# Make some symbolic links
Make_symlinks

# Miscellaneous
Miscellaneous

# Swap/disk space info on this system -> rootfs/etc/recovery
Save_diskinfo

# Add SSHD functionalities (if existent)
Check_for_sshd

# Save fstab/mount output needed for the recovery procedure
# we will tar --extract per filesystem (that's the basic idea)
cp ${MKCDREC_DIR}/Config.sh ${ROOTFS}/etc/recovery/
# comment some unused variables during restore phase
ed ${ROOTFS}/etc/recovery/Config.sh <<eof
/^MKCDREC_MODULES=/s/^/# /
/^SCRIPTS=/s/^/# /
/^stagedir=/s/^/# /
/^BUSYBOX_DIR=/s/^/# /
/^CUTSTREAM_DIR=/s/^/# /
/^PASTESTREAM_DIR=/s/^/# /
wq
.
eof

cp ${SCRIPTS}/ansictrl.sh ${ROOTFS}/etc/recovery/
cp ${SCRIPTS}/restore_common.sh ${ROOTFS}/etc/recovery/
cp ${MKCDREC_DIR}/VERSION ${ROOTFS}/etc/recovery/
cp ${MKCDREC_DIR}/contributions/menu.sh ${ROOTFS}/bin/
cp /etc/fstab ${ROOTFS}/etc/recovery/fstab.`hostname`
cp /etc/mtab ${ROOTFS}/etc/recovery/mtab.`hostname`
df -kP > ${ROOTFS}/etc/recovery/df.`hostname`
if [ "${ONLY_INCLUDE_LISTED_FS}" = "Y" ]; then
	# only backup/restore the file systems listed in
	# variable INCLUDE_FS_LIST
	mv ${TMP_DIR}/To_Backup ${TMP_DIR}/To_Backup.save
	for x in `echo ${INCLUDE_FS_LIST}`
	do
	  cat ${TMP_DIR}/To_Backup.save | { while read Line
	  do
		y=`echo ${Line} | awk '{print $2}'`
		if [ "${x}" = "${y}" ]; then
		   echo "${Line}" >> ${TMP_DIR}/To_Backup
		fi
	  done
	  } # end of while read y
	done # end of for x
fi
# Save the list of fs which were backup'ed (needed for restore
cp ${TMP_DIR}/To_Backup ${ROOTFS}/etc/recovery/To_Restore
cd ${ROOTFS}
rm -rf ${ROOTFS}/cdrom
ln -s /mnt/cdrom cdrom
cd ${MKCDREC_DIR}

# Fill "modprobe.sh" script to preload certain modules, e.g. scsi/FC
for i in `ls /proc/scsi/ | egrep -v '(scsi|sg|device_info)'`
do
    [ ! -z "${i}" ] && echo modprobe -q ${i} >>${ROOTFS}/etc/recovery/modprobe.sh
done
# cciss is not visible under /proc/scsi (any others?)
lsmod | grep -q cciss && echo modprobe -q cciss >>${ROOTFS}/etc/recovery/modprobe.sh

# SCSI (found in FC3 rc.sysinit file)
for module in `/sbin/modprobe -c | awk '/^alias[[:space:]]+scsi_hostadapter[[:space:]]/ { print $3 }'` ; do
        echo modprobe -q $module >>${ROOTFS}/etc/recovery/modprobe.sh
done

# SATA modules not picked up
lsmod | grep -q ata_piix && echo modprobe -q ata_piix >>${ROOTFS}/etc/recovery/modprobe.sh

# remove duplicates
cat ${ROOTFS}/etc/recovery/modprobe.sh | sort -u > /tmp/modprobe.sh
mv /tmp/modprobe.sh ${ROOTFS}/etc/recovery/modprobe.sh

if [ -f ${TMP_DIR}/TAPE_DEV ]; then
   echo modprobe -q st >>${ROOTFS}/etc/recovery/modprobe.sh
fi

# copy the DESTINATION_PATH to ramfs (to know when the backups were made)
# When backups were made we make a timestamp "Backup",
# otherwise we will see "CDrec" instead in /etc/recovery directory.
if [ ! -z "${DESTINATION_PATH}" ]; then
        # Backups will be on CD, disk, or network disk
        echo ${DESTINATION_PATH} will contain the backups | tee -a ${LOG}
        touch ${ROOTFS}/etc/recovery/Backup_made_at_`date +%d.%m.%Y`
        # Backups_on_cd is to FLAG us it's on the CD
        if [ -f ${TMP_DIR}/Backups_on_cd ]; then
           echo "/cdrom/" > ${ROOTFS}/etc/recovery/RESTORE_PATH
           echo "CDROM" >${ROOTFS}/etc/recovery/Backup_made_at_`date +%d.%m.%Y`
        elif [ -s ${TMP_DIR}/USBKEY_DEV ]; then
           echo "/cdrom/" > ${ROOTFS}/etc/recovery/RESTORE_PATH
           echo "CDROM" >${ROOTFS}/etc/recovery/Backup_made_at_`date +%d.%m.%Y`
        else
           echo ${DESTINATION_PATH} > ${ROOTFS}/etc/recovery/RESTORE_PATH
           cd ${DESTINATION_PATH}
	   touch ${DESTINATION_PATH}/.testwrite 
	   if [ $? -ne 0 ]; then 
	      echo "Fatal: Cannot write to DESTINATION_PATH(=${DESTINATION_PATH})" 
	      exit 1 
	   fi 
	   rm -f ${DESTINATION_PATH}/.testwrite
           RestoreMntPoint=`df -kP . | tail -n 1 | awk '{print $6}'`
           RestoreDev=`mount|grep "on ${RestoreMntPoint} " | awk '{print $1}'`
           RestoreFStype=`mount|grep "on ${RestoreMntPoint} " | awk '{print $5}'`
           RestoreOptions=`mount|grep "on ${RestoreMntPoint} " | awk '{print $6}'| sed -e 's/[()]//g'`
	   echo "mkdir -p -m 755 ${RestoreMntPoint}" >> ${ROOTFS}/etc/recovery/mkdirs.sh
           df -kP . | tail -n 1 | grep : >/dev/null 2>&1
           if [ $? -eq 0 ]; then
              # NFS mount point
              echo "NFS" >${ROOTFS}/etc/recovery/Backup_made_at_`date +%d.%m.%Y`
              echo "NFS" >${MKCDREC_DIR}/tmp/NFS
              echo "mkdir -p /nfs/${RestoreMntPoint}" >> ${ROOTFS}/etc/recovery/mount.sh
              echo "mount -t ${RestoreFStype} ${RestoreDev} /nfs/${RestoreMntPoint} -o ${RestoreOptions}" >> ${ROOTFS}/etc/recovery/mount.sh
           else
              echo "DISK">${ROOTFS}/etc/recovery/Backup_made_at_`date +%d.%m.%Y`
              echo "modprobe -q ${RestoreFStype}" >>${ROOTFS}/etc/recovery/mount.sh
              case ${RestoreFStype} in
                ext3|ext4)
                    echo "modprobe -q jbd" >>${ROOTFS}/etc/recovery/mount.sh ;;
                *) ;;
              esac
              echo "mount -t ${RestoreFStype} ${RestoreDev} ${RestoreMntPoint} -o ${RestoreOptions}" >> ${ROOTFS}/etc/recovery/mount.sh
           fi
        fi
elif [ -f ${TMP_DIR}/TAPE_DEV ]; then
        # backups will be on tape (thx Marco ;-)
        cp ${TMP_DIR}/TAPE_DEV ${ROOTFS}/etc/recovery/TAPE_DEV
        echo ${REMOTE_COMMAND} >${ROOTFS}/etc/recovery/REMOTE_COMMAND
        echo "TAPE" >${ROOTFS}/etc/recovery/Backup_made_at_`date +%d.%m.%Y`
elif [ "${NSR_RESTORE}" = "y" ]; then
        echo "NSR" >${ROOTFS}/etc/recovery/Backup_made_with_NSR
elif [ "${TSM_RESTORE}" = "y" ]; then
        echo "TSM" >${ROOTFS}/etc/recovery/Backup_made_with_TSM
elif [ "${DP_RESTORE}" = "y" ]; then
        echo "DP" >${ROOTFS}/etc/recovery/Backup_made_with_DP
elif [ "${BACULA_RESTORE}" = "y" ]; then
        echo "BACULA" >${ROOTFS}/etc/recovery/Backup_made_with_BACULA
else
        echo "The CD-ROM made will primarily be a RESCUE CD!" | tee -a ${LOG}
        touch ${ROOTFS}/etc/recovery/CDrec_${VERSION}_made_at_`date +%d.%m.%Y`
        rm -f ${ISOFS_DIR}/*.log
fi

cd ${MKCDREC_DIR}
[ -f ${ROOTFS}/etc/recovery/mount.sh ] && chmod +x ${ROOTFS}/etc/recovery/mount.sh
if [ -f ${ROOTFS}/etc/recovery/modprobe.sh ]; then
  sort -u ${ROOTFS}/etc/recovery/modprobe.sh > /tmp/modprobe.sh
  cp -f /tmp/modprobe.sh ${ROOTFS}/etc/recovery/modprobe.sh
  chmod +x ${ROOTFS}/etc/recovery/modprobe.sh
  echo_log "Created the following modprobe.sh script:"
  echo_log "`cat ${ROOTFS}/etc/recovery/modprobe.sh`"
fi

# store the compress and encrypt program in files for recovery purposes
echo ${CMP_PROG} > ${ROOTFS}/etc/recovery/CompressedWith
echo ${ENC_PROG_CIPHER} > ${ROOTFS}/etc/recovery/EncryptedWith

# Copy some info to the ISOFS_DIR (easy when we mount the CD to look at it)
# Copy VERSION (to know with which version of mkcdrec the CDR was made)
cp VERSION ${ISOFS_DIR}
cp README ${ISOFS_DIR}
cp -R doc ${ISOFS_DIR}
if [ -d ${MKCDREC_DIR}/utilities ]; then
        cp -R utilities ${ISOFS_DIR}
        echo_log "Copying the mkCDrec utilities to ISO9660 image"
fi
# copy the restore scripts to /etc/recovery
for i in start-restore.sh clone-dsk.sh restore_common.sh ask.for.cd.sh restore-fs.sh \
  mount_drives.sh partition_drives.sh format_drives.sh \
  restore_boot_loader.sh
do
echo_log cp ${SCRIPTS}/${i} ${ROOTFS}/etc/recovery
cp ${SCRIPTS}/${i} ${ROOTFS}/etc/recovery
done

# cp our man script to ROOTFS (again), in case the user copied the executable
echo_log cp ${MKCDREC_DIR}/usr/bin/man ${ROOTFS}/usr/bin/man
cp ${MKCDREC_DIR}/usr/bin/man ${ROOTFS}/usr/bin/man

# copy the MAN_PAGES list to our rootfs
Copy_man_pages

# check space free on stage directory - if above 90% warn
Check_stage_capacity

# Check which bootloader we're using
echo "UNKNOWN" > ${ROOTFS}/etc/recovery/BOOTLOADER      # if nothing found
Check_Bootloader
rm -f /tmp/mkcdrec.lck.$$ /tmp/available.disks          # cleanup temp. files

# A hack needed for Mandrake and DevFS (copy the content of /lib/dev-state
if [ -d /lib/dev-state ]; then
   echo_log cp -R /lib/dev-state ${ROOTFS}/lib
   cp -R /lib/dev-state ${ROOTFS}/lib
fi

# for udev/hotplug
if [ -d /etc/hotplug ]; then
   echo_log cp -pLR /etc/hotplug ${ROOTFS}/etc
   cp -pLR /etc/hotplug ${ROOTFS}/etc
   echo_log cp -pLR /etc/hotplug.d ${ROOTFS}/etc
   cp -pLR /etc/hotplug.d ${ROOTFS}/etc
fi
if [ -d /etc/udev ]; then
   if [ -d /etc/dev.d ]; then
      rm -rf ${ROOTFS}/etc/dev.d
      cp -dpR /etc/dev.d ${ROOTFS}/etc
      echo_log cp -dpR /etc/dev.d ${ROOTFS}/etc
   fi
   rm -rf ${ROOTFS}/etc/udev
   cp -dpR /etc/udev ${ROOTFS}/etc
   echo_log cp -dpR /etc/udev ${ROOTFS}/etc
fi

# a touch of OBDR
[ -f ${TMP_DIR}/OBDR ] && touch ${ROOTFS}/etc/recovery/OBDR

# AUTODR=y? (Automatic Disaster Recovery for start-restore.sh?)
[ "${AUTODR}" = "y" ] && touch ${ROOTFS}/etc/recovery/AUTODR

# Add perl stuff if in Config.sh we defined ADD_PERL=yes
if [ ${ADD_PERL} = "true" ]; then
   Copy_Perl_Environment
   # hopefully the ramdisk is big enough?
   Check_stage_capacity
fi

####################################################
# Copy some files to the rootfs - misc.
####################################################
[ -f /lib/lsb/init-functions ] && cp -p /lib/lsb/init-functions ${ROOTFS}/lib/lsb
touch ${ROOTFS}/var/log/lastlog	# needed by SLES10

# copy some useful info such as output of ifconfig
echo_log "Dump output of ifconfig into ${ROOTFS}/etc/recovery/ifconfig.txt"
ifconfig > ${ROOTFS}/etc/recovery/ifconfig.txt
ip a >${ROOTFS}/etc/recovery/ip_a.txt   # Added by Schlomo Schapiro 2006-05-11
#### end of filling up the rootfs ####

# Make a compressed copy of the etc/recovery directory
cd ${ROOTFS}
tar zpcf ${ISOFS_DIR}/recovery.tgz etc/recovery

# TEST
#echo ln -s etc/rc.d/rc.sysinit ./linuxrc | tee -a ${LOG}
#(cd ${ROOTFS}; ln -s etc/rc.d/rc.sysinit ./linuxrc 2>>${LOG})

# Compress the rd-base.img file
cd ${basedir}
echo "The base ramdisk has the following size (uncompressed):" | tee -a ${LOG}
color red white
df -kP $stagedir | tee -a ${LOG}
color white black
umount rd-base.img 2>/dev/null

if [ x${ROOT_FS} = xramfs ]; then
	echo
	echo "Compressing ramdisk" | tee -a ${LOG}
	echo "Size of ramdisk is `du -sk ${ROOTFS}`" | tee -a ${LOG}
else
	echo
	echo "Compressing the complete filesystem 'rd-base.img'" | tee -a ${LOG}
	echo " the size of rd-base.img is `ls -l rd-base.img | awk '{print $5}'`" | tee -a ${LOG}
fi
echo " **** Be Prepared: it can take a while ****"

#if [ x${BOOTARCH} = xia64 ]; then
#  dd if=rd-base.img bs=1k count=$((RAMDISK_SIZE*1024)) \
#        | bzip2 -v9 > ${ISOFS_DIR}/rd-base.img.bz2
#elif [ x${ROOT_FS} = xramfs ]; then
if [ x${ROOT_FS} = xramfs ]; then
  echo "Finishing the second ramdisk via cpio/bzip2 [type ramfs]" | tee -a ${LOG}
  (cd ${stagedir} && find .   | \
        cpio -H newc --create --quiet | \
        bzip2 -v9 > "${ISOFS_DIR}/rd-base.img.bz2"  2>>${LOG} )
else
  dd if=rd-base.img bs=1k | bzip2 -v9 > ${ISOFS_DIR}/rd-base.img.bz2
fi

# check integrity of rd-base.img.bz2
echo "Check integrity of rd-base.img.bz2." | tee -a ${LOG}
bzip2 -t ${ISOFS_DIR}/rd-base.img.bz2
if [ $? -eq 1 ]; then
  error 1 "rd-base.img was not correctly compressed with bzip2.
Please do a \'make clean\' and try again."
fi

# the garbage collector
do_cleanup

# create a timestamp in tmp that will be used by mkisofs (needed if we pass
# midnight during backup/mkisofs phases ;-)
date +%d.%m.%Y > ${TMP_DIR}/DATE

# a really stupid line of code to hack around the mkisofs trouble of finding
# the relative path of bootflop.img (to make the boot.cat file)
# add a paranoid check on / (gdha, 16/04/2001)
if [ "`pwd`" = "/" ]; then
   error 1 "It cannot be true that `pwd` is /. MkCDrec should live in a sub-directory somewhere!"
fi 
rm -rf isofs    # should not exist anyway
ln -s ${ISOFS_DIR} isofs        # we are in $MKCDREC_DIR now

# write "0" into volno file (single volume; will increment it for multi vols)
echo "0" > ${TMP_DIR}/volno

# check if we need to run cfg2html (nice description of our system hw/sw)
if [ -f ${MKCDREC_DIR}/utilities/cfg2html.sh ]; then
   echo_log "+-------------------------------------------------------------------------+"
   echo_log "  Busy with Cfg2html - collecting hw/sw information into ${ISOFS_DIR}/doc"
   echo_log "+-------------------------------------------------------------------------+"
   cd ${ISOFS_DIR}/doc
   echo_log "`${MKCDREC_DIR}/utilities/cfg2html.sh`"
fi

if [ x${BOOTARCH} = xia64 ]; then
   # make a safety backup of /boot/efi on the CDROM
   echo_log "tar zcf ${ISOFS_DIR}/boot_efi.tar.gz /boot/efi"
   tar zcf ${ISOFS_DIR}/boot_efi.tar.gz /boot/efi
fi

# Allow user to add custom directories to the CDROM
cd ${MKCDREC_DIR}
if [ -x ${MKCDREC_DIR}/scripts/add_to_cdrom ] ; then
   ${MKCDREC_DIR}/scripts/add_to_cdrom
fi

echo "-------------< Leaving `basename $0` >------------" >> ${LOG}

rm -f /tmp/Analyse_mdadm_conf.lck       # remove lock file
rm -f /tmp/MDdev
${UMASK_RESTORE}        # restore original umask settings
exit 0
