# mkcdrec (C) Copyright 2000-2010 by Gratien D'haese - IT3 Consultants
# Please read LICENSE in the source directory
# Config.sh contains the variable parameters set by the end-user
# Script will be dotted by :
#       initrd.sh
#       rd-base.sh
#       bootflop.sh, bootx86_64.sh
#       tar-it.sh
#       mkmakeISO9660.sh
################################################################
## $Id: Config.sh,v 1.213 2011/01/14 09:09:52 gdha Exp $
################################################################

# Set to y if you want to see all the output
VERBOSE=n

# Set to y if you want to use colors in the prompts
USECOLOR=y

# Architecture this CD-ROM should boot on. Supported are the following:
# x86, powermac, new-powermac, ia64, x86_64, sparc
BOOTARCH=x86

# Perform heavy verification tests on CDrec.iso boot image
HEAVY_VERIFY=y

# RAM disk size for our base ram (default 32 Mb). The minimum should be 8.
# This RAM disk size will be used AFTER the inital ram disk has been loaded
# Do not confuse it for initrd (4 Mb is normally sufficient there)
# Mandrake 8.0 requires 16, but mdk 8.1 prefers 24 Mb.
# Reiserfs requires 8212 blocks (a block is 4096 bytes) + room for data (ugh).
# For ia64 platforms and kernel 2.6.x use 64. 
RAMDISK_SIZE=128

# The ISOFS_DIR is where the target (isofs + tgz) will be copied to
# Be aware that for a CDROM of 650 MB one needs about 1 GB temporary space
# Also, BE CAREFUL -- this directory will be deleted by make clean!
# Don't use /tmp.
ISOFS_DIR=/var/tmp/backup

# CDREC_ISO_DIR is the path where the CDrec.iso will be created, is NOT the
# same of ISOFS_DIR
# ** Attention: for multi volume CDs one needs approx. 2 Gb disk space **
# . means ${MKCDREC_DIR}, please use real pathname not a variable
CDREC_ISO_DIR=/var/tmp/isodir

# You may fill in an absolute path to your preferred linux kernel - may be left
# empty (default). The bootflop.sh script will try to find your current kernel 
# instead (best effort method)
LINUX_KERNEL=""

# If you are working on ia64, you may fill in an absolute path to elilo.conf
# and elilo.efi directory
# Elilo.conf and elilo.efi must be found in this directory
ELILO_DIR="/boot/efi/efi/redhat"

# If you specify a LINUX_KERNEL which is a different version from the one
# currently running, specify the version here. The modules for that version
# should exist in /lib/modules/${LINUX_VERSION}. 
# Add something alike the output of 'uname -r' but according LINUX_KERNEL
LINUX_VERSION=""

# Extra kernel parameters which syslinux should use, e.g. "vga=794"
# or " devfs=mount" (for Mandrake 8/9 with devfs support)
# see append= line in /etc/lilo.conf!
# KERNEL_APPEND="splash=0" in case you have a flickering boot sequence.
KERNEL_APPEND="ramdisk_blocksize=1024 selinux=0"

# Use the compress program of your choice (gzip, bzip2)
CMP_PROG=gzip
# which options do we feed the CMP_PROG with (-9: best compression, c: stdout)
CMP_PROG_OPT="-9cv"

################
## Encryption ##
################
# Name an openssl cipher to use or "none" for unencrypted backups.
CIPHER=none

#########################
# Pre/Post-Exec scripts #
#########################
# Handy if you need to shutdown a database or do something else before starting
# the backup (PreExec). PostExec will be executed when backups are finished.
# E.g. PreExec="/etc/init.d/oracle stop" (use ; to seperate multiple commands
# or use a home brew script)
PreExec=""
PostExec=""

####################
# General settings #
####################

# default setting for prompt for a rescue boot-floppy (NO=0; YES=1)
# handy in case you cannot boot from an el-torito cdrom ;-)
# Note: only works if BOOT_FLOPPY_DENSITY=HD
PROMPT_BOOT_FLOPPY=0

# The initrd filesystem type to use (ext2, minix, romfs, cramfs, ramfs)
# Must be compiled into the kernel (not a module).
# SuSe 10.2 does not have ext2 anymore inside the kernel, use minix instead!
# Try first ramfs; if that does not work try ext2 or minix
INITRD_FS=ramfs

# The root filesystem type to use (ext2, ext3, ext4, minix, ramfs)
ROOT_FS=ramfs


# Backup mounted loopback filesystems (true=1)
BACKUP_LOOP=0

# default setting for the size of emulating bootfloppy (default=2.88Mb)
# HD = 1.44 Mb (Linux 2.2.x kernel fits on 1.44 Mb, 2.4 must be build with
# major modules support for squeezing on 1 HD floppy)
# H1722 = 1.722 Mb bootfloppy (makes a 2.88 Mb image for the El-torito CD)
# ED = 2.88 Mb (Linux 2.4 kernel tend to be huge ;-/)
# Consequence: if ED is selected no physical floppy can be made! Therefore,
# even if you make PROMPT_BOOT_FLOPPY=1
# bootflop.sh script will decide automatically for HD or ED on basis on 
# kernel size
BOOT_FLOPPY_DENSITY=ED

