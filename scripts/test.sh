#!/bin/bash
# Before running this script please ensure that your PATH is
# typical as you use for compilation/installation. I use
# /bin /sbin /usr/bin /usr/sbin /usr/local/bin, but it may
# differ on your system.
# $Id: test.sh,v 1.97 2008/08/26 09:16:26 gdha Exp $
. ./Config.sh 2>/dev/null

echo $PATH
Usage () {
echo "`basename $0`: test mkCDrec readiness"
echo -e "\t-h: print this help"
echo -e "\t-v: print information on tool versions"
exit
}

ver_linux () {
# script taken from linux source tree
echo '-- Versions installed: (if some fields are empty or looks'
echo '-- unusual then possibly you have very old versions)'
uname -a
insmod -V  2>&1 | awk 'NR==1 {print "Kernel modules        ",$NF}'
echo "Gnu C                 " `gcc --version`
ld -v 2>&1 | awk -F\) '{print $1}' | awk \
      '/BFD/{print "Binutils              ",$NF}'
ls -l `ldd /bin/sh | awk '/libc/{print $3}'` | sed -e 's/\.so$//' \
  | awk -F'[.-]'   '{print "Linux C Library        " $(NF-2)"."$(NF-1)"."$NF}'
echo -n "Dynamic linker         "
ldd -v > /dev/null 2>&1 && ldd -v || ldd --version |head -1
ls -l /usr/lib/lib{g,stdc}++.so  2>/dev/null | awk -F. \
       '{print "Linux C++ Library      " $4"."$5"."$6}'
ps --version 2>&1 | awk 'NR==1{print "Procps                ", $NF}'
mount --version | awk -F\- '{print "Mount                 ", $NF}'
hostname -V 2>&1 | awk 'NR==1{print "Net-tools             ", $NF}'
# Kbd needs 'loadkeys -h',
loadkeys -h 2>&1 | awk \
'(NR==1 && ($3 !~ /option/)) {print "Kbd                   ", $3}'
# while console-tools needs 'loadkeys -V'.
loadkeys -V 2>&1 | awk \
'(NR==1 && ($2 ~ /console-tools/)) {print "Console-tools         ", $3}'
expr --v | awk 'NR==1{print "Sh-utils              ", $NF}'
X=`cat /proc/modules | sed -e "s/ .*$//"`
echo "Modules Loaded         "$X
ulimit -a
}

check_exe() {
  found=`which $1 2>/dev/null`
  echo ${found} | grep which >/dev/null 2>&1
  if [ $? -eq 0 ]; then
     # which: no nasm in ... is printed to stdout (should be stderr)
     found=""
  fi
  if [ `echo ${1} | wc -c` -lt 4 ];
  then
        et="\t"
  elif [ `echo ${1} | wc -c` -lt 8 ];
  then
        et="\t"
  else
        et=""
  fi
  if [ -z ${found} ]; then
     echo -n "${1}:"
     echo -e "${et}\t\t\t\t\t\t\t${fail}Not found${c_norm}"
     case ${1} in
        rsh|ssh) echo -e "${c_bold}${1}${c_norm}: must have rsh or ssh.";;
        sfdisk) echo -e "${c_bold}${1}${c_norm}: must have (force stop)."
                TestErrCount=$((TestErrCount + 1))
                ;;
        ash|mformat|mkisofs|${CDRECORD}) 
                echo -e "${c_bold}${1}${c_norm}: must have (force stop)"
                TestErrCount=$((TestErrCount + 1))
                ;;
        mt) echo -e "${c_bold}${1}${c_norm}: needed with tape back-up!";;
        genromfs)
                if [ "${INITRD_FS}" = "romfs" ]; then
                  echo -e "${c_bold}${1}${c_norm}: optional"
                fi
                ;;
        openssl) echo -e "${c_bold}${1}${c_norm}: needed for encryption!";;
        *) echo -e "${c_bold}${1}${c_norm}: must have it!";;
     esac
  #else
    # echo -e "${et}\t\t\t\t\t\t\t${passed}Found${c_norm}"
  fi
}

Fallback_method_to_find_ATA_cdrom () {
if [ ${kernel_minor_nr} -eq 6 ] && [ ! -f /tmp/CDR.found ] ; then
   for ATA_CD in hda hdb hdc hdd hde
   do
        ${CDRECORD} -atip dev=/dev/${ATA_CD} 2>/dev/null >/tmp/cdr.$$
        if egrep -q "TAO|CD-RW|CDRW|BURN" /tmp/cdr.$$ ; then
                echo /dev/${ATA_CD} > /tmp/CDR.found
        fi
   done
fi
}

Matching_SCSIDEVICE_or_not () {
# input check of: CDwriter_dev=`cat /tmp/CDR.found 2>/dev/null`
# with SCSIDEVICE setting in Config.sh
if [ ! -z "${CDwriter_dev}" ]; then
   echo -e "\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
   touch /tmp/cdr.$$   # cdr found
   if [ x${SCSIDEVICE} != x${CDwriter_dev} ]; then
        echo -e "\t${fail}Warning:${c_norm} Set your SCSIDEVICE to ${CDwriter_dev} in Config.sh"
   fi
else
   echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
   echo -e "\t${fail}Warning:${c_norm} Edit Config.sh and change BURNCDR to \"n\""
   TestErrCount=$((TestErrCount + 1))
fi # end of [ ! -z "${CDwriter_dev}" ];
}

