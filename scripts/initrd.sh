#!/bin/bash
# Copyright (c) 2000-2010 Gratien D'haese
# Please read LICENSE in the source directory
# $Id: initrd.sh,v 1.120 2010/02/07 10:22:19 gdha Exp $
. ./Config.sh 2>/dev/null
. ${SCRIPTS}/ansictrl.sh 2>/dev/null

set -o history
trap do_cleanup SIGTERM SIGINT
#trap check_rc DEBUG


echo "------------< Entering `basename $0` >-----------" | tee -a ${LOG}

# check the return code of every command, ignoring if statements
unused_check_rc()
{
    LASTRC=$?
    if [ $LASTRC != 0 ]; then
       a=`history 2 | head -1 | awk '{print $2}'`
       COMMAND=`basename $a`
       if ! echo $COMMAND | grep "if" > /dev/null ; then
           do_cleanup
       fi
    fi
    LASTRC=
    COMMAND=
}

# cleanup files left in an unfinished state
do_cleanup()
{
    echo "Cleaning up files created by `basename $0` due to failure." >&2
    sync 
    umount ${RAM0} 2> /dev/null
    rm -f initrd.img.gz initrd.img
    exit 1
}

# reads all the binaries for their dependencies
build_lib_list() {
#^^^^^^^^^^^^^^^
    cd ${stagedir}
    pushd ${stagedir} > /dev/null
    LIBDIR=`ldd \`find . -perm +111 -a ! -type d -a ! -type l 2> /dev/null | grep -v /dev\` | grep -v linux-gate | \
            grep "=>" | sort | awk '{print $3}' | grep -v '^dynamic$' | uniq`
    popd > /dev/null
}

get_module () {
#&&&Hack: TR/12-Sep-2008:
# modprobe --set-version `uname -r` --show-depends st glitch
# Workaround: prefix module with "@", then no magic wuill be done...
nolookup=0
if [ "${1:0:1}" == "@" ]; then
       mod=`find /lib/modules/${Kernel_Version} -type f -name ${1:1:999}.*o* | head -1 2>&1`
       nolookup=1
else
       mod=`find /lib/modules/${Kernel_Version} -type f -name ${1}.*o* | head -1 2>&1`
fi


if [ ! -z ${mod} ]
then
        # if major version is lower then 3 then --show-depends option is
        # not yet supported (gdha, 28/Mar/2005)
        if [ $nolookup -eq 1 -o ${modprobe_version} -lt 3 ]; then
                modlist=${mod}
        else
                modlist=`modprobe --set-version ${Kernel_Version} --show-depends ${1} | awk '{print $2}'`
        fi
          for mod in ${modlist}
          do
            BName=`basename ${mod}`
            # TargetBName=BName for RH, FC, SuSe
            TargetBName=`echo ${BName} | cut -d"." -f1-2`
            if [ "`grep -c ${TargetBName} ${stagedir}/etc/modules.initrd`" -eq "0" ]
            then
              cp ${mod} /tmp
              gunzip -f /tmp/${BName} 2>/dev/null
              cp /tmp/${BName} ${stagedir}/lib/modules 2>/dev/null || \
              cp /tmp/${TargetBName} ${stagedir}/lib/modules || \
              Fail "Out of space on initial ram-disk!"
              echo -n "${TargetBName} " >> ${stagedir}/etc/modules.initrd
              rm -f /tmp/${BName} || rm -f /tmp/${TargetBName}
              echo_log "Copied ${mod} module to ${stagedir}/lib/modules"
            fi
          done  
else
        echo "get_module: no ${1} found to load." | tee -a ${LOG}
fi
}

