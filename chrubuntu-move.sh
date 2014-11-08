#!/bin/bash
#
# Script to transfer Ubuntu to Chromebook's media
#
# Copyright 2012-2013 Jay Lee
#
# here would be nice to have some license - BSD one maybe
#

# Allow debugging
if [ -n "$DEBUG" ]; then
	echo "Enabling debug mode"
	DEBUG_WRAP="echo"
	DEBUG_CMD="set -x"
	set -x
	exec 2>&1
else
	set -e
fi

# Target specifications
target_mnt="/tmp/urfs"
chromebook_arch="`uname -m`"

setterm -blank 0

# Basic sanity checks

# Make sure that we have root permissions
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

# Make sure we run as bash
if [ ! $BASH_VERSION ]; then
	echo "This script must be run in bash"
	exit 1
fi

# Gather options from command line and set flags
while getopts aeh:m:np:P:rt:v: opt; do
	case "$opt" in
		a)	always="yes"		;;
		t)	target_disk=${OPTARG}	;;
		*)	cat <<EOB
Usage: [DEBUG=yes] sudo $0 [-a] [-t <disk>]
	-a : Always boot into ubuntu
	-t : Specify target disk
Example: $0 -a -t "/dev/sdc"
EOB
			exit 1			;;
	esac
done

[ -z "${target_disk}" ] && echo "Invalid target specified" && exit 255

# Partitioning
echo -e "Got ${target_disk} as target drive\n"
echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"
ext_size="`blockdev --getsz ${target_disk}`"
aroot_size=$((ext_size - 65600 - 33))
parted --script ${target_disk} "mktable gpt"
cgpt create ${target_disk}
cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
sync
blockdev --rereadpt ${target_disk}
partprobe ${target_disk}

# ChrUbuntu partitions configuration
if [[ "${target_disk}" =~ "mmcblk" ]]; then
	target_rootfs="${target_disk}p7"
	target_kern="${target_disk}p6"
else
	target_rootfs="${target_disk}7"
	target_kern="${target_disk}6"
fi

# Print summary
echo -e "Installing Ubuntu $ubuntu_version with metapackage $ubuntu_metapackage\n"
echo -e "Target Kernel Partition: $target_kern, Target Root FS: ${target_rootfs}, Target Mount Point: ${target_mnt}\n"
read -p "Press [Enter] to continue..."

if mount | grep ${target_rootfs} > /dev/null; then
	echo "Found formatted and mounted ${target_rootfs}."
	echo "Continue at your own risk!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	umount ${target_mnt}/{dev/pts,dev,sys,proc,}
fi

# Creating target filesystem
mkfs.ext4 ${target_rootfs}
mkdir -p $target_mnt
mount -t ext4 ${target_rootfs} $target_mnt

# Transferring host system to target
rsync -axi / /dev $target_mnt/

# Keep CrOS partitions from showing/mounting in Ubuntu
udev_target=${target_disk:5}
echo "KERNEL==\"$udev_target1\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"$udev_target3\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"$udev_target5\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"$udev_target8\" ENV{UDISKS_IGNORE}=\"1\"
" > $target_mnt/etc/udev/rules.d/99-hide-disks.rules

# Fix bug causing high CPU usage after closing LID
# Note: as side effect LID will stop working!
sed -i 's/^$/\necho\ disable\ >\ \/sys\/firmware\/acpi\/interrupts\/gpe1F\n/' $target_mnt/etc/rc.local

# We use host kernel
KERN_VER=`uname -r`
mkdir -p $target_mnt/lib/modules/$KERN_VER/
cp -ar /lib/modules/$KERN_VER/* $target_mnt/lib/modules/$KERN_VER/
[ ! -d $target_mnt/lib/firmware/ ] && mkdir $target_mnt/lib/firmware/
cp -ar /lib/firmware/* $target_mnt/lib/firmware/
kernel=/boot/vmlinuz-`uname -r`
config=vmlinuz.cfg

# We force rootfs to be first hdd in cross mode
target_rootfs=/dev/sda

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > $config

vbutil_kernel --pack newkern \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--version 1 \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config $config \
	--vmlinuz $kernel \
	--arch $chromebook_arch

dd if=newkern of=${target_kern} bs=4M

echo -e "Installation seems to be complete.\n"

if [ "$always" = "yes" ]; then
	echo "Setting Ubuntu kernel partition as top priority for all following boots."
	cgpt add -i 6 -P 5 -S 1 ${target_disk}
	echo -e "If ChrUbuntu fails when you reboot, you will have to perform full ChromeOS recovery "
	echo -e "After thay you may retry ChrUbuntu install."
	echo -e "If you're unhappy with ChrUbuntu when you reboot be sure to run:"
	echo -e "\tsudo cgpt add -i 2 -P 5 -S 1 ${target_disk}\n"
	echo -e "To make ChromeOS the default boot option.\n"
else
	echo "Setting Ubuntu kernel partition as top priority for next boot only."
	cgpt add -i 6 -P 5 -T 1 ${target_disk}
	echo -e "If ChrUbuntu fails when you reboot, power off your Chrome OS device."
	echo -e "When turned on, you'll be back in Chrome OS."
	echo -e "If you're happy with ChrUbuntu when you reboot be sure to run:"
	echo -e "\tsudo cgpt add -i 6 -P 5 -S 1 ${target_disk}\n"
	echo -e "To make ChruBuntu the default boot option.\n"
fi