#################
#### M A I N ####
#################
# set onlcr to avoid staircase effect and do not lock scrolling
stty onlcr -ixon #0>&1

loop=true
while ($loop); do
  case $1 in
        -h*)    Usage;;
        -v*)    ver_linux
                exit;;
        *)      loop=false
  esac
done

clear
# Intro: print banner of mkCDrec version
VERSION="`cat VERSION | cut -d_ -f 2`"
echo -ne "${c_bold}make test output of mkCDrec ${VERSION} ${c_norm}\n"

# Create an TestErrCount variable which
#       0 = /tmp/.mkcdrec.tests.passed
#       1 = /tmp/.mkcdrec.tests.not.passed
# will be created at the end. test is now part of the Makefile
TestErrCount=0

# what is the minor nr of the kernel? (2,3,4,5,6,...)
kernel_minor_nr=`uname -r | cut -d. -f2`

# test 1: are we root?
echo -en "${c_bold}Test 1${c_norm}:  Are we root?"
if [ `id --user` -ne 0 ]; then
        echo -e "\t\t\t\t\t\t${fail}Failed${c_norm}\n"
        exit 1
fi
echo -e "\t\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"

# test 2: do we have all executables mkCDrec needs during build?
echo -en "${c_bold}Test 2${c_norm}:  missing executables needed by mkCDrec"

# check first of all if the command /usr/bin/which is available otherwise
# all the check_exe commands will fail!
if [ ! -f /usr/bin/which ]; then
   echo -e "\t\t\t${fail}Failed${c_norm}
         Command ${c_bold}/usr/bin/which${c_norm} not found. Must have it!\n"
   exit 1
else
   echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
fi
check_exe dd
check_exe mount
check_exe bc
check_exe umount
[ ! -f ${MKCDREC_DIR}/busybox/busybox ] && check_exe gcc
check_exe ldd
check_exe ${MAKEDEV}
check_exe ${MKISOFS}
check_exe ${CDRECORD}
check_exe mt
check_exe ash
check_exe bzip2
check_exe gzip
check_exe rsync
check_exe ${REMOTE_COMMAND}
if [ "${INITRD_FS}" = "romfs" ]; then
   check_exe genromfs
fi
check_exe file
check_exe openssl
if [ x${BOOTARCH} = xx86 ]; then
        check_exe sfdisk
        if [ "${FORCE_SYSLINUX}" = "false" ]; then
           # now we need isolinux.bin
           if [ ! -f "${ISOLINUX}" ]; then
              echo -en "${c_bold}isolinux.bin${c_norm}: please add correct path in Config.sh or install syslinux\n"
              TestErrCount=$((TestErrCount + 1))
           fi
        else
           # use syslinux
           check_exe mformat
           check_exe syslinux
        fi
elif [ x${BOOTARCH} = xx86_64 ]; then
	check_exe sfdisk
	if [ ! -f "${ISOLINUX}" ]; then
	   echo -en "${c_bold}isolinux.bin${c_norm}: please add correct path in Config.sh"
	   TestErrCount=$((TestErrCount + 1))
	fi
elif [ x${BOOTARCH} = xnew-powermac ]; then
        check_exe ybin
        check_exe hmount
        check_exe hattrib
        check_exe humount
elif [ x$${BOOTARCH} = xia64 ]; then
        check_exe parted
elif [ x$${BOOTARCH} = xsparc ]; then
        check_exe parted
fi
if [  ${DVD_Drive} -eq 1 ]; then
        check_exe growisofs
fi

TarSubVer=`tar --version | head -n 1 | cut -d" " -f4- | cut -d. -f2`
if [ ${TarSubVer} -lt 12 ]; then
   echo -en "${c_bold}tar${c_norm}: please upgrade "
   tar --version | head -n 1
fi

# important to check version of mkisofs for DVD support
MkisofsMajVer=`${MKISOFS} -version | head -n 1 | cut -d" " -f 2| cut -d. -f1`
#MkisofsMinVer=`${MKISOFS} -version | head -n 1 | cut -d" " -f 2| cut -d. -f2`
MkisofsMinVer=`${MKISOFS} -version | head -n 1 | cut -d" " -f 2| cut -d. -f2| cut -b -2`
case ${MkisofsMajVer} in
        1) if [ ${MkisofsMinVer} -lt 14 ]; then
                echo -en "${c_bold}${MKISOFS}${c_norm}: please upgrade "
                ${MKISOFS} -version
                TestErrCount=$((TestErrCount + 1))
           fi
           ;;
        2) # version 2.x is fine
           ;;
        *) echo -en "${c_bold}${MKISOFS}${c_norm}: unknown version "
           ${MKISOFS} -version
           TestErrCount=$((TestErrCount + 1))
           ;;
esac