# Should mkfs check for bad blocks before making the filesystems?
# The "-c" considerable slows down the restore, if you can live without it
# then make the following variable empty (thx to Yves Blusseau)
# Keep the "-c" option (after the play-around time) for production systems.
#CHECK_BAD_BLOCKS="-c"
CHECK_BAD_BLOCKS=""

# Do you need perl and its /usr/lib/perl5 stuff to be added on the ramdisk?
# Say "true" for yes or false/no/n or whatever if you do not need it. 
ADD_PERL=false

###############
# Tape Device #
###############
# Define a tape device (if any of course - doens't hurt if not attached)
# be sure to use the "norewinding" device, otherwise you will loose!
TAPE_DEV=/dev/nst0
# preferred mt command is from st-mt package, not GNU mt
MT=/bin/mt
# TapeDensity: use command "mt densities" to select your proper setting
# -----------  (only needed in combination with tape backup)
# When remote backup is used: TapeDensity is not set (yet) - FIXME
TapeDensity="0x25"

# REMOTE_COMMAND if desired (rsh, ssh) - used in combination with remote tapes
# However, it could be a remote file too ;-()
REMOTE_COMMAND=ssh

##########################################
# Exclude directories/files from archive #
##########################################
# If you wish to exclude explicit some paths from being backup'ed add them here
# Please add only one item per line!! This is true for all following items.
# The syntax is just as when using wildcards on any *nix system.
# eg: "/test" will exclude all items in /test (if /test is a directory) and 
#           also /test will NOT exist upon restore
#           if /test is a file, it will only exclude that file
#           ==> mostly used for files or mountpoints you don't want backup'ed
# eg: "/test/*" will exclude all items in the directory /test
#           but /test will be created upon restore
#           ==> this is what most people want for directories
# eg: "/var/log/maillog*" will exlude all /var/log/maillog* files
#           ==> this demonstrates wildcards so you can exclude frequently
#           updated files (most commonly logfiles)