Make_libs () {
#^^^^^^^^^^^

echo_log "Copying the libraries we need..."
for i in `echo $LIBDIR`
do
    echo "$i" | grep -q "^(0x0" && continue
    echo_log strip_copy_lib $i $stagedir/$i
    strip_copy_lib $i $stagedir/$i ||  Fail "initrd: out of space!"
done

# Check if ld-linux.so.2 is there (FC3 does not copy it because it is a link)
if [ -f /lib/ld-linux.so.2 ] && [ ! -f $stagedir/lib/ld-linux.so.2 ]; then
   strip_copy_lib /lib/ld-linux.so.2 $stagedir/lib/ld-linux.so.2 || Fail "initrd: out of space!"
fi

# Check if ld-linux-ia64.so.2 exists (FC3 doesn't copy it because it is a link)
if [ -f /lib/ld-linux-ia64.so.2 ] && [ ! -f $stagedir/lib/ld-linux-ia64.so.2 ]; then
        strip_copy_lib /lib/ld-linux-ia64.so.2 $stagedir/lib/ld-linux-ia64.so.2 || Fail "initrd: out of space!"
fi

case ${BOOTARCH} in
       x86_64)
        strip_copy_lib /lib64/ld-linux-x86-64.so.2 $stagedir/lib64/ld-linux-x86-64.so.2 || Fail "initrd: out of space!"   
        ;;
 new-powermac)
        # added for new-powermac SF# 1035231
        if [ -f /lib/ld.so.1 ]; then
           strip_copy_lib /lib/ld.so.1 $stagedir/lib/ld.so.1 || Fail "initrd: out of space!"
        fi
        ;;
            *) # no special actions for other BOOTARCH
        ;;
esac
# ldconfig must be done prior to SYMLINKS.  SYMLINKS creates links to libs that
# don't exist yet, and ldconfig doesn't like that, so it removes them.
echo_log  "++++++++++++++ ldconfig +++++++++++++"
echo "/lib" > ${stagedir}/etc/ld.so.conf
echo "/lib/i686" >> ${stagedir}/etc/ld.so.conf
echo_log "`/sbin/ldconfig -v -r ${stagedir}/`"
if [ $? -eq 1 ]; then
        error 1 "Oops. I guess the initial ramdisk is full: `df -kP $stagedir | tail -1`"
fi
}

#################### MAIN ##################

#Allow user to identify kernel version when manually specifying LINUX_KERNEL
if [ -z "$LINUX_VERSION" ]; then
        Kernel_Version=`uname -r`
else
        Kernel_Version=${LINUX_VERSION:-`uname -r`}
fi

# Kernel 2.2.x will return 2, kernel 2.4.x returns 4
kernel_minor_nr=`echo ${Kernel_Version} | cut -d. -f2` 

# pick up the initial ramdisk size from the Config.sh file (if empty then...)
if [ -z "${INITRDSIZE}" ]; then
 INITRDSIZE=2500 # 1k blocks
fi

# Is devfsd running? 
ls -b /dev/.devfsd >/dev/null 2>&1   # empty when no DEVFS active
DEVFSD=$?
if [ x${DEVFS} = x0 ] || [ x${DEVFSD} = x1 ]; then
   # devfsd not running
   RAM0=/dev/ram0
else
   RAM0=/dev/rd/0
fi

modprobe_version=`modprobe -V | awk '{print $3}' | cut -d. -f1`
if [ ${modprobe_version} -lt 3 ]; then
        echo "modprobe version is ${modprobe_version}: get_module cannot use the --show-depends option" | tee -a ${LOG}
else
        echo "modprobe version is ${modprobe_version}: get_module can use the --show-depends option" | tee -a ${LOG}
fi

# experimental RAM0 on disk instead of /dev/ram0
RAM0=/tmp/mkcdrec.ram0

echo_log "${BOOTARCH}: making an empty initrd via ${RAM0}"
dd if=/dev/zero of=${RAM0} bs=1k count=${INITRDSIZE}

# umount $stagedir (rest-over of rd-base.sh)
umount -f -d ${stagedir}

echo "The initial ramdisk filesystem setting found in Config.sh = ${INITRD_FS}" | tee -a ${LOG}

if [ X${INITRD_FS} = Xext2 ]; then
  echo_log "Creating an empty ext2 filesystem for the init ramdisk"
  #/sbin/mkfs.ext2 -Fq ${RAM0} -m 0 -i $((16*1024)) ${INITRDSIZE} > /dev/null 2>&1
  /sbin/mkfs.ext2 -Fq ${RAM0} -m 0  ${INITRDSIZE} > /dev/null 2>&1
  /bin/mount -o loop -t ext2 ${RAM0} ${stagedir}
  if [ $? -ne 0 ]; then
     echo "Problem with creating virtual initial ramdisk" | tee -a ${LOG}
  fi
  rmdir ${stagedir}/lost+found
elif [ X${INITRD_FS} = Xreiserfs ]; then
  echo_log "Creating an empty reiserfs for the init ramdisk"
  /sbin/mkfs.reiserfs -f ${RAM0} > /dev/null 2>&1
  /bin/mount -o loop -t reiserfs ${RAM0} ${stagedir}