# test 3: check the allowed fs for INITRD_FS
echo -en "${c_bold}Test 3${c_norm}:  Filesystem for Initial ramdisk allowed?"
case ${INITRD_FS} in
 ext2|minix|romfs|ramfs|cramfs)
   echo -en "${c_bold}${passed}\t\tPassed${c_norm}\n"
   ;;
 *)
   echo -en "${c_bold}${fail}\t\tFAILED${c_norm}\n"
   echo -en "Please change INITRD_FS into ext2, minix, romfs or cramfs in Config.sh\n"
   TestErrCount=$((TestErrCount + 1))
   ;;
esac


# test 4: does the loopback device work?
echo -en "${c_bold}Test 4${c_norm}:  loopback device works?"
mkdir -p test.$$
err=0
modprobe loop >/dev/null 2>&1   # module? (gdha, 28/04/2001)
for FileSystem in `echo ${ROOT_FS} ${INITRD_FS} | tr " " "\n"| egrep -v "romfs|ramfs|cramfs" | sort| uniq`
do
dd if=/dev/zero of=${TMP_DIR}/loopback bs=1k count=$((${RAMDISK_SIZE}*1024)) >/dev/null 2>&1
err=$?
case ${FileSystem} in
  minix) /sbin/mkfs.minix ${TMP_DIR}/loopback -i $((2*1024)) > /dev/null 2>&1
        err=$(($? + $err))
        ;;
  ext2) /sbin/mkfs.ext2 -Fq ${TMP_DIR}/loopback -m 0 -N $((2*1024)) > /dev/null 2>&1
        err=$(($? + $err))
        ;;
  ext3) /sbin/mkfs.ext3 -j -Fq ${TMP_DIR}/loopback -m 0 -N $((2*1024)) > /dev/null 2>&1
        err=$(($? + $err))
        ;;
  msdos|vfat) echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}\n"
              echo -e "Oops! Are you serious? I refuse to continue with ${fail}${c_bold}${FileSystem}${c_norm} as root fs\n"
              echo "Modify the Config.sh ROOT_FS or INITRD_FS entry"
              exit 255 # total loss
        ;;
  xfs|jfs) echo -e "\t\t\t\t${fail}${c_bold}FAILED${c_norm}\n" 
            echo -e "${fail}${c_bold}${ROOT_FS}${c_norm} is not yet supported on non-block devices!\n"
           TestErrCount=$((TestErrCount + 1))
        ;;
  reiserfs) echo y | /sbin/mkreiserfs -fq ${TMP_DIR}/loopback > /dev/null 2>&1
            # RAMDISK_SIZE must be at least 34 !!
            if [ $? -ne 0 ]; then
                echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}\n" 
                echo -e "${fail}${c_bold}${FileSystem}${c_norm} is not yet supported on non-block devices!\n"
                echo "Modify the Config.sh ROOT_FS entry to ext2, ext3"
                exit 1 # too bad
            fi
        ;;
 *) echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}\n"
    echo -e "Oops! Filesystem ${fail}${c_bold}${FileSystem}${c_norm} not yet supported on loopback devices\n"
    echo -e "If you think otherwise then submit a bug report at Sourceforge\n"
    exit 1 # forced exit
    ;;
esac
/bin/mount -o loop -t ${FileSystem} ${TMP_DIR}/loopback test.$$ > /dev/null 2>&1
err=$(($? + $err))

if [ $err -ne 0 ]; then
   echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}\n"
   echo "Oops! A problem with the loopback device, or with ${FileSystem} filesystem support in your kernel."
   echo "Loopback device support (N/m/y/?) y or m"
   echo "Also check if ${ROOT_FS} or ${INITRD_FS} are supported by your kernel."
   echo "Or, check if RAMDISK_SIZE (${RAMDISK_SIZE}) is big enough for your fs"
   echo "Recompile your kernel if needed before running 'make test' again."
   TestErrCount=$((TestErrCount + 1))
fi
umount test.$$ 2>/dev/null
done
rm -f ${TMP_DIR}/loopback
rm -rf test.$$
if [ $err -eq 0 ]; then
   echo -e "\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
else
   exit 1 # makes no sense to continue - fix the kernel first
fi

# test 5: is the ram device available for use?
echo -en "${c_bold}Test 5${c_norm}:  ram device available"
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
echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}\n"
echo "Please recompile kernel and enable options:
Loopback device support (N/m/y/?) y or m
Ram disk support (N/m/y/?) y
Initial Ram disk (initrd) support (N/y/?) y

After a successful rebuild try again ;-)"
TestErrCount=$((TestErrCount + 1))
fi
echo -e "\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"

# test 6: romfs support by the kernel? (optional)
echo -en "${c_bold}Test 6${c_norm}:  romfs supported  by the kernel?"
if [ "${INITRD_FS}" = "romfs" ]; then
   mkdir -p test.$$
   genromfs -d . -f ROMFS >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo -e "\t${fail}Warning${c_norm}: genromfs not found!"
   fi
   mount -o loop -t romfs ROMFS test.$$ >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo -e "\t\t\t${fail}${c_bold}FAILED${c_norm}"
      echo -e "\t${fail}Warning${c_norm}: Please add ROMFS support to your kernel!"
      TestErrCount=$((TestErrCount + 1))
   else
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   fi
   umount test.$$
   rm -r test.$$ ROMFS
