# mkcdrec (C) Copyright 2000-2008 by Gratien D'haese - IT3 Consultants
# Please read LICENSE in the source directory
#
#### $Id: make_common.sh,v 1.47 2009/09/10 05:44:52 gdha Exp $
#
# Script will be dotted by :
#       Config.sh
################################################################

[ ! -d ${ISOFS_DIR} ] && mkdir -p ${ISOFS_DIR}
[ ! -d ${CDREC_ISO_DIR} ] && mkdir -p ${CDREC_ISO_DIR}
[ ! -d ${TMP_DIR} ] &&  mkdir -p ${TMP_DIR}

# ROOTFS will be our temporary root directory that we'll use to recover/boot
# It will contains enough functionality as a rescue disk too
ROOTFS=${stagedir}
if [ ! -d ${ROOTFS} ]; then
        mkdir -p ${ROOTFS}
fi

# Load modules.
for m in $MKCDREC_MODULES; do
        . ${MKCDREC_DIR}/modules/$m
done

# Load init flavor.
if [ -f ${MKCDREC_DIR}/etc/rc.d/flavors/$INIT_FLAVOR ]; then
. ${MKCDREC_DIR}/etc/rc.d/flavors/$INIT_FLAVOR
fi

set -o history
trap _do_cleanup SIGTERM SIGINT

check_rc()
{
   if [ $? != 0 ]; then
      echo "Command failed."
      exit 1
   fi
}

# Echo the command line to the ${LOG} file, and if
#  VERBOSE is set, then echo it to the terminal too
echo_log() {
   if [ x${VERBOSE} = xy ] ; then
      echo "$*" | tee >>${LOG}
   else
      echo "$*" >>${LOG}
   fi
}

strip_copy() {
        ttt=`basename $1`
        if ! cp $1 /tmp/$ttt; then
                return 1
        fi
        strip /tmp/$ttt
        mv /tmp/$ttt $2
        return 0
}

strip_copy_lib() {
        ttt=`basename $1`
        if ! cp $1 /tmp/$ttt; then
                return 1
        fi
        strip -S /tmp/$ttt
        mv /tmp/$ttt $2
        return 0
}

_do_cleanup()
{
    echo "Cleaning up files created by `basename $0` due to failure." >&2
    cd $basedir
    sync
    umount `cat ${TMP_DIR}/USBKEY_DEV` > /dev/null 2>&1
    umount $stagedir 2> /dev/null
    if type do_cleanup > /dev/null 2>&1; then
        do_cleanup
    fi
    exit 1
}

ParseDevice () {
###########
# input $1 is a line containing as 1st argument a file system devive, eg.
# /dev/hda1, /dev/sdb1, /dev/md0, /dev/disk/c1t0d0, or even devfs alike
# /dev/ide/host0/bus0/target0/lun0/part2
# Output: Dev: hda1, sdb1, md0, md/0, disk/c1t0d0, vg_sd/lvol1
#        _Dev: hda1, sdb1, md0, md_0, disk_c1t0d0, vg%137sd_lvol1
Dev=`echo ${1} | awk '{print $1}' | cut -d"/" -f 3-`
_Dev=`echo ${Dev} | sed -e 's/_/%137/g' | tr "/" "_"`
}

ParseDisk () {
#########
# input is $Dev (e.g. sda1, disk/c1t0d0)
# output is dsk (e.g. sda, disk/c1t0) and _dsk (e.g. sda, disk_c1t0)

# is it one of those with "p" at the end?
# this will match: Mylex (rd/c?d?p?), Compaq IDA (ida/c?d?p?),
# Compaq Smart (cciss/c?d?p?), AMI Hyperdisk (amiraid/ar?p?),
# IDE Raid (e.g. Promise Fastrak) (ataraid/d?p?), EMD (emd/?p?) and
# Carmel 8-port SATA (carmel/?p?)
DEVwP=`expr "${Dev}" : "\(\(cciss\|rd\|ida\)/c[0-9]\+d[0-9]\+p[0-9]\+\|amiraid/ar[0-9]\+p[0-9]\+\|ataraid/d[0-9]\+p[0-9]\+\|\(emd\|carmel\)/[0-9]\+p[0-9]\+\)"`


if [ -c /dev/.devfsd ]; then
   # e.g. disc=ide/host0/bus0/target0/lun0/disc
   disc=`echo ${Dev} | cut -d"p" -f 1`disc
   if [ -b /dev/${disc} ]; then # I'm paranoid I know
     # to please sfdisk we have to backtrace the old style name (sda)
     dsk=`ls -l /dev | grep ${disc} | awk '{print $9}'`
   else
     # maybe devfs was configured in old style only?
     if [ -z $DEVwP ]; then
       dsk=`echo ${Dev} | sed -e 's/[0-9]//g'`      # sda
     else
       dsk=`echo ${Dev} | sed -e 's/p[0-9]\+$//g'`  # cXdX
     fi
   fi
else
   if [ -z $DEVwP ]; then
     dsk=`echo ${Dev} | sed -e 's/[0-9]//g'`      # sda
   else
     dsk=`echo ${Dev} | sed -e 's/p[0-9]\+$//g'`  # cXdX
   fi
fi
_dsk=`echo ${dsk} | tr "/" "_"`

}