elif [ X${INITRD_FS} = Xxfs ]; then
  # Warning: this is currently undocumented because the initrd is too
  # small for XFS.
  echo_log "Creating an empty xfs for the init ramdisk"
  /sbin/mkfs.xfs ${RAM0} > /dev/null 2>&1
  /bin/mount -o loop -t xfs ${RAM0} ${stagedir}
elif [ X${INITRD_FS} = Xmsdos ]; then
  echo_log "Creating an empty msdos filesystem for the init ramdisk"
  /sbin/mkfs.msdos ${RAM0} > /dev/null 2>&1
  /bin/mount -o loop -t msdos ${RAM0} ${stagedir}
elif [ X${INITRD_FS} = Xromfs ]; then
  echo_log "Using ROMFS for the init ramdisk"
  rm -rf ${stagedir}
  mkdir ${stagedir}
elif  [ X${INITRD_FS} = Xramfs ]; then
  echo_log "Using RAMFS for the init ramdisk"
  rm -rf ${stagedir}
  mkdir -m 775 ${stagedir}
elif  [ X${INITRD_FS} = Xcramfs ]; then
  echo_log "Using CRAMFS for the init ramdisk"
  rm -rf ${stagedir}
  mkdir ${stagedir}
elif  [ X${INITRD_FS} = Xminix ]; then
  echo_log "Creating an empty minix filesystem for the init ramdisk"
  /sbin/mkfs.minix ${RAM0} > /dev/null 2>&1
  /bin/mount -o loop -t minix ${RAM0} ${stagedir}
else
   error 1 "Don't know how to build a filesystem of type ${INITRD_FS}."
fi

echo_log Populating the \'initrd\' filesystem

# directories
(cd ${stagedir}/ && mkdir -p new_root proc dev lib/i686 bin etc mnt usr sys var/run)
(cd ${stagedir}/ && ln -s bin sbin)             # link sbin to bin
(cd ${stagedir}/usr && ln -s ../lib lib)        # link usr/lib to lib
# On Ubuntu (and maybe others too) the libc is under /lib/tls/i686/cmov
# check if /lib/tls dir exists? Yes, soflink it to lib
if [ -d /lib/tls/i686/cmov ]; then
   mkdir -p ${stagedir}/lib/tls/i686/cmov
elif [ -d /lib/i686/cmov ]; then
   mkdir -p ${stagedir}/lib/i686/cmov
elif [ -d /lib/tls ]; then
   (cd ${stagedir}/lib && ln -s . tls)
fi
if [ x${BOOTARCH} = xia64 ]; then
   (cd ${stagedir}/    && mkdir -p boot/efi)
fi
if [ x${BOOTARCH} = xx86_64 ]; then
   (cd ${stagedir}/    && mkdir -p lib64)
   (cd ${stagedir}/usr && ln -s ../lib64 lib64)
   (cd ${stagedir}/lib64 && ln -s . tls)
fi
echo_log "Populating the \'dev\' filesystem if DEVFS = $DEFVS (0)" 
if [ $DEVFS -eq 0 ]; then
        # devices
        (cd ${stagedir}/ && cp -ra \
            /dev/initrd \
            /dev/ram[012] \
            /dev/console \
            /dev/mem \
            /dev/kmem \
            /dev/hd[abcdefgh] \
            /dev/hd[abcdefgh]1 \
            /dev/scd[0-8] \
            /dev/fd0 \
            /dev/null \
            /dev/sd[ab] \
            /dev/sda[1-4] \
            /dev/sdb[1-4] \
            /dev/ttyS0 \
            /dev/tty[1-6] dev)
        if [ -f ${TMP_DIR}/OBDR ]; then
           (cd ${stagedir}/ && cp -ra ${TAPE_DEV} dev)
        fi
        # Work-around for /dev/ram problem (should be 0 but is 1 on RedHat)
        # on SuSe /dev/ram is a link to ram0
        (cd ${stagedir}/dev && \
            ln -s ram0 ram ; \
            ln -s ram0 ramdisk ; \
            )
        # Add some block devices for UML
        (cd ${stagedir}/dev && \
            mknod --mode=660 ubd0 b 98 0 ; \
            mknod --mode=660 ubd1 b 98 16 ; \
            mknod --mode=660 ubd2 b 98 32 ; \
            mknod --mode=660 ubd3 b 98 48)
        # check if udevd is running
        ps ax | grep -i udev | grep -v grep >/dev/null 2>&1
        if [ $? -eq 0 ]; then
           # uDev is running - create some spare devices for the CD
           echo_log "Warning: uDev is active. Create some extra devices."
           [ "${MAKEDEV}" = "/sbin/makedev" ] && MAKEDEV="/sbin/makedev ."
        (cd ${stagedir}/dev && \
           mknod -m 0660 initrd b 1 250
           chown root.root initrd
           ${MAKEDEV} scd >/dev/null 2>&1 ; \
           ${MAKEDEV} sda sdb sdc sdd >/dev/null 2>&1 ; \
           ${MAKEDEV} hda hdb hdc hdd hde hdf hdg >/dev/null 2>&1 ; \
           ${MAKEDEV} ram >/dev/null 2>&1 ; \
           ${MAKEDEV} mem >/dev/null 2>&1 ; \
           ${MAKEDEV} kmem >/dev/null 2>&1 ; \
           ${MAKEDEV} console >/dev/null 2>&1 ; \
           ${MAKEDEV} ttyS0 >/dev/null 2>&1 ; \
           ${MAKEDEV} null >/dev/null 2>&1 ; \
           ${MAKEDEV} zero >/dev/null 2>&1 ; \
           )
        fi
        (cd ${stagedir}/dev && \
            ln -s scd0 sr0 ; \
            ln -s scd1 sr1 ; \
            )