else
   echo -e "\t\t\t${passed}${c_bold}N/A${c_norm}"
fi

# test 7: cramfs support?
echo -en "${c_bold}Test 7${c_norm}:  cramfs supported  by the kernel?"
if [ "${INITRD_FS}" = "cramfs" ]; then
   mkdir -p test.$$
   cp VERSION test.$$/
   mkcramfs test.$$  CRAMFS >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo -e "\t${fail}Warning${c_norm}: mkcramfs not found!"
      TestErrCount=$((TestErrCount + 1))
   fi
   mount -o loop -t cramfs CRAMFS test.$$ >/dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo -e "\t\t\t${fail}${c_bold}FAILED${c_norm}"
      echo -e "\t${fail}Warning${c_norm}: Please add cramfs support to your kernel!"
      TestErrCount=$((TestErrCount + 1))
   else
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   fi
   umount test.$$
   rm -r test.$$ CRAMFS
else
   echo -e "\t\t\t${passed}${c_bold}N/A${c_norm}"
fi

# test 8: strip is mandotary (binutils)
echo -en "${c_bold}Test 8${c_norm}:  strip (from binutils) available?"
found=`which strip 2>/dev/null`
if [ -z ${found} ]; then
     echo -e "\t\t\t\t\t${fail}Not found${c_norm}"
     echo -e "Please install the latest binutils which are available from:"
     echo -e "http://www.gnu.org/software/binutils/binutils.html or"
     echo -e "from your Linux distributions CDs.\n"
     TestErrCount=$((TestErrCount + 1))
else
     echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
fi

# test 9: big kernel? ED/HD setting in Config.sh
# which kernel are we using?
echo -en "${c_bold}Test 9${c_norm}:  BOOT_FLOPPY_DENSITY=${BOOT_FLOPPY_DENSITY} ok?"
if [ "${FORCE_SYSLINUX}" = "true" ]; then
# only check kernel size for bootflop.img
#--#
if [ -z ${LINUX_KERNEL} ]; then
   Find_Linux_kernel    # lilo or grub way of finding kernel file
fi
kernel_size=`ls -lL ${LINUX_KERNEL} | awk '{print $5}'` # in bytes
# to be on the safe side my trigger is at 800Kb (it depends said the consultant)
if [ ${kernel_size} -gt 800000 ] && [ "${BOOT_FLOPPY_DENSITY}" = "HD" ]; then
  echo -e "\n${fail}Warning:${c_norm} Edit Config.sh and change BOOT_FLOPPY_DENSITY=HD"
  echo "into BOOT_FLOPPY_DENSITY=ED (or H1722)"
  echo -e "${fail}Warning:${c_norm} Change PROMPT_BOOT_FLOPPY=0 for ED (2.88 Mb)"
  TestErrCount=$((TestErrCount + 1))
else
  echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
fi
#--#
else # [ "${FORCE_SYSLINUX}" = "true" ]
  # no need to check with isolinux
  echo -e "\t\t\t\t${passed}${c_bold}N/A${c_norm}"
fi # [ "${FORCE_SYSLINUX}" = "true" ]