Fail () {
####
echo "Fatal: $1" >> ${LOG}
echo -en "\a"
error 1 "Fatal: $1"
}

Check_stage_capacity () {
####################
in_use=`df -kP ${MKCDREC_DIR}/stage | tail -n 1 | awk '{print $5}' | cut -d"%" -f 1`
if [ ${in_use} -eq 100 ]; then
  error 1 "Base ram disk is 100% FULL. Increase RAMDISK_SIZE in Config.sh"
fi
if [ ${in_use} -gt 90 ]; then
  color white blue
  echo "${stagedir} is for ${in_use}% used!"
  sleep 5
  color white black
  echo
fi
}

Build_exclude_list () {
#####################################
### First we make an exclude list ###
#####################################
# some paths MUST be excluded
set -o noglob

if [ -f ${TMP_DIR}/TAPE_DEV ]; then
    > ${TMP_DIR}/exclude_list # empty file
else
    echo ${DESTINATION_PATH} > ${TMP_DIR}/exclude_list
fi
echo "/proc/kcore" >> ${TMP_DIR}/exclude_list   # to avoid disasters (SuSe)
echo ${ISOFS_DIR} >> ${TMP_DIR}/exclude_list
#if [ "${CDREC_ISO_DIR}" != "." ]; then
#   echo ${CDREC_ISO_DIR} >> ${TMP_DIR}/exclude_list
#fi
echo ${ROOTFS} >> ${TMP_DIR}/exclude_list
# Exclude paths on users request (if any)
# check if the EXCLUDE_LIST in Config.sh is empty or not
if [ -n "${EXCLUDE_LIST}" ]; then
  for excl_paths in `echo ${EXCLUDE_LIST}`
  do
   echo ${excl_paths} >> ${TMP_DIR}/exclude_list
  done
fi

# build NFS exclude list (we do not want to back the NFS server)
for exc in `mount | egrep -v "proc|devfs|devpts|${Dev}" | awk '{print $3}'`
do
  # 'exc' contains the file system
  if [ "`mount | grep ${exc} | awk '{print $5}'`" = "nfs" ]; then
     echo "${exc}/" >> ${TMP_DIR}/exclude_list
  fi
done

# if FS is "/" then we have to make sure we do not backup mount-points.
# Remember, mount points are created with mkdirs.sh at restore time ;-)
if [ "${Fs}" = "/" ]; then
   # next line will show all mounted partitions (maybe more than what
   # is listed in /etc/fstab)! Remove this FS from exclude_list too.
   # /proc will be in this list too (and MUST be excluded!)
   for exc in `mount | egrep -v "devfs|devpts|${Dev}" | awk '{print $3}'`
        do
          echo "${exc}/" >> ${TMP_DIR}/exclude_list
        done # end of for exc
fi # end of FS=/
# time for the magic! As we descend $Fs absolute paths have NO
# meaning in the exclude list (too bad), e.g. /foo -> foo/*
# if e.g. Fs=home than home will be stripped too
> ${TMP_DIR}/exc.tmp    # make it empty!

for i in `cat ${TMP_DIR}/exclude_list`
do
if [ "${Fs}" = "/" ]; then
  echo $i | sed -e 's;^/\(.*\)$;\./\1;' >>${TMP_DIR}/exc.tmp
else
  echo $i | sed -e "s;^${Fs};;" | sed -e 's;^/\(.*\)$;\./\1;' >>${TMP_DIR}/exc.tmp
fi
done
# remove duplicates if any
cat ${TMP_DIR}/exc.tmp | sort | uniq > ${TMP_DIR}/${_Fs}.exclude_list
set +o noglob
}