echo_log "End of populating of \'dev\' filesystem ($DEVFS)"
fi # end of [ x$DEVFS = x0 ]


# APPLICATIONS ########################################################
for binary in killall syslogd klogd ls mount grep ash bzip2 umount cat pivot_root chroot [ test echo pwd mkdir sleep udevstart cpio mknod;
# added chroot again as according initrd docs it should exist in old and new
# root fs (gdha, 22/11/2001)
# remove modprobe as static exe on mdk9.2 is too big to fit (gdha, 01/12/03)
do 
    targetbin=`which ${binary} 2>/dev/null`
    if [ $? -eq 0 ]; then       # targetbin found
        echo_log strip_copy ${targetbin} ${stagedir}/bin/${binary}
        strip_copy ${targetbin} ${stagedir}/bin/${binary}
    else
        echo "Warning: ${binary} was NOT found!" | tee -a ${LOG}
    fi
done
if [ -f ${TMP_DIR}/OBDR ]; then
        if [ ! -f  ${MT} ]; then
           Fail "OBDR needs ${MT}. Couldn't find it. Check MT in Config.sh"
        fi
        strip_copy ${MT} ${stagedir}/bin/mt
        echo_log strip_copy ${MT} ${stagedir}/bin/mt
        strip_copy /bin/dd ${stagedir}/bin/dd
        echo_log strip_copy /bin/dd ${stagedir}/bin/dd
fi

# if initial ramdisk is of type ramfs then we need busybox
if [ X${INITRD_FS} = Xramfs ]; then
	strip_copy ${MKCDREC_DIR}/busybox/busybox ${stagedir}/bin/busybox
	echo_log strip_copy ${MKCDREC_DIR}/busybox/busybox ${stagedir}/bin/busybox
fi
# special treatment for insmod depending on kernel_minor_nr
# Kernels < 2.5 need to use insmod.old instead of insmod (if existing)
case ${kernel_minor_nr} in
    2|4) 
        if [ -f /sbin/insmod.old ]; then
          echo_log strip_copy /sbin/insmod.old ${stagedir}/bin/insmod
          strip_copy /sbin/insmod.old ${stagedir}/bin/insmod
        elif [ -f /sbin/insmod.modutils ]; then # for Debian 3.1
          echo_log strip_copy /sbin/insmod.modutils ${stagedir}/bin/insmod
          strip_copy /sbin/insmod.modutils ${stagedir}/bin/insmod
        else
          echo_log strip_copy /sbin/insmod ${stagedir}/bin/insmod
          strip_copy /sbin/insmod ${stagedir}/bin/insmod
        fi
        ;;
      *)
         echo_log strip_copy /sbin/insmod ${stagedir}/bin/insmod
         strip_copy /sbin/insmod ${stagedir}/bin/insmod
        ;;
esac

(cd ${stagedir}/bin && ln -s ash sh)

# gdha - 11/07/2001 - remove pivot_root with kernel = 2.2.x
if [ ${kernel_minor_nr} -eq 2 ]; then
   rm -f ${stagedir}/bin/pivot_root 2>/dev/null