EXCLUDE_LIST="/var/spool/squid/*
/var/log/maillog*
/var/log/messages*
/var/log/lastlog
/var/log/X*
/var/tmp/isodir/*
/tmp/CDrec*
/mnt/*
/proc/*
/var/tmp/[BACKUP]
"

##########################
# CD/DVD-Writer Settings #
##########################
# The location of mkisofs - may be set by user to what he likes
# Keep in mind to use an absolute path if you change it!!
# MKISOFS=/opt/schily/bin/mkisofs
MKISOFS=mkisofs
# to check ISO9660 image's integrity use 'isovfy'
ISOVFY="`which isovfy`"

# We need syslinux (and isolinux.bin) from the distribution or source
# Because isolinux.bin is not an executable "which" will not work on it
if [ -f /usr/lib64/syslinux/isolinux.bin ]; then
        # x86_64,...
        ISOLINUX="/usr/lib64/syslinux/isolinux.bin"
        MEMDISK="/usr/lib64/syslinux/memdisk"
	SYSLINUXPATH="/usr/lib64/syslinux"
elif [ -f /usr/lib/syslinux/isolinux.bin ]; then
        # RedHat,Fedora<11, ...
        ISOLINUX="/usr/lib/syslinux/isolinux.bin"
        MEMDISK="/usr/lib/syslinux/memdisk"
	SYSLINUXPATH="/usr/lib/syslinux"
elif [ -f /usr/share/syslinux/isolinux.bin ]; then
        # Slackware, Fedora=>11, ...
        ISOLINUX="/usr/share/syslinux/isolinux.bin"
        MEMDISK="/usr/share/syslinux/memdisk"
	SYSLINUXPATH="/usr/share/syslinux"
else
	# not found
	ISOLINUX=""
	MEMDISK=""
	SYSLINUXPATH=""
fi
# since mkCDrec v0.8.7 ISOLINUX will be used by default; in cases we
# want SYSLINUX above ISOLINUX we must set the following to "true":
FORCE_SYSLINUX=false
 
# BURNCDR = y means we want to burn a CDR with a CDrec.iso image immediately
# Put 'n' is you do not have a CD/dvd-writer attached locally (default=n)
BURNCDR=n

# Initial DVD Support (DVD_Drive=1 yes or 0 for no [Default=0])
# Set to 1 for growisofs usage, leave it 0 for cdrecord with dvd support
# but do not forget to change MAXCDSIZE too then
# It is important to know that growisofs writes directly to the DVD and
# does not produce an ISO image (no CDrec.iso file will be created)! 
# Another important issue to know is that with growisofs only one DVD
# can be written (no multiply DVDs).
DVD_Drive=0

# The following lines define the necessary input for 'cdrecord' (only used
# when BURNCDR = y, otherwise it will be ignored)
# Keep in mind to use an absolute path if you change it!!
## CDRECORD=/usr/bin/wodim
CDRECORD=/usr/bin/cdrecord
# in case you need special options for cdrecord (not dev, speed, blank, toc),
# but e.g. driveropts=burnfree
CDRECORDOPT=""
SCSIDEVICE="/dev/cdrom"
# use 'cdrecord -scanbus' to find the SCSIDEVICE settings (or 'make test')
WRITERSPEED="4"

# only useful when BURNCDR = y and using CDRW otherwise use "n"
# will blank in "fast" mode (so do not use new CDRWs)
BLANK_CDRW=y

# to automatically eject the CD after burning
CD_EJECT=y

# what is the maximum CDR capacity (by default 640 Mb). Increase it at your
# risk. Will only be used for making multi-volume CDs. Expressed in Kb.
# Noticed that by reserving some space the chance is higher of getting a 
# working ISO9660 image with mkisofs (14/06/2001 - gdha)
MAXCDSIZE=670000

##### DVD+R(W) Support (with growisofs) #####
if [ ${DVD_Drive} -eq 1 ]; then
# WARNING: no attempt will be made to erase DVD+RW!!! Make sure it is done.
# E.g.: growisofs -Z /dev/scd0=/dev/zero
# Using growisofs from http://fy.chalmers.se/~appro/linux/DVD+RW/
# dvdrtools: did not work for me yet? FIXME!
# DVD+R does not need any formatting, DVD+RW does (use e.g. dvd+rw-format)
# Assuming growisofs uses SCSI emulation device or is a SCSI device.
SCSIDEVICE=`${CDRECORD} -scanbus 2>/dev/null|grep -i dvd| grep -v dvdrtools|awk '/[0-9]+,[0-9]+,[0-9]+/{print $1}'|cut -d"," -f1|tail -n 1`
SCSIDEVICE="/dev/scd${SCSIDEVICE}"
# or when it is not a SCSI device at all, but ATAPI then hard-code it (FIXME)
# make test is a good indicator, and your common sense of course.
#SCSIDEVICE="/dev/hdc"

MAXCDSIZE=4350000
# At this point no attempt will be made for multiple DVD+R(W) sets
# usage:
#       growisofs -Z $SCSIDEVICE -R -J $ISOFS_DIR
fi # end of DVD_Drive=1


######################################################
# Serial Console used instead of virtual VGA console #
######################################################
# if SERIAL="" then no attempt will be made to start a getty process
# if SERIAL="ttyS0" then syslinux will write to ttyS0 and virtual console
# COM1 is ttyS0, COM2 is ttyS1
# Default is SERIAL="". Set SERIAL="ttyS0" for Integrity systems (ia64);
# use SERIAL="tts/0" on Mandrake (devfs notation)
# To login via serial console use root/mkCDrec (or mkcdrec/mkCDrec)
SERIAL=""
BAUDRATE=9600
# the serial port is always 8N1 (8-bits, no parity, 1 stop bit) which is a
# limitation of syslinux

################
# DHCP support #
################
# You can force DHCP support instead of taking this system network settings
# Be sure that the network card loadbale modules are in your list, or add
# these in NETWORK_MODULES
FORCE_DHCP_SUPPORT=Y

# List of partitions which are to have a fixed size when restored
# during cloning.  FAT partitions don't need to be listed here as
# they are handled automatically.
FIXED_SIZE=""

########################################################################
# List of modules we want to include in the initial ram disk
# Remember: the purpose is to load only the modules which are needed to
# find and mount the CD-ROM - all other modules will get loaded by the
# second ram disk
# Tip: dependency modules will get loaded automatically by get_module, so
# there is no need anymore to list them first!
# IA64 you could add "scsi_mod scsi_transport_fc lpfc sd_mod mptbase mptscsih"
# You can also add special drivers here which are IDE related such as:
# via82cxxx, sis5513, and probably others
# Which modules do we need in initrd
# TR/12-Sep-2008: prefix module name with "@" to disable dependency
# lookup magic with modprobe (initrd.sh in get_module()). Fails with
# ST module for example (OBDR - hint, hint) on RHEL4.
INITRD_MODULES="cpqarray ide-mod ide-probe-mod ide-cd aec62xx alim15x3 amd74xx atiixp cmd64x cs5520 cs5530 cs5535 cy82c693 hpt34x hpt366 it821x jmicron ns87415 opti621 pdc202xx_new piix rz1000 sc1200 serverworks siimage sis5513 slc90e66 triflex trm290 via82cxxx ide-generic ide-core cdrom isofs ide-scsi sr-mod sr_mod ide-detect ide-disk ata_piix ata_generic libata nls_iso8859-1 nls_cp437 nls_utf8 fat vfat ahci mptspi mptscsih mptbase scsi_transport_spi usb_storage usb-storage sg scsi_dh sd_mod @st @sg @scsi_mod "
########################################################################

########################################################################
# MODULES for the big ramdisk:
# List which SCSI related modules we absolute need (add more if necessary)
# Check /lib/modules/${Kernel_version}/[pcmcia,scsi]/*
# These modules are only loaded AFTER initrd has finished and gave control to
# the second RAM disk.
# So, it won't help you at boot time when initrd tries to mount the cd-rom
# for unpacking the 2th ram disk. Will add limited module support in initrd.
# PS: it will not break the mkCDrec making if modules are not found.
SCSI_MODULES="scsi_transport_spi
aic7xxx
aha152x_cs
BusLogic
apa1480_cb
aacraid
cciss
3w-9xxx
3w-xxxx
ide-scsi
scsi_mod
sd_mod
sr_mod
st
sg
megaraid
megaraid_mm
mptspi
mptscsih
mptbase
libata
ata_piix
eata
sata_mv
sata_nv
sata_promise
sata_qstor
sata_sil24
sata_sil
sata_sis
sata_svw
sata_sx4
sata_uli
sata_via
sata_vsc"

# Option to EXCLUDE SCSI modules for safety reasons, e.g. qla2300 module to
# avoid SAN based storage to be destroyed!
# Default: empty string
EXCLUDE_MODULES=""

# add below the network modules that need to be loaded on mkCDrec - they
# will be modprobe'd in rc.network on the mkCDrec boot CD-ROM (gdha, 14/10/2001)
NETWORK_MODULES="mii
3c59x
8139too
pcnet32
tulip
tg3
e1000
e100
r8169
bnx2
"

# add below the usb modules that need to be loaded on mkCDrec
# (for usb keyboard and mouse for example)
USB_MODULES="usbcore
hid 
usbserial
usbhid
ehci-hcd
uhci-hcd
usb-ohci
usb-uhci
ohci-hcd
usb-storage
keybdev
mousedev
usbhid
"
# List here any other module you may need in case of restore/recover
# NFS related modules (hopefully build into kernel, otherwise....)
OTHER_MODULES="lockd
sunrpc
psmouse
cdrom
unix
nfs
nls_cp437
nls_utf8
nls_iso8859-1
ide_core
ide_generic
ide_disk
ide_cd
ide-cd
ide_tape
zlib_inflate
isofs
reiserfs
smbfs
pagebuf
xfs_support
xfs
jfs
mbcache
ext2
ext3
ext4
ext4dev
jbd
smbfs
ntfs
fat
vfat
minix
bonding"
########################################################################
# END of MODULES for the big ram disk

# Which directories do we need in the rd-base.sh
MKDIR_LIST="var/run var/run/netreport var/tmp var/log usr/man usr/bin usr/sbin \
var/lock/subsys var/empty/sshd etc/ssh etc/dhcpc etc/udhcpc etc/init.d \
var/spool/uucp initrd lib/security etc/pam.d etc/sysconfig etc/network \
sys/class etc/makedev.d etc/lvm/backup  \
etc/profile.d var/lib/dhclient etc/security/console.perms.d \
root etc/security/console.apps \
etc/security/msec etc/default etc/skel etc/modprobe.d usr/lib mnt/floppy \
mnt/local mnt/cdrom var/lib/nfs usr/lib64 lib/i686 lib/tls lib/lsb \
usr/libexec/openssh var/lib/empty var/lib/dhcp lib32 usr/lib32 \
var/run/network usr/lib/sse2"

# List /etc/ files which can be copied blindly to rootfs/etc
ETC_FILES="
conf.modules
devfsd.conf
evms.conf
exports
fb.modes
group
host.conf
hostname
HOSTNAME
hosts
issue
ld.so.conf
localtime
login.defs
makedev.d/*
mdadm.conf
mke2fs.conf
modprobe.conf
modprobe.conf.dist
modprobe.conf.local
modprobe.devfs
modprobe.preload
modules
modules.autoload
modules.autoload.d/*
modules.conf
modules.conf.local
modules.devfs
modules.devfsd
networks
partimaged/*
passwd
profile.d/*
protocols
psdevtab
pwdb.conf
raidtab
resolv.conf
rpc
security/*
security/console.perms.d/*
services
shadow
silo.conf
smartd.conf
sysctl.conf
init.d/functions
default/rcS
"

# Trace the MAKEDEV executable
if [ -f /sbin/MAKEDEV ]; then
        MAKEDEV=/sbin/MAKEDEV
elif [ -f /dev/MAKEDEV ]; then
        MAKEDEV=/dev/MAKEDEV
elif [ -f /usr/sbin/MAKEDEV ]; then
        MAKEDEV=/usr/sbin/MAKEDEV
elif [ -f /sbin/makedev ]; then
        MAKEDEV="/sbin/makedev"
else
        MAKEDEV="MAKEDEV"
fi

# List binaries we need (it does not matter if they are in busybox)
# We skip binaries provides by busybox
################
#### Be careful:  do NOT add bash[1/2] to following list
################  will be added automatically (bash2 version)
BINARIES="${MAKEDEV}
ata_id
cdrom_id
dasd_id
edd_id
path_id
scsi_id
usb_id
vol_id
ash
awk
badblocks
basename
bc
blockdev
bzip2
chattr
checkproc
clamscan
compress
consoletype
debugfs
devfsd
dhclient
dhclient-script
dialog
diff
dmesg
dmsetup
dosfsck
dumpe2fs
e2fsck
e2label
efibootmgr
egrep
eject
elvis
elvis-tiny
ethtool
evms
evms_activate
evmsd
evmsd_worker
evms_gather_info
evms_metadata_backup
evms_metadata_restore
evms_mpathd
evmsn
evms_query
extendfs
fdisk
fgrep
file
file
freshclam
fsck
fsck.jfs
fsck.xfs
fstab-decode
ftp
fuser
grep
grub
grub-install
guessfstype
gzip
halt
hdparm
hotplug
hwclock
hwup
ifconfig
ifdown
ifenslave
ifplugd
ifup
initlog
ip
ipcalc
kerneld
killall
killall5
killproc
less
less.bin
lilo
loadkeys
logdump
logger
logredo
losetup
lsattr
lsof
lvchange
lvcreate
lvdisplay
lvmdiskscan
lvreduce
lvremove
lvrename
lvscan
lynx
mc
md5sum
mdadd
mdadm
mdcreate
mdrun
mdstop
mii-tool
mkchk
mkdosfs
mke2fs
mkfs
mkfs.jfs
mkfs.xfs
mklost+found
mknod
mkpv
mkraid
mkreiserfs
mkswap
modules-update
mount
mount.nfs
${MT}
netstat
nslookup
ntfs-3g
ntfscat
ntfscluster
ntfscmp
ntfsdecrypt
ntfsdump_logfile
ntfsfix
ntfsinfo
ntfsls
ntfsmftalloc
ntfsmount
ntfsmove
ntfstruncate
ntfswipe
pam-console-apply
parted
partimage
partimaged
pidof
ping
portmap
pvchange
pvcreate
pvdisplay
pvmove
pvscan
raidstart
reiserfsck
resize2fs
resize_reiserfs
restorecon
rlogin
route
rpcinfo
rpc.ugidd
rsh
runlevel
scp
screen
script
setserial
sfdisk
showmount
sigtool
silo
smbclient
smbmnt
smbmount
smbumount
sort
ssh
ssh-add
ssh-agent
ssh-keygen
startproc
start_udev
stty
sync
sysctl
tar
telnet
test_extent
tune2fs
udev
udevadm
udevd
udevsend
udevsettle
udevstart
udevtrigger
udev.create_static_devices.sh
umount
uname
usleep
uuidgen
vgcfgbackup
vgcfgrestore
vgchange
vgck
vgcreate
vgdisplay
vgexport
vgextend
vgimport
vgmerge
vgmknodes
vgreduce
vgremove
vgrename
vgscan
vgsplit
vi
xchkdmp
xfs_check
xfs_growfs
xfs_repair
xpeek
"

# /directory=executable_will_be_linked_to=[path/]real_executable
LINKS="/bin=sh=bash
/bin=cut=/usr/bin/cut
/sbin=fsck.ext2=e2fsck
/sbin=fsck.ext3=e2fsck
/sbin=fsck.ext4=e2fsck
/sbin=fsck.ext4dev=e2fsck
/sbin=fsck.msdos=dosfsck
/sbin=mkfs.ext2=mke2fs
/sbin=mkfs.ext3=mke2fs
/sbin=mkfs.ext4=mke2fs
/sbin=mkfs.ext4dev=mke2fs
/sbin=mkfs.msdos=mkdosfs
/sbin=mkfs.reiserfs=mkreiserfs
/sbin=fsck.reiserfs=reiserfsck
/sbin=raid0run=mkraid
/sbin=raidhotadd=raidstart
/sbin=raidhotgeneraterror=raidstart
/sbin=raidhotremove=raidstart
/sbin=raidstop=raidstart
/sbin=depmod=/bin/depmod
/sbin=insmod=/bin/insmod
/sbin=lsmod=/bin/lsmod
/sbin=modprobe=/bin/modprobe
/sbin=mount.nfs=/bin/mount.nfs
/bin=uncompress=compress
/usr/bin=bunzip2=bzip2
/usr/bin=gunzip=gzip
/usr/bin=vi=elvis
/usr/bin=ssh1=ssh
/usr/bin=ssh2=ssh
/usr/bin=gpart=/cdrom/utilities/gpart
/usr/bin=cfdisk=/cdrom/utilities/cfdisk
/usr/bin=memtest=/cdrom/utilities/memtest
/usr/bin=recover=/cdrom/utilities/recover
/usr/bin=ext2resize=/cdrom/utilities/ext2resize
/usr/bin=e2salvage=/cdrom/utilities/e2salvage
/usr/bin=liloconfig=/cdrom/utilities/liloconfig
/usr/bin=grubconfig=/cdrom/utilities/grubconfig
/usr/bin=chntpw=/cdrom/utilities/chntpw
/usr/bin=dd_rescue=/cdrom/utilities/dd_rescue
/usr/bin=lshw=/cdrom/utilities/lshw
/usr/bin=lphdisk=/cdrom/utilities/lphdisk
/usr/bin=smartctl=/cdrom/utilities/smartctl"

MAN_PAGES="
badblocks
bzip2
debugfs
dmsetup
dosfsck
dumpe2fs
e2fsck
evms
evms_activate
evms_gather_info
evms_metadata_backup
evms_metadata_restore
evms_query
extendfs
fsck
fsck.jfs
fsck.xfs
fstab
ftp
grub
gzip
hdparm
hotplug
lilo
lilo.conf
loadkeys
logdump
logredo
lvchange
lvcreate
lvdisplay
lvmdiskscan
lvreduce
lvremove
lvrename
lvscan
md5sum
mdadm
mii-tool
mkcdrec
mkdosfs
mke2fs
mkfs.jfs
mkfs.xfs
mkinitrd
mkraid
mkreiserfs
mount
partimage
partimaged
partimagedusers
pvchange
pvcreate
pvdisplay
pvmove
pvscan
raid0run
raidstop
raidtab
raidtart
reiserfsck
rsh
scp
screen
smbclient
smbmnt
smbmount
smbumount
ssh
ssh-keygen
stty
tune2fs
vgcfgbackup
vgcfgrestore
vgchange
vgck
vgcreate
vgdisplay
vgexport
vgextend
vgimport
vgmerge
vgmknodes
vgreduce
vgremove
vgrename
vgscan
vgsplit
xchkdmp
xfs_check
xfs_growfs
xfs_repair
xpeek
"

# Set this to the name of the flavor in ${ROOTFS}/etc/rc.d/flavors which
# should be run as rc.local.
#INIT_FLAVOR="vanilla"
INIT_FLAVOR="dialog"

################################
# Tivoli Storage Manager support
################################
# Set this and make any necessary adjustments if TSM is used for backups:
TSM_RESTORE="n" # y = yes, anything else = no
TSM_ROOT_DIR="/opt/tivoli/tsm/client/ba/bin"
TSM_FILES="
/etc/adsm/TSM.PWD
${TSM_ROOT_DIR}/dsmc
${TSM_ROOT_DIR}/dsm.opt
${TSM_ROOT_DIR}/dsm.sys
${TSM_ROOT_DIR}/inclexcl*
${TSM_ROOT_DIR}/plugins*
${TSM_ROOT_DIR}/lib*
${TSM_ROOT_DIR}/en_US/dscjres.txt
${TSM_ROOT_DIR}/en_US/dsmc.hlp
${TSM_ROOT_DIR}/en_US/dsmclientV3.cat
${TSM_ROOT_DIR}/en_US/dsmhelp.key
${TSM_ROOT_DIR}/en_US/dsmhelp.text
"
###############

##############################################
# HP Openview Data Protector restore support #
# Sponsored by Hewlett-Packard Belgium       #
##############################################
# made the code a bit clever - do not forget to change DP_DATALIST_NAME
if [ -d /usr/omni ]; then
   DP_ROOT_DIR="/usr/omni"      # DP 5.x
   DP_CONFIG_DIR="/usr/omni/config"      # DP 5.x
   DP_NLS_DIR="/usr/omni/config/nls"      # DP 5.x
   DP_LBIN_DIR="/usr/omni/bin"      # DP 5.x
elif [ -d /opt/omni ]; then
   DP_ROOT_DIR="/opt/omni"      # DP 6.x
   DP_CONFIG_DIR="/etc/opt/omni"      # DP 6.x
   DP_NLS_DIR="/opt/omni/lib/nls"      # DP 6.x
   DP_LBIN_DIR="/opt/omni/lbin"      # DP 5.x
else
  DP_ROOT_DIR="/opt/omni"	# set anyway as rd-base.sh does test for dir
fi
DP_RESTORE="y"  # "y" to add DP binaries to CD
DP_FILES="
${DP_LBIN_DIR}/fsbrda
${DP_LBIN_DIR}/vrda
${DP_LBIN_DIR}/rrda
${DP_LBIN_DIR}/rma
${DP_LBIN_DIR}/rbda
${DP_ROOT_DIR}/bin/omnir
${DP_LBIN_DIR}/devbra
${DP_ROOT_DIR}/bin/omnimnt
${DP_ROOT_DIR}/bin/omnidb
${DP_LBIN_DIR}/inet
${DP_ROOT_DIR}/lib/libBrandChg.so
${DP_ROOT_DIR}/lib/libdc.so
${DP_ROOT_DIR}/lib/libde.so
${DP_NLS_DIR}/C/omni.cat
${DP_NLS_DIR}/locale.map
${DP_CONFIG_DIR}/cell/cell_server
${DP_CONFIG_DIR}/client/cell_server
${DP_CONFIG_DIR}/cell/omni_format
${DP_CONFIG_DIR}/client/omni_format
${DP_CONFIG_DIR}/cell/omni_info
${DP_CONFIG_DIR}/client/omni_info
"
# Following is Datalist name of full host backup (of system where you run
# mkcdrec on; purpose is to restore system data via DP)
DP_DATALIST_NAME="testbackup"

################################
# Legato Networker support
################################
NSR_ROOT_DIR="/nsr"
NSR_RESTORE="n" #  y = yes, anything else = no
NSR_FILES="
${NSR_ROOT_DIR}/mm
${NSR_ROOT_DIR}/lic
${NSR_ROOT_DIR}/lic/res
${NSR_ROOT_DIR}/rap
${NSR_ROOT_DIR}/res
${NSR_ROOT_DIR}/res/servers
${NSR_ROOT_DIR}/res/nsrla.res
${NSR_ROOT_DIR}/res/nsrwizclnt.res
${NSR_ROOT_DIR}/tmp
${NSR_ROOT_DIR}/tmp/sec
${NSR_ROOT_DIR}/tmp/adv_ssids
${NSR_ROOT_DIR}/logs/messages
${NSR_ROOT_DIR}/logs/daemon.log
${NSR_ROOT_DIR}/logs/summary
${NSR_ROOT_DIR}/cores/nsrexecd
${NSR_ROOT_DIR}/cores/nsrexecd/.nsr
${NSR_ROOT_DIR}/index
${NSR_ROOT_DIR}/applogs
/usr/bin/networker
/usr/bin/nsrdsa_recover
/usr/bin/nsrdsa_save
/usr/bin/nsrports
/usr/bin/nsrwatch
/usr/bin/nwadmin
/usr/bin/nwarchive
/usr/bin/nwbackup
/usr/bin/nwrecover
/usr/bin/nwretrieve
/usr/bin/preclntsave
/usr/bin/pstclntsave
/usr/bin/recover
/usr/bin/save
/usr/bin/savepnpc
/usr/lib/X11/app-defaults
/usr/lib/X11/app-defaults/Networker
/usr/lib/nsr/C
/usr/lib/nsr/C/nsr.help
/usr/lib/nsr/de_de
/usr/lib/nsr/de_de/nsr.help
/usr/lib/nsr/gls
/usr/lib/nsr/gls/cm
/usr/lib/nsr/gls/cm/registry
/usr/lib/nsr/gls/lc
/usr/lib/nsr/gls/lc/os
/usr/lib/nsr/gls/lc/os/portable
/usr/lib/nsr/gls/lc/os/portable/C
/usr/lib/nsr/libfsdc.so
/usr/lib/nsr/poin.cln
/usr/lib/nsr/product.res
/usr/lib/nsr/prrm.cln
/usr/lib/nsr/uasm
/usr/sbin/mminfo
/usr/sbin/mmlocate
/usr/sbin/mmpool
/usr/sbin/networker.cluster
/usr/sbin/nsr_shutdown
/usr/sbin/nsr_support
/usr/sbin/nsradmin
/usr/sbin/nsralist
/usr/sbin/nsrarchive
/usr/sbin/nsrclone
/usr/sbin/nsrcscd
/usr/sbin/nsrdmpix
/usr/sbin/nsrexec
/usr/sbin/nsrexecd
/usr/sbin/nsrinfo
/usr/sbin/nsrmm
/usr/sbin/nsrndmp_2fh
/usr/sbin/nsrndmp_clone
/usr/sbin/nsrndmp_recover
/usr/sbin/nsrndmp_save
/usr/sbin/nsrretrieve
/usr/sbin/nsrsup
/usr/sbin/nsrwizreg
/usr/sbin/preclntsave
/usr/sbin/pstclntsave
/usr/sbin/save
/usr/sbin/savefs
/usr/sbin/savepnpc
"

################################
# Bacula support
################################
# These are automatically set by the Bacula
#  "make" process, so there is no need to 
#  change them.
BACULA_DIR=/home/kern/bacula/rescue/linux/cdrom/bacula
BACULA_RESTORE="n"

###############


###########################################
# AUTOMATIC DISASTER RECOVERY (AUTODR) mode
###########################################
# Set to "y" if you want to activate AUTODR after booting up mkCDrec
# No user interaction needed anymore - Use at your own risk!!!!!!!!!
# All user interactions such as OK to restore, format, etc... will be 
# skipped. No questions asked, just restore the damn thing.
# OK. I pause for 20 seconds (to interrupt the start-restore process)
AUTODR="n"

################################
# Size of the Initial RAM disk #
################################
# The size our initrd-fs in RAM
# Also check your CONFIG_BLK_DEV_RAM_SIZE (it may NOT be bigger!)
# For ia64 use 16384
# openSUSE 10.2/10.3 suggestion: 64000 (x86) and 128000 (x86_64)
INITRDSIZE=16384 # 1k blocks

# SELinux enforcing mode make tar cripple because tar does not support the
# extended attributes that store the security context labels
# See http://fedora.redhat.com/docs/selinux-faq-fc3/ - back up files
# mkcdrec can however do a best effort by temporary disabling SELinux
# during the backup only - if you can live with that make next variable "true"
Disable_SELinux_during_backup=true

#+++++++++++++++++++++++++++++++++++++++++++++++++++#
############### DO NOT EDIT BELOW HERE ##############
#+++++++++++++++++++++++++++++++++++++++++++++++++++#

PROJECT="mkCDrec"

# Debugging (comment the proper line) - shows the commands only
#DEBUG=echo
DEBUG=

# basedir is the directory where you run make in
basedir=`pwd`
# MKCDREC_DIR: same as $basedir
MKCDREC_DIR=${basedir}

# available modules are: rh_pppoe sshd pcmcia (functions is dotted)
MKCDREC_MODULES="`cd ${MKCDREC_DIR}/modules; ls`"

# scripts directory (shell scripts of mkCDrec)
SCRIPTS=${MKCDREC_DIR}/scripts

# stagedir will be used to populate the ramdisks (temporary dir)
stagedir=${MKCDREC_DIR}/stage

# Where the partitions will be mounted on the booted system
LOCALFS=/mnt/local

PATH=/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin:/opt/schily/bin:${MKCDREC_DIR}/bin:${PATH}:/dev:/usr/lib:/usr/libexec/openssh

# To avoid language problems with locale copied executables - thx to Y. Blusseau
LANG="C"
LANG_ALL="C"

# To avoid problem "Unknown escape sequence in input: 33, 133"
GROFF_NO_SGR=1
export GROFF_NO_SGR

# BusyBox ( an all-in-one command - see doc in dir)
# edit ${BUSYBOX_DIR}/Config.h to enable/disable commands
# Disabled TAR (will need GNU tar for permission features...)
BUSYBOX_DIR=${MKCDREC_DIR}/`ls -d busybox* 2>/dev/null`

# cutstream
CUTSTREAM_DIR=${MKCDREC_DIR}/`ls -d cutstream* 2>/dev/null`

# pastestream
PASTESTREAM_DIR=${MKCDREC_DIR}/`ls -d pastestream* 2>/dev/null`

# TMP_DIR & LOG must be defined in Config.sh for mkmakeISO9660.sh (gdha)
# v0.6.2 has a problem with making multiple volumes cause of the missing lines
TMP_DIR=${MKCDREC_DIR}/tmp
# Our log-file
LOG=${MKCDREC_DIR}/mkcdrec.log

kernel_minor_nr=`uname -r | cut -d. -f2`

# The kernel supports devfs (true:1). 2.2 kernels need patches!
# Obsolete - just keep it as our scripts still use this variable
DEVFS=0

#############################
# Read the common functions #
#############################

if [ -x ${MKCDREC_DIR}/scripts/make_common.sh ]; then
	. ${MKCDREC_DIR}/scripts/make_common.sh
fi

###################
# Encryption part #
###################
if [ x$CIPHER = xnone ]; then
        # Use encryption (openssl or cat for plaintext)
        ENC_PROG=cat
        # Cipher to use (try bf, des, ... or empty "" string for plaintext)
        ENC_PROG_CIPHER=""
        ### SECRET KEY usage ###
        # file (use absolute paths) that contains the key to be used w/ openssl
        # Please make sure that the mode is 600 (with chmod) and note that 
        # the key file is only necessary in non-interactive mode 
        # (see 'make help')!
        ENC_PROG_PASSWD_FILE="$HOME/.secret"
else
        ENC_PROG=openssl
        ENC_PROG_CIPHER=$CIPHER
        ENC_PROG_PASSWD_FILE="$HOME/.secret"
fi

#############################################
# The local end-user config file of mkcdrec #
#############################################
#
# The idea is to have a local config file which could be kept during upgrades
# but somehow a cross-check should be done in order to have a consistent
# behaviour of mkCDrec. 
if test -r /etc/mkcdrec.conf ; then
        . /etc/mkcdrec.conf
fi

#############################################
# Basic Colors do not change
#############################################
c_low=0
c_hi=1
c_red=31
c_green=32
c_yellow=33
c_blue=34
c_magenta=35
c_cyan=36
c_blue=34
c_black=30
c_white=37
# background colors
c_bred=41
c_bgreen=42
c_byellow=43
c_bblue=44
c_bmagenta=45
c_bcyan=46
c_bwhite=47
c_bblack=40

c_esc="\033"
c_bold="${c_esc}[1m"
c_norm="${c_esc}[m"


#############################################
# Colors that can be configured
#############################################

if [ x$USECOLOR = xy ] ; then
   hi=1
   c_back=${c_bblack}   #
   c_light="${c_esc}[${c_white}m"
   c_hilight="${c_esc}[${hi};${c_white}m"
   c_higreen="${c_esc}[${hi};${c_green}m"
   c_passed="${c_esc}[${c_green}m" # green
   c_fail="${c_esc}[${c_red}m"   # red

   # selection text
   c_st="${c_esc}[0;${c_cyan};${c_back}m" # cyan on black
   # selection list
   c_sl="${c_esc}[1;${c_yellow};${c_back}m" # yellow on black
   c_warn="${c_esc}[1;${c_red};${c_back}m" # red on black
   c_warntxt="${c_esc}[0;${c_green};${c_back}m" # green on black
   c_error="${c_esc}[1;${c_red};${c_back}m" # red on black
   c_errortxt="${c_esc}[0;${c_green};${c_back}m" # green on black
   c_end="${c_esc}[0;${c_white};${c_back}m" # white on black
   c_hiend="${c_esc}[1;${c_white};${c_back}m" # white on black
   c_askyn="${c_esc}[0;${c_green};${c_back}m" # green on black
   c_sel="${c_esc}[${c_cyan}m"

else

   c_passed=${c_norm}
   c_failed=${c_norm}
   c_light=${c_norm}
   c_hilight=${c_norm}
   c_higreen=${c_norm}
   c_st=${c_norm}
   c_sl=${c_norm}
   c_warn=${c_norm}
   c_warntxt=${c_norm}
   c_error=${c_norm}
   c_errortxt=${c_norm} 
   c_end=${c_norm}
   c_hiend=${c_norm}
   c_askyn=${c_norm}   
   c_sel=${c_norm}

fi