Find_Root_Partition() {
echo $1 | cut -d"p" -f2- | sed -e 's/[a-zA-Z\/]//g'
}

Find_Linux_kernel () {
#================
# what is the current kernel - different way of finding acc. lilo or grub
# Input: none
# Output: $LINUX_KERNEL and /tmp/LINUX_KERNEL (contains content of variable
#         $LINUX_KERNEL)
#set -x
Kernel_Version=${LINUX_VERSION:-`uname -r`}
if [ ! -z "${LINUX_KERNEL}" ]; then
   # variable was set in Config.sh - test if kernel exist
   if [ -f ${LINUX_KERNEL} ]; then
      echo ${LINUX_KERNEL} > /tmp/LINUX_KERNEL
      return
   else
      # otherwise, make it empty and search ourselves
      LINUX_KERNEL="" && > /tmp/LINUX_KERNEL
   fi
fi

# Check LILO configuration if applicable
if [ -f /etc/lilo.conf ]; then
   cat /proc/cmdline | grep BOOT_IMAGE >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      Current_kernel_label=`cat /proc/cmdline | cut -d= -f2|sed 's/ .*//'`
   else
      Current_kernel_label=`awk -F= '/default/ {print $2}' /etc/lilo.conf`
   fi   
   Current_kernel_label=`echo ${Current_kernel_label} | sed -e 's/"//g'`
   egrep "image|label" /etc/lilo.conf | tr -d " " | \
   { while read Line
   do
        echo ${Line} | grep image= >/dev/null
        if [ $? -eq 0 ]; then
           image=`echo ${Line} | cut -d= -f2`
        fi
        echo ${Line} | grep label= >/dev/null
        if [ $? -eq 0 ]; then
           Found_label=`echo ${Line}|cut -d= -f2|sed -e 's/"//g'`
           if [ "${Found_label}" = "${Current_kernel_label}" ]; then
              # check if $image is a link
              if [ -L ${image} ]; then
                 :
              fi
              echo ${image} > /tmp/LINUX_KERNEL
              break             # hope we got the corr. kernel image
           fi
        fi
   done
   }
   # read the LINUX_KERNEL from tmp file (needed after a while loop!)
   LINUX_KERNEL=`cat /tmp/LINUX_KERNEL 2>/dev/null`
fi
# GRUB: grub.conf?
if [ -f /boot/grub/grub.conf ] && [ -z "${LINUX_KERNEL}" ]; then
   grep /boot /etc/fstab > /dev/null
   if [ $? -eq 0 ]; then
      LINUX_KERNEL='/boot'`grep kernel /boot/grub/grub.conf | grep -v "^#" | awk '{print $2}'` 
   else
      LINUX_KERNEL=`grep kernel /boot/grub/grub.conf | grep -v "^#" | awk '{print $2}' | grep ${Kernel_Version}` 
   fi
   echo ${LINUX_KERNEL} >/tmp/LINUX_KERNEL
   kernel_candidate=`echo ${LINUX_KERNEL} | awk '{print $1}'`
   if [ ! -f ${kernel_candidate} ]; then
      # stupid hack in case above trick did not find a valid linux kernel, but
      # instead returned only "/boot" (is a directory, so make it empty again)
      # NOTE: This only checks the first kernel if we got a list back.
      LINUX_KERNEL="" && > /tmp/LINUX_KERNEL
   fi
fi
# GRUB: menu.lst?
if [ -f /boot/grub/menu.lst ] && [ -z "${LINUX_KERNEL}" ]; then
   cat /proc/cmdline | grep root= >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      # FIX for "ro root=/dev/hda4\n video=i810fb..."
      RootDevice=/dev/`cat /proc/cmdline | head -n 1 | cut -d"/" -f3- | cut -d" " -f1` #/dev/hda5
      ParseDevice ${RootDevice}  # output: $Dev
      ParseDisk ${Dev} # output: $dsk
      # fix for /dev/cciss/c0t0p0 type of disks
      RootPartition=`Find_Root_Partition $RootDevice`
      #RootPartition=`echo ${RootDevice} | sed -e 's/[a-zA-Z\/]//g'`  #5
      #BootDevice=`echo ${RootDevice} | sed -e 's/'${RootPartition}'//'` #/dev/hda
      BootDevice=/dev/${dsk} #/dev/hda
      GrubPartition=`expr ${RootPartition} - 1` # always 1 less
      Cmdline="`cat /proc/cmdline|head -n 1|sed -e 's/  / /g' |sed -e 's/ $//'`"
      GrubDevice=`grep ${BootDevice} /boot/grub/device.map | awk '{print $1}' | sed -e 's/[()]//g'`     # hd0
      # FIXME for multiple entries
      # FIXME debian root (hd0,0) and on next line kernel ...
      grep "kernel (${GrubDevice},${GrubPartition}" /boot/grub/menu.lst| sed -e 's/  / /g' | { while read Line
        do
          echo ${Line} | grep "${Cmdline}" >/dev/null
          if [ $? -eq 0 ]; then
                LINUX_KERNEL=`echo ${Line} | cut -d")" -f2 | awk '{print $1}'`
                echo ${LINUX_KERNEL} >/tmp/LINUX_KERNEL
                break # we found it
          fi
        done
        }
     LINUX_KERNEL=`cat /tmp/LINUX_KERNEL 2>/dev/null`
     if [ ! -f ${LINUX_KERNEL} ]; then
        # again if kernel is not a file, make it empty again...
        LINUX_KERNEL="" && >/tmp/LINUX_KERNEL
     fi
     # if LINUX_KERNEL="" could this be a Debian system?
     if [ -z "${LINUX_KERNEL}" ]; then
         # try it the hard way
         LINUX_KERNEL=`ls /boot/vm*${Kernel_Version}`
         [ -f ${LINUX_KERNEL} ] && echo ${LINUX_KERNEL} >/tmp/LINUX_KERNEL
     fi # [ -z "${LINUX_KERNEL}" ]
   fi # cat /proc/cmdline
fi # [ -f /boot/grub/menu.lst ]
# SPARC?
if [ -f /boot/silo.conf ]; then # SPARC/Linux
   Kernel_Version=${LINUX_VERSION:-`uname -r`}
   LINUX_KERNEL=`ls /boot/vm*${Kernel_Version}`
   echo ${LINUX_KERNEL} >/tmp/LINUX_KERNEL
fi

if [ x${BOOTARCH} = xia64 ]; then # linux ia64
        Kernel_Version=${LINUX_VERSION:-`uname -r`}
        LINUX_KERNEL=`ls /boot/vm*${Kernel_Version}`
        echo ${LINUX_KERNEL} >/tmp/LINUX_KERNEL
fi

# read LINUX_KERNEL back from file to synchronize mem/file
LINUX_KERNEL=`cat /tmp/LINUX_KERNEL 2>/dev/null`

# Being paranoid! Seen problems with e.g.
# LINUX_KERNEL=/boot/vmlinuz-2.4.18-19.7.x /vmlinuz-2.4.18-3
if [ -z "$LINUX_VERSION" ]; then
        Kernel_Version=`uname -r`
else
        Kernel_Version=${LINUX_VERSION:-`uname -r`}
fi

for lxk in `echo ${LINUX_KERNEL}`
do
        p2=`echo ${lxk} | cut -d"-"  -f2-`      # we hope "-" separates
        if [ "${p2}" = "${Kernel_Version}" ]; then
           if echo ${lxk} | egrep '^/boot' ; then
              LINUX_KERNEL=${lxk}
           else
              LINUX_KERNEL=/boot${lxk}
           fi
           echo ${LINUX_KERNEL} >/tmp/LINUX_KERNEL
        fi
done

# read LINUX_KERNEL back from file to synchronize mem/file
LINUX_KERNEL=`cat /tmp/LINUX_KERNEL 2>/dev/null`

echo "LINUX_KERNEL=${LINUX_KERNEL}" >> ${LOG}
if [ -z "${LINUX_KERNEL}" ]; then
   echo "
WARNING: No Linux kernel was found automatically!
Please edit Config.sh file and add which kernel you are using into LINUX_KERNEL" | tee -a ${LOG}
# PANIC stop
echo "Set LINUX_KERNEL in Config.sh" && error 1
fi
}