fi

# LIBRARIES ###########################################################
## Library list for SuSe 6.2, RedHat 6.2/7.0, Debian 2.2/3.0
# libs in /lib
if [ ${BOOTARCH} == 'x86_64' ]; then
       LIBTARGET='lib64'
else
       LIBTARGET='lib'
fi	
for LIB in libnss_files.so.2 libnss_dns.so.2 libnss_files.so.1 libnss_dns.so.1 libresolv.so.2
 do
  if [ -f /${LIBTARGET}/${LIB} ]; then
     strip_copy_lib /${LIBTARGET}/${LIB} ${stagedir}/${LIBTARGET}/${LIB} || Fail "initrd.sh: ${LIB}: out of space!"
  fi
 done

# libs in /usr/lib (activate do loop again after complaints if missing
# libbz2.so in /initrd/usr/lib, normally build_lib_list should catch it
# but apperently it is not fullproof - gdha - 20/04/2001)
for LIB in `find /${LIBTARGET} -name "libbz2.so*"` `find /usr/${LIBTARGET} -name "libbz2.so*"`
 do
   if [ ! -L ${LIB} ] && [ ! -f ${stagedir}/${LIBTARGET}/${LIB} ]; then
      strip_copy_lib ${LIB} ${stagedir}/${LIBTARGET}/libbz2.so ||  Fail "initrd.sh: libbz2.so: out of space!"
   fi
 done

# Make the shared libs for our initrd-fs
build_lib_list
Make_libs

if [ -f ${stagedir}/lib/ld-linux.so.2 ]; then
   chmod 555 ${stagedir}/lib/ld-linux.so.2
fi
if [ -f ${stagedir}/lib/ld-linux-ia64.so.2 ]; then
   chmod 555 ${stagedir}/lib/ld-linux-ia64.so.2
fi
if [ -f ${stagedir}/lib/libnss_files.so.2 ]; then # Debian 3.0
   (cd ${stagedir}/lib; ln -s libnss_files.so.1 libnss_files.so.2 >/dev/null 2>/dev/null)
   (cd ${stagedir}/lib; ln -s libnss_dns.so.1 libnss_dns.so.2 >/dev/null 2>/dev/null)
fi
if [ -f ${stagedir}/lib/libbz2.so ]; then
   (cd ${stagedir}/lib; ln -s libbz2.so libbz2.so.0)    # RH 6.2
   (cd ${stagedir}/lib; ln -s libbz2.so libbz2.so.1)    # RH 7.0
fi

if [ -d /lib64 ]; then
  if [ -f ${stagedir}/lib64/ld-linux.so.2 ]; then
     chmod 555 ${stagedir}/lib64/ld-linux.so.2
  fi
  if [ -f ${stagedir}/lib64/ld-linux-ia64.so.2 ]; then
     chmod 555 ${stagedir}/lib64/ld-linux-ia64.so.2
  fi
  if [ -f ${stagedir}/lib64/libnss_files.so.2 ]; then # Debian 3.0
     (cd ${stagedir}/lib64; ln -s libnss_files.so.1 libnss_files.so.2 >/dev/null 2>/dev/null)
     (cd ${stagedir}/lib64; ln -s libnss_dns.so.1 libnss_dns.so.2 >/dev/null 2>/dev/null)
  fi
  if [ -f ${stagedir}/lib64/libbz2.so ]; then
     (cd ${stagedir}/lib64; ln -s libbz2.so libbz2.so.0)    # RH 6.2
     (cd ${stagedir}/lib64; ln -s libbz2.so libbz2.so.1)    # RH 7.0
  fi
fi

echo_log "Copied the following libraries to ${stagedir}/lib:"
echo_log "`ls -l ${stagedir}/lib`"

# Copy modules to mount CD-ROM at initrd time #########################
echo_log "Check if we need to load modules for IDE/SCSI cd-rom at boot time"
echo -n "MODULES=\"" > ${stagedir}/etc/modules.initrd   # start modules script
mkdir -p  ${stagedir}/lib/modules

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
# we do a forced gunzip (Mandrake) to bzip2 the modules on CD afterwards

