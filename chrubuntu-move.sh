#!/bin/bash -xe
#
# Script to transfer Ubuntu to Chromebook's media
#
# Version 1.2
#
# Copyright 2012-2013 Jay Lee
# Copyright 2013-2014 Eugene San
#
# Here would be nice to have some license - BSD one maybe
#
# Depends on following packages: cgpt vboot-kernel-utils parted rsync ecryptfs-utils libpam-mount lvm2

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

# Generic settings
release="$(basename ${0})"

# Target specifications
target_mnt="/tmp/urfs"
chromebook_arch="`uname -m`"
target_root="/dev/sda7"
target_home="/dev/sda1"

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
while getopts ant:u: opt; do
	case "$opt" in
		a)	always="yes"		;;
		n)	no_format="yes"		;;
		t)	target_disk="${OPTARG}"	;;
		u)	crypt_user="${OPTARG}"		;;
		*)	cat <<EOB
Usage: [DEBUG=yes] sudo $0 [-a] [-t <disk>]
	-a : Always boot into ubuntu
	-n : Skip partitioning and formatting
	-t : Specify target disk
	-u : Specify user that will mount encrypted target home
Example: $0 -a -t "/dev/sdb"
EOB
			exit 1			;;
	esac
done

# ChrUbuntu partitions configuration
[ -z "${target_disk}" ] && echo "Invalid target specified" && exit 255
target_kern="${target_disk}6"
target_rootfs="${target_disk}7"
target_homefs="${target_disk}1"

# Sanity check target devices
if mount | grep ${target_rootfs} > /dev/null; then
	echo "Found formatted and mounted ${target_rootfs}."
	echo "Attemp to unmount will be made, but you continue on your own risk!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	set +e; umount ${target_mnt}/{dev/pts,dev,sys,proc,home,}
fi
set +e; cryptsetup luksClose home

# Partitioning
echo -e "Got ${target_disk} as target drive\n"
if [ "${no_format}" != "yes" ]; then
	echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
	read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

	parted --script ${target_disk} "mktable gpt"
	cgpt create ${target_disk}

	# Get target device size in 512b sectors
	ext_size="`blockdev --getsz ${target_disk}`"

	kern_start=$((1 * 1024 * 1024 / 512)) # reserve 1M for GPT structs
	kern_size=$((16 * 1024 * 1024 / 512)) # 16M
	cgpt add -i 6 -b ${kern_start} -s ${kern_size} -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}

	root_start=$((24 * 1024 * 1024 / 512)) # 24M
	root_size=$((8 * 1024 * 1024 * 1024 / 512)) # 8GB
	cgpt add -i 7 -b ${root_start} -s ${root_size} -l ROOT-A -t "rootfs" ${target_disk}

	home_start=$((root_start + root_size))
	home_size=$((ext_size - root_start - root_size - kern_start)) # reserve 1M for GPT structs
	cgpt add -i 1 -b ${home_start} -s ${home_size} -l DATA-A -t "data" ${target_disk}

	sync
	blockdev --rereadpt ${target_disk}
	partprobe ${target_disk}
else
	echo -e "INFO: Partitioning skipped.\n"
fi

# Print summary
echo -e "Target Kernel Partition: ${target_kern}, Target Root FS: ${target_rootfs}, Target Mount Point: ${target_mnt}\n"
read -p "Press [Enter] to continue..."


# Creating target filesystems
if [ "${no_format}" != "yes" ]; then
	# Format rootfs
	mkfs.ext4 ${target_rootfs}

	# Format home
	if [ -n "${crypt_user}" ]; then
		echo -e "Target home will be encrypted: $target_home. Use [${crypt_user}]'s password at all stages.\n"
		read -p "Press [Enter] to continue..."
		cryptsetup -q -y -v luksFormat ${target_homefs}
		cryptsetup luksOpen ${target_homefs} home
		target_homefs="/dev/mapper/home"
	fi
	mkfs.ext4 ${target_homefs}
else
	if [ -n "${crypt_user}" ]; then
		cryptsetup luksOpen ${target_homefs} home
		target_homefs="/dev/mapper/home"
	fi

	echo -e "INFO: Formatting skipped.\n"
fi