Find_local_disks () {
###################
# Find and list all local IDE/SCSI disks into /tmp/available.disks
# copied from clone-dsk.sh - should become a real common function
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
ls -l /dev/sd* | awk '{print $5, $6, $10}' | sed  's;,;;' > /tmp/ls_sd
# list all found scsi devices in /tmp/scsi_devs
egrep -A 1 Host /proc/scsi/scsi | sed -e 's;^[  ]*;;' > /tmp/scsi_devs
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
} # of SCSI_Adapter
fi # of /proc/scsi/scsi

# scan HW RAID adapters (will catch everything)
cat /proc/partitions | { while read Line
do
   major=`echo ${Line} | awk '{print $1}'`
   minor=`echo ${Line} | awk '{print $2}'`
   name=`echo ${Line} | awk '{print $4}'`
   case ${major} in
   104|105)
        case ${minor} in
        0|16|32|48|64|80|96)
           echo "/dev/${name}" >> /tmp/available.disks
           ;;
        *) ;; # do nothing
        esac
        ;;
   *)   ;; # do nothing
   esac
done
}

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
                                                                                
# after last steps some devices could be double listed - uniq/sort
cat /tmp/available.disks | sort | uniq > /tmp/available.new
mv -f /tmp/available.new /tmp/available.disks
# end of disk scanning (all local disks are in file /tmp/available.disks )
# cleanup temporary files
rm -f /tmp/ls_sd /tmp/scsi_devs
}