# Test 10: cdrecord -scanbus ?
echo -en "${c_bold}Test 10${c_norm}: cdrecord -scanbus"
rm -f /tmp/CDR.found
if [ "${BURNCDR}" = "y" ]; then
   if [ ! -x `which ${CDRECORD}` ]; then        # cdrecord not found
      echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
      echo -e "\t${fail}Warning:${c_norm} Edit Config.sh and change BURNCDR to \"n\""
      echo "CDRECORD=${CDRECORD} was not found! Check your Config.sh file"
      echo "Or, if you are sure you have a working CDR then define your SCSIDEVICE."
      TestErrCount=$((TestErrCount + 1))
   else # cdrecord found
      ${CDRECORD} -scanbus >/tmp/cdrecord.scan 2>/dev/null
      case `echo $?` in
        255) DEVOPTS="dev=ATAPI"        # maybe ATAPI and 2.4.x kernel
             ATAPI="ATAPI:" ;;
          *) DEVOPTS=""         # SCSI (ide-scsi) or maybe ATA 2.6.x kernel
             ATAPI="" ;;
      esac
      # do a double check on the return code as it could be ATA explicit too
      ${CDRECORD} ${DEVOPTS} -scanbus >/tmp/cdrecord.scan 2>/dev/null
      case `echo $?` in
        255) DEVOPTS="dev=ATA"
             ATAPI="ATA" ;;
          *) ;; # do nothing
      esac
      ${CDRECORD} ${DEVOPTS} -scanbus >/tmp/cdrecord.scan 2>/dev/null
      case `echo $?` in
        0) 
           grep "CD-R" /tmp/cdrecord.scan >/tmp/cdrecord.CDR 2>&1
           if [ $? -eq 0 ]; then
                cat /tmp/cdrecord.CDR | { while read Line
                do
                  CDEV=`echo ${Line} | awk '{print $1}'`
                  # Changed "CD-R" into "TAO" as a generic CD-ROM is also CD-R
                  ${CDRECORD} -atip dev=${ATAPI}${CDEV} 2>/dev/null >/tmp/cdr.$$
                  if egrep -q "TAO|CD-RW|CDRW|DVD-RW|BURN" /tmp/cdr.$$ ; then
                        echo ${ATAPI}${CDEV} > /tmp/CDR.found
                  fi
                done
                }
                # if no CD found try the following trick
                Fallback_method_to_find_ATA_cdrom     # subroutine
                CDwriter_dev=`cat /tmp/CDR.found 2>/dev/null`
                Matching_SCSIDEVICE_or_not # subroutine
           else
                # before giving up do a desperate attempt to find a CDwriter
                Fallback_method_to_find_ATA_cdrom
                if [ -f /tmp/CDR.found ]; then
                   CDwriter_dev=`cat /tmp/CDR.found 2>/dev/null`
                   Matching_SCSIDEVICE_or_not # subroutine
                else
                   echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
                   echo -e "\t${fail}Warning:${c_norm} Edit Config.sh and change BURNCDR to \"n\""
                   TestErrCount=$((TestErrCount + 1))
                fi # end of [ -f /tmp/CDR.found ];
           fi
           ;;
        *) # before giving up do a desperate attempt to find a CDwriter
           Fallback_method_to_find_ATA_cdrom
           if [ -f /tmp/CDR.found ]; then
              CDwriter_dev=`cat /tmp/CDR.found 2>/dev/null`
              Matching_SCSIDEVICE_or_not # subroutine
           else
              echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
              echo -e "\t${fail}Warning:${c_norm} Edit Config.sh and change BURNCDR to \"n\""
              TestErrCount=$((TestErrCount + 1))
           fi # end of if [ -f /tmp/CDR.found ]
           ;;
      esac
   fi
   #rm -f /tmp/cdrecord.scan /tmp/cdrecord.CDR /tmp/cdr.$$ /tmp/CDR.found
   if [ -f /tmp/TestErrCount ]; then
        TestErrCount=`cat /tmp/TestErrCount`
        rm -f /tmp/TestErrCount
   fi
  
   if [  ${DVD_Drive} -eq 1 ]; then
      if [ ! -x `which growisofs 2>/dev/null` ]; then
         echo -e "\t${fail}Warning:${c_norm} growisofs not found! Edit Config.sh and change DVD_Drive to \"0\"" 
         TestErrCount=$((TestErrCount + 1))
      fi
      ${CDRECORD} ${DEVOPTS} -scanbus 2>/dev/null|grep -i dvd|grep -v dvdrtools >/dev/null
      if [ $? -ne 0 ]; then
         echo -e "\t${fail}Warning:${c_norm} No DVD writer found. Please change  DVD_Drive to \"0\" in Config.sh"
         TestErrCount=$((TestErrCount + 1))
      fi
      # check available space in ISOFS_DIR
      Space_free_in_ISOFS_DIR=`df -P $ISOFS_DIR| tail -n 1 | awk '{print $4}'`
      if [ ${Space_free_in_ISOFS_DIR} -lt ${MAXCDSIZE} ]; then
         echo -e "\t${fail}Warning:${c_norm} Maybe not enough free space to built a 4.7 GB DVD"
      fi
   fi 
else
   # BURNCDR=n
   echo -e "\t\t\t\t\t${passed}${c_bold}N/A${c_norm}"
fi
# Test 11: do we have Linux header file needed to compile BusyBox/sfdisk
echo -en "${c_bold}Test 11${c_norm}: Header files present?"
if [ ! -f /usr/include/linux/errno.h ] || [ ! -f /usr/include/linux/fs.h ]; then
   echo -e "\t\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
   echo -e "\t${fail}Warning:${c_norm} Please download and install the linux header files."
   #TestErrCount=$((TestErrCount + 1))
else
   echo -e "\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
fi

# Test 12: check DEVFS capabilities if required
echo -en "${c_bold}Test 12${c_norm}: DEVFS supported by kernel?"

DEVFSD=`ps ax | grep devfsd | grep -v grep 2>/dev/null`

if [ "x${DEVFS}" = "x1"  -a ! -z "${DEVFSD}" ]; then
        echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
        grep devfs /proc/cmdline >/dev/null  && \
        echo -e "\t${fail}Warning:${c_norm} Check Config.sh variable KERNEL_APPEND=\" devfs=mount\""
elif [ "x${DEVFS}" = "x0" -a ! -z "${DEVFSD}" ]; then
   echo -e "\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
   echo -e "\t${fail}Warning:${c_norm} Edit Config.sh and make DEVFS=1"
   TestErrCount=$((TestErrCount + 1))
elif [ "x${DEVFS}" = "x0" -a  -z "${DEVFSD}" ]; then
   echo -e "\t\t\t\t${passed}${c_bold}N/A${c_norm}"