echo_log "Check if we have loadable ide/scsi/sata modules, and ide/scsi cd-rom..."
# ls /proc/scsi/* contains the name of the scsi controller(s)
for cntrl in `ls /proc/scsi | egrep -v '^scsi$|^device_info$'`
do
  # on IA64 a CD-ROM drive will not be attached to FCh, exclude qlogic
  cat /proc/modules | egrep -v 'ql' | grep ${cntrl} >/dev/null 2>&1
  if [ $? -eq 0 ]; then
     get_module scsi_transport_spi
     get_module scsi_mod
     get_module diskdumplib
     get_module mptbase
     get_module ${cntrl}
     get_module usbcore # move loading usbcore before sd_mod!! 
     get_module sd_mod  # for SCSI disk
     if [ -f ${TMP_DIR}/OBDR ]; then
        get_module st   # SCSI tape     
        echo "${TAPE_DEV}" > ${stagedir}/OBDR
     fi
  fi 
done

# for ata_piix SATA driver
if [ -e /proc/ide/piix ]; then
  # SATA masquerades as SCSI
  get_module scsi_mod
  get_module sd_mod
  get_module ata_piix
fi

# for special ICH6/7 SATA drivers
for cntrl in `grep ^ata_piix /proc/modules | cut -f1 -d' '`
do
  get_module scsi_mod
  get_module sd_mod
  get_module $cntrl
done

# for other SATA drivers
for cntrl in `grep ^sata /proc/modules | cut -f1 -d' '`
do
  get_module scsi_mod
  get_module sd_mod
  get_module $cntrl
done

# for megaraid
[ -d /proc/megaraid ] && get_module megaraid

# For syslog.
get_module unix

# USB modules for keyboard
get_module usbcore
get_module hid
get_module usbhid
get_module uhci-hcd
get_module ehci-hcd

# Potentially used for root filesystem.
if [ x$ROOT_FS = xext2 ]; then
        get_module mbcache
        get_module ext2
elif [ x$ROOT_FS = xext3 ]; then
        get_module jbd
        get_module ext3
elif [ x$ROOT_FS = xreiserfs ]; then
        get_module reiserfs
elif [ x$ROOT_FS = xxfs ]; then
        get_module xfs
        get_module xfs_support
elif [ x$ROOT_FS = xminix ]; then
        get_module minix
elif [ x$ROOT_FS = xmsdos ]; then
        get_module msdos
        get_module fat
fi

# For CD-ROM.
get_module ide-mod
get_module ide-probe-mod
get_module cdrom
get_module ide-cd
get_module sr_mod
case ${kernel_minor_nr} in
 2|4) get_module ide-scsi ;;
   *) echo "Do not try to load ide-scsi module if kernel minor nr is ${kernel_minor_nr}" | tee -a ${LOG} ;;
esac
get_module inflate_fs
get_module zlib_inflate # needed by mdk 9.1
get_module isofs
get_module tmscsim      # requested by js@simulakron.de
get_module usb-ohci     # for USB cd-rom
get_module ehci_hcd
get_module ehci-hcd	# for CentOS
get_module uhci_hcd	# for CentOS
get_module ohci_hcd
get_module uhci-hcd     # for USB cd-rom (Debian)
get_module ohci-hcd     # for USB cd-rom (Debian)
get_module usb-uhci     # for USB cd-rom (HP BL20p G3)
get_module usb-storage  # for USB cd-rom
get_module nls_cp437    # for proper language

# Load other modules, given by the Config.sh
for i in ${INITRD_MODULES}
do
  get_module $i
done

# for IA64 write content of boot.img to /boot/efi/efi/recovery if present
if [ x${BOOTARCH} = xia64 ]; then
   if [ -d /boot/efi/efi ]; then
        mkdir -p /boot/efi/efi/recovery 2>/dev/null
        get_module sd_mod
        get_module fat
        get_module scsi_mod
        get_module diskdumplib
        get_module mptscsih
        get_module vfat
        df -P /boot/efi | grep efi | awk '{print $1}' >${stagedir}/EFI
   fi
fi

# special rule for OBDR - we need the st module if needed
if [ -f ${TMP_DIR}/OBDR ]; then
	get_module st   # SCSI tape     
	echo "${TAPE_DEV}" > ${stagedir}/OBDR
fi

# to finish up, compress the modules to save space (except for romfs/cramfs)
if ! [ x$INITRD_FS = xromfs  -o x$INITRD_FS = xcramfs ]; then
  for i in `ls ${stagedir}/lib/modules/* 2>/dev/null`
  do
    bzip2 -9v ${i}
    echo bzip2 ${i} >> ${LOG}
  done
else
  get_module ${INITRD_FS}       # make sure we have the module
