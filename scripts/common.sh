copy_kernel() {
# $1 is copy destination
	echo "Copying kernel into $1" | tee -a ${LOG}
	cp -v ${LINUX_KERNEL} $1 2> /dev/null || \
	cp -v /boot/vmlinuz-`uname -r` $1 2> /dev/null || \
	cp -v /boot/efi/efi/redhat/vmlinuz-`uname -r` $1 2> /dev/null || \
	cp -v bzImage  $1 2> /dev/null || \
	cp -v zImage $1 2> /dev/null || \
	cp -v vmlinuz $1 2> /dev/null || \
	cp -v vmlinux $1 2> /dev/null || \
	cp -v linux $1 2> /dev/null || \
	cp -v /vmlinuz $1 2> /dev/null || \
	cp -v /boot/vmlinuz $1 2> /dev/null || \
	cp -v /boot/vmlinux $1 2> /dev/null || \
	error 1 "No kernel image was found!"
# Reinitialize the default BootDevice of the kernel copy
	[ -f "$1" ] && rdev "$1" 0,0
}