# Mounting target filesystems
mkdir -p ${target_mnt}
mount -t ext4 ${target_rootfs} ${target_mnt}
mkdir -p ${target_mnt}/home
mount -t ext4 ${target_homefs} ${target_mnt}/home

# Transferring host system to target
rsync -ax --exclude=/initrd* --exclude=/vmlinuz* --exclude=/boot --exclude=/lib/modules --exclude=/lib/firmware / /dev ${target_mnt}/

# Allow selected crypt user to mount home during login (libpam-mount is required)
if [ -n "${crypt_user}" ]; then
	echo "<volume user=\"${crypt_user}\" fstype=\"auto\" path=\"${target_home}\" mountpoint=\"/home\" />" > /tmp/crypt_pam_mount
	sed -i '/Volume\ definitions/r /tmp/crypt_pam_mount' ${target_mnt}/etc/security/pam_mount.conf.xml
fi

# Tune touchpad
mkdir -p ${target_mnt}/usr/share/X11/xorg.conf.d
cat > ${target_mnt}/usr/share/X11/xorg.conf.d/touchpad.conf << EOZ
Section "InputClass"
	Identifier "touchpad"
	MatchIsTouchpad "on"
	Option "FingerHigh" "10"
	Option "FingerLow" "10"
EndSection
EOZ

# Keep CromeOS partitions from showing/mounting
udev_target=${target_disk:5}
echo "KERNEL==\"${udev_target}1\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"${udev_target}3\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"${udev_target}5\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"${udev_target}8\" ENV{UDISKS_IGNORE}=\"1\"
" > ${target_mnt}/etc/udev/rules.d/99-hide-disks.rules

# Refresh H/W pinning
rm -f ${target_mnt}/etc/udev/rules.d/*.rules

# Note: as side effect LID will stop working!
sed -i 's/^exit\ 0/\necho\ disable\ >\ \/sys\/firmware\/acpi\/interrupts\/gpe1F\nexit\ 0/' ${target_mnt}/etc/rc.local

# Disable auto interfaces
sed -i 's/^auto\ eth/#auto\ eth/' ${target_mnt}/etc/network/interfaces

# Use original ChromeOS kernel, modules and firmwares
kernel=${release%.*}.img.xz
lib=${release%.*}.tar.xz
kernel_orig=/tmp/kern.orig.img
config=/tmp/vmlinuz.cfg
newkern=/tmp/kern.img

# Prepare kernel comdline
# console= loglevel=7 init=/sbin/init cros_secure oops=panic panic=-1 root=/dev/dm-1 rootwait ro dm_verity.error_behavior=3 dm_verity.max_bios=-1 dm_verity.dev_wait=1 dm="2 vboot none ro1,0 2545920 bootcache PARTUUID=%U/PARTNROFF=1 2545920 b9d6fa324c47bc0c0a3f96c9a16d9a317432aa9d 512 20000 100000, vroot none ro 1,0 2506752 verity payload=254:0 hashtree=254:0 hashstart=2506752 alg=sha1 root_hexdigest=24393ba8b75a7fd85d73c233ceee70af4e9087ef salt=b012108da6fdd54d3d603ae24fe371ef18e787f788224c19711643bf8cd2e9af" noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3
#echo "console=tty1 debug verbose root=${target_root} rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic" > $config
#echo "console=tty1 loglevel=7 oops=panic panic=-1 root=${target_root} rootwait rw noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3" > $config
#echo "console=tty1 loglevel=7 oops=panic panic=-1 root=${target_root} rootwait rw noinitrd kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3" > $config
#echo "console=tty1 loglevel=7 init=/sbin/init oops=panic panic=-1 root=${target_root} rootwait rw noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3" > $config
echo "console=tty1 loglevel=7 init=/sbin/init oops=panic panic=-1 root=${target_root} rootwait rw noinitrd kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic" > $config

# Install kernel
xzcat ${kernel} > ${kernel_orig}
vbutil_kernel --repack ${newkern} \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--version 1 \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config ${config} \
	--oldblob ${kernel_orig}
dd if=${newkern} of=${target_kern} bs=4M

# Install lib/{modules,fimrwares}
tar -C ${target_mnt} -xaf ${lib}

echo -e "Installation seems to be complete.\n"
read -p "Press [Enter] to unmount target device..."

sync
umount ${target_mnt}/home ${target_mnt}
cryptsetup luksClose home