else
   echo -e "\t\t\t\t${fail}${c_bold}FAILED${c_norm}"
   echo -e "\t${fail}Warning:${c_norm} Edit Config.sh and make DEVFS=0"
   TestErrCount=$((TestErrCount + 1))
fi

# Test 13: check filesystem tools on mounted fs
# FIXME: exclude mount-points listed in EXCLUDE_DIRS
echo -en "${c_bold}Test 13${c_norm}: filesystem tools present?\n"
Mount_v=`mount -v | egrep -v "proc|devpts|autofs|iso9660|tmpfs|loop=" | awk '{print $5}' | uniq`
for FS in `echo ${Mount_v} ${ROOT_FS} ${INITRD_FS} | tr " " "\n" | sort | uniq`
do
    err=0
    case ${FS} in
        ext2|ext3|minix|msdos|xfs|jfs)
                for exe in fsck.${FS} mkfs.${FS}
                do
                  which $exe >/dev/null 2>&1
                  err=$(($err + $?))
                  if [ $? -ne 0 ]; then
                     echo -e "\t${c_bold}${FS}${c_norm}:\t\t\t\t\t${fail}$exe not found${c_norm}"
                     TestErrCount=$((TestErrCount + 1))
                  fi
                done
                if [ $err -eq 0 ]; then
                   echo -e "\t${c_bold}${FS}${c_norm}:\t\t\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
                fi
                ;;
        vfat)
                for exe in dosfsck mkfs.msdos
                do
                  which $exe >/dev/null 2>&1
                  err=$(($err + $?))
                  if [ $? -ne 0 ]; then
                     echo -e "\t${c_bold}${FS}${c_norm}:\t\t\t\t\t${fail}$exe not found${c_norm}"
                     TestErrCount=$((TestErrCount + 1))
                  fi
                done
                if [ $err -eq 0 ]; then
                   echo -e "\t${c_bold}${FS}${c_norm}:\t\t\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
                fi
                ;;
        reiserfs)
                for exe in mkreiserfs reiserfsck
                do
                  which $exe >/dev/null 2>&1
                  err=$(($err + $?))
                  if [ $? -ne 0 ]; then
                     echo -e "\t${c_bold}${FS}${c_norm}:\t\t\t\t\t${fail}$exe not found${c_norm}"
                     TestErrCount=$((TestErrCount + 1))
                  fi
                done
                if [ $err -eq 0 ]; then
                   echo -e "\t${c_bold}${FS}${c_norm}:\t\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
                fi
                ;;
        *) # other fs as nfs, smbfs, romfs we simply ignore
                ;;
    esac
done

# Test 14: check initrd (must be in kernel)
echo -en "${c_bold}Test 14${c_norm}: initrd must be compiled in kernel!"
[ -z "${LINUX_VERSION}" ] && LINUX_VERSION=`uname -r`
cat /proc/cmdline >/tmp/cmdline
grep BOOT_FILE /tmp/cmdline >/dev/null 2>&1
if [ $? -eq 0 ]; then
   BOOT_FILE_NAME=`cat /tmp/cmdline | sed -e 's/^.*BOOT_FILE=//' | sed -e 's/ .*$//'`
   if [ -L "$BOOT_FILE_NAME" ]; then
      # Translate the boot file symlink to a real filename (Debian)
      BOOT_FILE_NAME=`ls -L "$BOOT_FILE_NAME" | sed 's/^.* -> //'`
   fi
   # at this point is e.g. BOOT_FILE_NAME=/boot/vmlinuz-2.4.7
   # usual the kernel name starts with vmlin, but it could also be bzImage
   KERNEL_NAME=`echo $BOOT_FILE_NAME| cut -d/ -f2-|cut -d/ -f2-|cut -d/ -f2-`
   BOOT_DIR=`echo $BOOT_FILE_NAME | sed -e 's/'${KERNEL_NAME}'.*//'`
   grep initrd ${BOOT_DIR}/System.map-${LINUX_VERSION} >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   else
      echo -e "\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -e "\tMake \"CONFIG_BLK_DEV_INITRD=y\" in /usr/src/linux/.config"
      echo -e "\tand recompile the kernel."
      TestErrCount=$((TestErrCount + 1))
   fi
elif [ -f /boot/config-${LINUX_VERSION} ]; then
   # maybe we're lucky?
   grep "INITRD=y" /boot/config-${LINUX_VERSION} >/dev/null 2>&1
   if [ $? -eq 0 ]; then
         echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   else
      echo -e "\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -e "\tMake \"CONFIG_BLK_DEV_INITRD=y\" in /usr/src/linux/.config"
      echo -e "\tand recompile the kernel."
      TestErrCount=$((TestErrCount + 1))
   fi
elif [ -f /boot/System.map-${LINUX_VERSION} ]; then
   # Mandrake does not show a BOOT_DIR
   grep initrd /boot/System.map-${LINUX_VERSION} >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   else
      echo -e "\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -e "\tMake \"CONFIG_BLK_DEV_INITRD=y\" in /usr/src/linux/.config"
      echo -e "\tand recompile the kernel."
      TestErrCount=$((TestErrCount + 1))
   fi