SetTapeDensity () {
##############
# in Config.sh variable TapeDensity is defined; well the user should have
# filled in the correct value with the aid of "mt -f ${MT} densities"
# command. In this finction we will link with TapeDensity a proper CAPACITY
# value for the tape.

case ${TapeDensity} in
        "0x00") # default: hum? still don't know the density. Keep default
                # CAPACITY value
                ;;
        "0x13") # DDS (61000 bpi)
                CAPACITY=1300000        # 1.3 Gb
                ;;
        "0x19") # DLT 10GB
                CAPACITY=10000000
                ;;
        "0x1a") # DLT 20GB
                CAPACITY=20000000
                ;;
        "0x1b") # DLT 35GB
                CAPACITY=35000000
                ;;
        "0x24") # DDS-2
                CAPACITY=4000000        # 4 Gb
                ;;
        "0x25") # DDS-3
                CAPACITY=12000000       # 12 Gb (non-compressed)
                ;;
        "0x26") # DDS-4
                CAPACITY=20000000       # 20 Gb (non-compressed)
                ;;
        "0x30") # AIT-1
                CAPACITY=35000000       # 35 Gb (non-compressed)
                ;;
        "0x31") # AIT-2
                CAPACITY=60000000       # 60 Gb (non-compressed) ??
                ;;
        "0x49") # SDLT
                CAPACITY=160000000      # 160 Gb (non-compressed) ??
                ;;
        *)      # list is very uncomplete. Input is welcome...
                # Keep default CAPACITY=2100000 (2.1 Gb)
                ;;
esac

# now we set the tape density
${MT} -f ${TAPE_DEV} setdensity ${TapeDensity}
echo "${MT} -f ${TAPE_DEV} setdensity ${TapeDensity}" | tee -a ${LOG}
echo "Tape capacity is ${CAPACITY}" | tee -a ${LOG}
}

GetBootArch () {
###########
# return the (b)arch (boot) architecture variable
arch="`uname -m`"
case ${arch} in
        i386|i486|i586|i686|i786)       barch=x86 ;;
        x86_64)                         barch=${arch} ;;
        sparc)                          barch=${arch} ;;
        ppc)                            barch=new-powermac ;;
        ia64)                           barch=${arch} ;;
        *)                              barch="Unsupported" ;;
esac
}

Divide () {
#########
num1=$1
num2=$2
                                                                                
# divide with floating numbering
bc -l <<EOF
${num1}/${num2}
EOF
}
#-----<--------->-------

Multiply () {
###########
num1=$1
num2=$2
                                                                                
bc -l <<EOF
${num1}*${num2}
EOF
}
#-----<--------->-------

Find_path_of_file () {
# input variable is the path to a file - we need to cut the file
# from the path and return this path only
ipath=$1
path="/"
NF=`echo $ipath | awk -F "/" '{print NF-1}'`
echo $ipath | cut -d"/" -f 1-$NF
}
#-----<--------->-------

