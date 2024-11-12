#! /bin/bash
#
# start_udev
#
# script to initialize /dev by using udev.
#
# Copyright (C) 2004 Greg Kroah-Hartman <greg@kroah.com>
#
# Released under the GPL v2 only.
#
# This needs to be run at the earliest possible point in the boot 
# process.
#
# Based on the udev init.d script
#
# Thanks go out to the Gentoo developers for proving 
# that this is possible to do.
#
# Yes, it's very verbose, feel free to turn off all of the echo calls,
# they were there to make me feel better that everything was working
# properly during development...
#

. /etc/udev/udev.conf

prog=udev
sysfs_dir=/sys
bin=/sbin/udev
udevd=/sbin/udevd

run_udev () {
	# handle block devices and their partitions
	for i in ${sysfs_dir}/block/*; do
		# add each drive
		export DEVPATH=${i#${sysfs_dir}}
		echo "$DEVPATH"
		$bin block

		# add each partition, on each device
		for j in $i/*; do
			if [ -f $j/dev ]; then
				export DEVPATH=${j#${sysfs_dir}}
				echo "$DEVPATH"
				$bin block
			fi
		done
	done
	# all other device classes
	for i in ${sysfs_dir}/class/*; do
		for j in $i/*; do
			if [ -f $j/dev ]; then
				export DEVPATH=${j#${sysfs_dir}}
				CLASS=`echo ${i#${sysfs_dir}} | \
					cut -d/ -f3-`
				echo "$DEVPATH"
				$bin $CLASS
			fi
		done
	done
	return 0
}

make_extra_nodes () {
	# there are a few things that sysfs does not export for us.
	# these things go here (and remember to remove them in 
	# remove_extra_nodes()
	#
	# Thanks to Gentoo for the initial list of these.
	ln -snf /proc/self/fd $udev_root/fd
	ln -snf /proc/self/fd/0 $udev_root/stdin
	ln -snf /proc/self/fd/1 $udev_root/stdout
	ln -snf /proc/self/fd/2 $udev_root/stderr
	ln -snf /proc/kcore $udev_root/core

	mkdir $udev_root/pts
	mkdir $udev_root/shm
}

# don't use udev if sysfs is not mounted.
if [ ! -d $sysfs_dir/block ]; then
	echo "udev: sysfs is not mounted, exiting"
	exit 1
fi

echo "mounting... ramfs at $udev_root"
mount -n -t ramfs none $udev_root

# propogate /udev from /sys
export ACTION=add
export UDEV_NO_SLEEP=1
echo "udev: Creating initial udev device nodes:"

# You can use the shell scripts above by calling run_udev or execute udevstart
# which does the same thing, but much faster by not using shell.  
#  only comment out one of the following lines.
#run_udev
/sbin/udevstart

echo "udev: Making extra nodes"
make_extra_nodes

echo "udev: Startup is finished!"