fi

echo "\"" >> ${stagedir}/etc/modules.initrd     # end modules script

chmod +x ${stagedir}/etc/modules.initrd
echo_log "The following list of modules were copied to the initial ram disk:"
echo_log "`cat ${stagedir}/etc/modules.initrd`"

# NON-EXE FILES #######################################################
cp ${MKCDREC_DIR}/etc/services ${stagedir}/etc
install -m 700 ${MKCDREC_DIR}/linuxrc ${stagedir}/init
install -m 700 ${MKCDREC_DIR}/linuxrc_pre ${stagedir}/linuxrc_pre
install -m 700 ${MKCDREC_DIR}/linuxrc_find_and_prep_root ${stagedir}/linuxrc_find_and_prep_root
install -m 700 ${MKCDREC_DIR}/linuxrc_post ${stagedir}/linuxrc_post
> ${stagedir}/etc/fstab
echo "*.*               /dev/tty6" > ${stagedir}/etc/syslog.conf
cp -fr /etc/modules* ${stagedir}/etc/   # mdk needs /etc/modules (gdha,28/11/01)
cp -fr /etc/modprobe* ${stagedir}/etc/   # for kernel 2.6.x (gdha, 20/01/2004)
if [ -f /etc/devfsd.conf ]; then
   cp -f /etc/devfsd.conf ${stagedir}/etc/ # for gentoo? (gdha, 10/03/04)
fi
cp -fa /etc/udev ${stagedir}/etc/	# for fc5/udev? (JR, 8-07-06)

# make note of which type of ROOT_FS has been used for rd-base.img as
# we need to know this afterwards (init) to mount the rd-base.img
# as ext2, minix file system or as ramfs/tmpfs type (the first one is
# dd-ed and the latter cpio-ed; both are bzip2 afterwards)
echo "${ROOT_FS}" > ${stagedir}/.rootfs

# END NON-EXE FILES ###################################################
echo -e "\nInitrd root contains the following directory tree:"
(cd ${stagedir}; ls -xlF | tee -a ${LOG} )
echo "Size of initial ramdisk is" | tee -a ${LOG}
df -kP ${stagedir} | tail -n 1 | tee -a ${LOG}
cd ${MKCDREC_DIR}

if [ X${INITRD_FS} = Xromfs ]; then
  genromfs -d ${stagedir} -f ${RAM0} 
  if [ $? -ne 0 ]; then
        error 1 "genromfs not found! Get it from ftp.banki.hu:/pub/Linux/local/genromfs-*"
  fi
else
  umount ${RAM0} 
fi

if [ X${INITRD_FS} = Xcramfs ]; then
  echo "mkcramfs the completed init ramdisk" | tee -a ${LOG}
  mkcramfs  ${stagedir}  initrd.img.gz  # it is compressed already
  echo "------------< Leaving `basename $0` >-----------" | tee -a ${LOG}
  exit 0
elif [ X${INITRD_FS} = Xramfs ]; then
  # the file "/ramfs" is a trigger for init to use RAMFS style instead of
  # pivot_root and we store the size into this file
  echo "$((((${RAMDISK_SIZE}*1024)+512)*1024))" > ${stagedir}/ramfs	# bytes
  echo "Creating the initial ramdisk via cpio/gzip - ramfs" | tee -a ${LOG}
  (cd ${stagedir} && find .   | \
	cpio -H newc --create --quiet | \
	gzip -9 > "${MKCDREC_DIR}/initrd.img.gz"  2>>${LOG} )
else
  echo "Compressing the completed init ramdisk using dd/gzip" | tee -a ${LOG}
  dd if=${RAM0} bs=1k count=${INITRDSIZE} | gzip -v9 > initrd.img.gz 2>>${LOG}
  # if RAM0 is a disk image - rm it again, otherwise do not bother
fi

# Cleaning up $RAM0 file
case ${RAM0} in
	/dev/*)  ;;
	*) 	echo "Cleaning up ${RAM0} " | tee -a ${LOG}
		rm -f ${RAM0} 2>>${LOG}  ;;
esac

echo "Check integrity of initrd.img.gz" | tee -a ${LOG}
gzip -t initrd.img.gz
if [ $? -eq 1 ]; then
   error 1 "CRC error on initrd.img.gz! Please \"rm initrd.img.gz\"
and try again with \"make\""
fi
echo "------------< Leaving `basename $0` >-----------" | tee -a ${LOG}
