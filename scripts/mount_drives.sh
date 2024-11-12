. ./Config.sh
. ./ansictrl.sh
. ./restore_common.sh


## debug mode (if for real remove 'echo' command)
DEBUG=

# Version
VERSION=`cat /etc/recovery/VERSION`

if [ "${RESTORE_DEV}" = "CDROM" ]; then
   Check_Multi_volume   # are we dealing with a multi volume CD? True=0
fi

DeviceCdrom             # define CDROM (eg. /dev/hdc)

cd /etc/recovery
for mdsk  in `ls mkfs.* md/mkfs.* lvm/mkfs.* 2>/dev/null`
do
  _dsk=`echo ${mdsk} | cut -d"." -f 2`
  dsk=`echo ${_dsk} | tr "_" "/" | sed -e 's/%137/_/g'`
  print "\nDisk /dev/${dsk} contains the following partition(s):\n"
  grep ${dsk} /etc/recovery/To_Restore | awk '{printf "%s\t%s\t\t%s\n", $1, $2, $3}'

  # List all partitions with one disk, e.g. hda[1-19]
    cat /etc/recovery/To_Restore | grep ${dsk} | \
    { while read Line
    do
      ParseDevice ${Line}
      Fs=`echo ${Line} | awk '{print $2}'`      # eg. /usr
      _Fs=`echo ${Fs} | tr "/" "_"`             # eg. _usr
      FStype=`echo ${Line} | awk '{print $3}'`  # eg. ext2

      # load FStype modules if needed (doesnot hurt anyway)
      modprobe ${FStype} 2>/dev/null
      if [ "${FStype}" = "ext3" ]; then
        modprobe freext3 >/dev/null 2>&1
        sleep 2
      fi
      # mount the partition on LOCALFS
      mount -t ${FStype} /dev/${Dev} ${LOCALFS}
      if [ $? -eq 1 ]; then
        error 1 "Could not mount /dev/${Dev} on ${LOCALFS}. Please investigate manually."
      fi 
      sync; sync; sync
      if [ "${Fs}" = "/" ]; then
        cd ${LOCALFS}
        mkdir proc > /dev/null 2>&1
        /etc/recovery/mkdirs.sh # make any missing mount point
        OK_TO_REBOOT=1 # 1: /proc made (2: LILO OK)
      fi
      cd /
      sync; sync; sync
    done
    } # end of while loop
done # end for dsk loop