elif [ -L /boot/System.map ]; then
   # follow the symbolic link if any to the real map
   grep initrd /boot/System.map >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   else
      echo -e "\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -e "\tMake \"CONFIG_BLK_DEV_INITRD=y\" in /usr/src/linux/.config"
      echo -e "\tand recompile the kernel."
      TestErrCount=$((TestErrCount + 1))
   fi
elif [ -f /usr/src/linux/.config ]; then
   grep "CONFIG_BLK_DEV_INITRD=y" /usr/src/linux/.config >/dev/null 2>&1
   if [ $? -eq 0 ]; then
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   else
      echo -e "\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -e "\tMake \"CONFIG_BLK_DEV_INITRD=y\" in /usr/src/linux/.config"
      echo -e "\tand recompile the kernel."
      TestErrCount=$((TestErrCount + 1))
   fi
else
   echo -e "\t\t\t${c_bold}${fail}Warning${c_norm}"
   echo -e "\t${c_bold}Check manual${c_norm}:\t/usr/src/linux/.config file"
   TestErrCount=$((TestErrCount + 1))
fi
rm -f /tmp/cmdline

# Test 15: check amount of memory present for compression speed
MemBytes=`cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}'`
MemMBytes=`expr ${MemBytes} / 1000`
echo -en "${c_bold}Test 15${c_norm}: Amount of memory available"
if [ ${MemMBytes} -lt 128 ]; then
   echo -en "${c_bold}${failed}\t\t\t${MemMBytes} Mb${c_norm}\n"
   echo -en "\tPlease use ${c_bold}CMP_PROG_OPT=\"-6cv\"${c_norm} in Config.sh\n"
else
   echo -en "\t${c_bold}${passed}\t\t\t${MemMBytes} Mb${c_norm}\n"
fi

# Test 16: is scripts/Config.sh a link or file
echo -en "${c_bold}Test 16${c_norm}: scripts/Config.sh a link?"
if [ -L scripts/Config.sh ]; then
   echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
else
   echo -e "\t\t\t\t${c_bold}${fail}Warning${c_norm}"
   echo -en "\tWill correct it immediately!\n"
   rm -f scripts/Config.sh
   ln -s ../Config.sh scripts/Config.sh
fi

# Test 17: check serial console in use or not
echo -en "${c_bold}Test 17${c_norm}: serial console"
if [ -z "${SERIAL}" ]; then
   echo -e "\t\t\t\t\t\t${passed}${c_bold}N/A${c_norm}"
else
   stty -F /dev/${SERIAL} 1>/dev/null 2>&1
   if [ $? -eq 0 ]; then
      # OK, serial port active, now check current baudrate
      Speed=`stty -F /dev/${SERIAL} | grep speed | awk '{print $2}'`
      if [ "${Speed}" = "${BAUDRATE}" ]; then
         echo -e "\t\t\t\t\t\t${passed}${c_bold}Passed${c_norm}"
      else
         echo -e "\t\t\t\t\t\t${c_bold}${fail}Failed${c_norm}"
         echo -en "\t${c_bold}${fail}Warning${c_norm}:"
         echo -e "\t${c_bold}Check Config.sh${c_norm}: Set BAUDRATE to ${Speed}"
         TestErrCount=$((TestErrCount + 1))
      fi
   else
      echo -e "\t\t\t\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -en "\t${c_bold}${fail}Warning${c_norm}:"
      echo -e "\t${c_bold}Check Config.sh${c_norm}: Set SERIAL accordingly"
      TestErrCount=$((TestErrCount + 1))
   fi
fi

# Test 18: which arch?
echo -en "${c_bold}Test 18${c_norm}: supported architecture?"
GetBootArch # returns barch

if [ "${BOOTARCH}" != "${barch}" ]; then
        echo -e "\t\t\t\t${c_bold}${fail}Failed${c_norm}"
        TestErrCount=$((TestErrCount + 1))
        if [ "${barch}" = "Unsupported" ]; then
          echo -en "\t${c_bold}${fail}Fatal${c_norm}:"
          echo -e "\t${c_bold}Architecture NOT supported by mkCDrec.${c_norm}"
        else
          echo -en "\t${c_bold}${fail}Warning${c_norm}:"
          echo -e "\t${c_bold}Check Config.sh${c_norm}: Set BOOTARCH to ${barch}"
        fi
else
        echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
fi

# Test 19: is RAMDISK_SIZE big enough?
echo -en "${c_bold}Test 19${c_norm}: is RAMDISK_SIZE=${RAMDISK_SIZE} big enough?"
case ${kernel_minor_nr} in
    5|6)# Kernel 2.6.x needs a ramdisk bigger than 32 Mb
        if [ ${RAMDISK_SIZE} -lt 64 ]; then
           echo -e "\t\t\t\t${c_bold}${fail}Failed${c_norm}"
           echo -en "\t${c_bold}${fail}Critical:${c_norm}:"
           echo -e "\t${c_bold}Check Config.sh${c_norm}: Set RAMDISK_SIZE to 64"
           echo -e "\t${c_bold}Warning${c_norm}: Please install mkcdrec_utilities!"
           TestErrCount=$((TestErrCount + 1))
        else
           echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
        fi
        ;;
    4)  # Kernel 2.2/4 are happy with 32 Mb
        if [ ${RAMDISK_SIZE} -lt 32 ]; then
           echo -en "\t${c_bold}${fail}Warning${c_norm}:"
           echo -e "\t${c_bold}Check Config.sh${c_norm}: Set RAMDISK_SIZE to 32"
        else
           echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
        fi
        ;;
    *)  # Kernel 2.x (where is lower than 4)
        echo -e "\t\t\t\t${passed}${c_bold}Passed${c_norm}"
        ;;