Check_USBKEY_FileSystemType () {
# USBKEYs must be of type FAT16 (new keys are often FAT32)
USBKEY_DISK=`echo ${USBKEY_DEV} | tr [0-9] " "` # /dev/sdb1 becomes /dev/sdb
echo "Current USBKEY partition layout incl. File System Type:" | tee -a ${LOG}
fdisk -l ${USBKEY_DISK} >${TMP_DIR}/usbkey_fdisk 2>/dev/null 
cat ${TMP_DIR}/usbkey_fdisk | tee -a ${LOG}
grep -iq fat32 ${TMP_DIR}/usbkey_fdisk
if [ $? -eq 0 ]; then
	echo "WARNING: USBKEY device ${USBKEY_DEV} is of type FAT32!" | tee -a ${LOG}
	USBKEY_PAR=`grep -i fat32 ${TMP_DIR}/usbkey_fdisk | awk '{print $1}' | tr [A-Za-z/] " " | awk '{print $1}'` # should now only contain a nr
	echo "Try to change FAT32 into FAT16 (harmless :)" | tee -a ${LOG}
	echo sfdisk --change-id ${USBKEY_DISK} ${USBKEY_PAR} 6 | tee -a ${LOG}
	sfdisk --change-id ${USBKEY_DISK} ${USBKEY_PAR} 6
fi
fdisk -l ${USBKEY_DISK} >${TMP_DIR}/usbkey_fdisk 2>/dev/null
grep -iq fat16 ${TMP_DIR}/usbkey_fdisk
if [ $? -eq 0 ]; then
	echo "USBKEY device ${USBKEY_DEV} is of type FAT16." | tee -a ${LOG}
else
	Fail "USBKEY device ${USBKEY_DEV} does not have a FAT16 File System! Change it with fdisk and make it bootable too."
fi
}
#-----<--------->-------

Check_USBKEY_bootable () {
# USBKEY must be bootable or it won't boot obviously
# We will use ${TMP_DIR}/usbkey_fdisk as input created by function Check_USBKEY_FileSystemType
USBKEY_DISK=`echo ${USBKEY_DEV} | tr [0-9] " "` # /dev/sdb1 becomes /dev/sdb
grep -i fat16 ${TMP_DIR}/usbkey_fdisk | grep -q "*" 2>/dev/null
if [ $? -eq 0 ]; then
	echo "USBKEY device ${USBKEY_DEV} is bootable" | tee -a ${LOG}
else
	echo "WARNING: USBKEY device ${USBKEY_DEV} is not yet bootable!" | tee -a ${LOG}
	USBKEY_PAR=`grep -i fat16 ${TMP_DIR}/usbkey_fdisk | awk '{print $1}' | tr [A-Za-z/] " " | awk '{print $1}'` # should now only contain a nr
	echo parted -s ${USBKEY_DISK} set ${USBKEY_PAR} boot on | tee -a ${LOG}
	parted -s ${USBKEY_DISK} set ${USBKEY_PAR} boot on
fi
fdisk -l ${USBKEY_DISK} >${TMP_DIR}/usbkey_fdisk 2>/dev/null
grep -i fat16 ${TMP_DIR}/usbkey_fdisk | grep -q "*" 2>/dev/null
if [ $? -ne 0 ]; then
	Fail "USBKEY device ${USBKEY_DEV} is not yet bootable. Do it manually with fdisk"
fi
}
#-----<--------->-------

Check_USBKEY_MBR () {
USBKEY_DISK=`echo ${USBKEY_DEV} | tr [0-9] " "` # /dev/sdb1 becomes /dev/sdb
dd if=${USBKEY_DISK} bs=512 count=1 | strings | grep -iq GRUB 2>/dev/null
if [ $? -eq 0 ]; then
	echo "USBKEY device ${USBKEY_DEV} contains a valid MBR"  tee -a ${LOG}
else
	echo "WARNING: USBKEY device ${USBKEY_DEV} does not have a valid MBR" | tee -a ${LOG}
	if [ -f ${SYSLINUXPATH}/mbr.bin ]; then
		echo cat ${SYSLINUXPATH}/mbr.bin > ${USBKEY_DISK} | tee -a ${LOG}
		cat ${SYSLINUXPATH}/mbr.bin > ${USBKEY_DISK} 
	else
		Fail "${SYSLINUXPATH}/mbr.bin missing - please check syslinux rpm"
	fi
fi
}
#-----<--------->-------