esac
if [ "${ADD_PERL}" = "true" ]; then
   # check size of perl
   PERL_VERSION=`perl -v | head -2 | tail -n 1 | awk '{print $4}' | sed -e 's/v//'`
   Estimated_Perl_Size=`du -sk /usr/lib/perl5/${PERL_VERSION} |awk '{print $1}'`
   if [ ${Estimated_Perl_Size} -gt 28500 ]; then
      # probably a good idea to increase RAMDISK_SIZE of disable PERL
      echo -e "\t${fail}Warning${c_norm}: ADD_PERL=true and you run the risk of running
        out of space in the ramdisk (perl size = ${Estimated_Perl_Size}).
        You have two options:
                1) increase RAMDISK_SIZE, or
                2) set ADD_PERL=false
        both in the Config.sh file."
   fi
fi

# test 20 - CONFIG_BLK_DEV_RAM_SIZE check (best effort)
echo -en "${c_bold}Test 20${c_norm}: is BLK_DEV_RAM_SIZE big enough for initrd?"
IssueINITRDSizeWarning=0
if [ -f /proc/config ]; then
        BLK_DEV_RAM_SIZE=`grep BLK_DEV_RAM_SIZE /proc/config | cut -d= -f2`
        [ ${BLK_DEV_RAM_SIZE} -gt ${INITRDSIZE} ] && IssueINITRDSizeWarning=1
        [ ${BLK_DEV_RAM_SIZE} -lt ${INITRDSIZE} ] && IssueINITRDSizeWarning=1
elif [ -f /proc/config.gz ]; then
        BLK_DEV_RAM_SIZE=`zcat /proc/config.gz | grep BLK_DEV_RAM_SIZE | cut -d= -f2`
        [ ${BLK_DEV_RAM_SIZE} -gt ${INITRDSIZE} ] && IssueINITRDSizeWarning=1
        [ ${BLK_DEV_RAM_SIZE} -lt ${INITRDSIZE} ] && IssueINITRDSizeWarning=1
elif [ -f /boot/config-${LINUX_VERSION} ]; then
        BLK_DEV_RAM_SIZE=`grep BLK_DEV_RAM_SIZE /boot/config-${LINUX_VERSION} | cut -d= -f2`
        [ ${BLK_DEV_RAM_SIZE} -gt ${INITRDSIZE} ] && IssueINITRDSizeWarning=1
        [ ${BLK_DEV_RAM_SIZE} -lt ${INITRDSIZE} ] && IssueINITRDSizeWarning=1
else
        BLK_DEV_RAM_SIZE="default"
fi
echo  -e "\t\t${passed}${BLK_DEV_RAM_SIZE}${c_norm}"
if [ ${IssueINITRDSizeWarning} -eq 1 ]; then
   echo -e "\t${fail}Warning${c_norm}: You may increase (or decrease) INITRDSIZE in Config.sh from ${INITRDSIZE} to ${BLK_DEV_RAM_SIZE}"
fi

# test 21 - SELinux running in enforcing mode?
echo -en "${c_bold}Test 21${c_norm}: SELinux running in non-enforcing mode?"
if [ -f /etc/selinux/config ]; then
   grep "^SELINUX=enforcing" /etc/selinux/config >/dev/null 2>&1
   if [ $? -eq 0 ] && [ "${Disable_SELinux_during_backup}" = "false" ]; then
      # enforcing mode
      echo -e "\t\t\t${c_bold}${fail}Failed${c_norm}"
      echo -e "\t${fail}Warning${c_norm}: Backup cannot preserve extended attributes."
      echo -e "\tYou might temporary disable SELinux druing backup by changing in"
      echo -e "\tConfig.sh the variable into Disable_SELinux_during_backup=true"
   else
      # permissive or disabled mode - OK
      echo -e "\t\t\t${passed}${c_bold}Passed${c_norm}"
   fi
else
   echo -e "\t\t\t${passed}${c_bold}N/A${c_norm}"
fi

##########################################################################
# Now make a decision whether make test was good enough to continue
if [ ${TestErrCount} -eq 0 ]; then
        touch /tmp/.mkcdrec.tests.passed
else
        echo "
*****************************************************************
*       Oops! I encountered ${TestErrCount} problem(s)!                 *
*       Please correct it, or install the missing components.   *
*****************************************************************"
        rm -f /tmp/.mkcdrec.tests.passed
        touch /tmp/.mkcdrec.tests.not.passed
fi

# print ver_linux is useful for debugging reasons, therefore, run
# scripts/test.sh -v
