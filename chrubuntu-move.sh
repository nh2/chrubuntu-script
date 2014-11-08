#!/bin/bash -xe
#
# Script to transfer Ubuntu to Chromebook's media
#
# Version 1.7
#
# Copyright 2012-2013 Jay Lee
# Copyright 2013-2014 Eugene San
#
# Post install procedure:
# https://github.com/darkknight1812/c710_ubuntu_pis/blob/master/install.sh
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

# Default target specifications
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
while getopts nt:u:q opt; do
	case "$opt" in
		n)	no_format="yes"		;;
		t)	target_disk="${OPTARG}"	;;
		u)	crypt_user="${OPTARG}"		;;
		q)	no_sync="yes"		;;
		*)	cat <<EOB
Usage: [DEBUG=yes] sudo $0 [-a] [-t <disk>]
	-n : Skip partitioning and formatting
	-t : Specify target disk
	-u : Specify user that will mount encrypted target home
	-q : Skip syncing
Example: $0 -t "/dev/sdb" -n
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
if [ -n "${crypt_user}" ]; then
	mkdir -p ${target_mnt}/home
	mount -t ext4 ${target_homefs} ${target_mnt}/home
fi

# Transferring host system to target
if [ "${no_sync}" != "yes" ]; then
	rsync -ax / /dev ${target_mnt}/
fi

# Allow selected crypt user to mount home during login (libpam-mount is required)
if [ -n "${crypt_user}" ]; then
	echo "<volume user=\"${crypt_user}\" fstype=\"auto\" path=\"${target_home}\" mountpoint=\"/home\" />" > /tmp/crypt_pam_mount
	sed -i '/Volume\ definitions/r /tmp/crypt_pam_mount' ${target_mnt}/etc/security/pam_mount.conf.xml
fi

# Enabled touchpad modules
cat << 'EOF' | tee -a /etc/modules
i2c_i801
i2c_dev
chromeos_laptop
cyapa
EOF

# Configure touchpad
sed -i '18i Option "VertHysteresis" "10"' $target_mnt/usr/share/X11/xorg.conf.d/50-synaptics.conf
sed -i '18i Option "HorizHysteresis" "10"' $target_mnt/usr/share/X11/xorg.conf.d/50-synaptics.conf
sed -i '18i Option "FingerLow" "1"' $target_mnt/usr/share/X11/xorg.conf.d/50-synaptics.conf
sed -i '18i Option "FingerHigh" "5"' $target_mnt/usr/share/X11/xorg.conf.d/50-synaptics.conf

# Refresh H/W pinning
rm -f ${target_mnt}/etc/udev/rules.d/*.rules

# Keep CromeOS partitions from showing/mounting
udev_target=${target_disk:5}
cat << 'EOF' | tee -a ${target_mnt}/etc/udev/rules.d/99-hide-disks.rules
KERNEL=="$udev_target1" ENV{UDISKS_IGNORE}="1"
KERNEL=="$udev_target3" ENV{UDISKS_IGNORE}="1"
KERNEL=="$udev_target5" ENV{UDISKS_IGNORE}="1"
KERNEL=="$udev_target8" ENV{UDISKS_IGNORE}="1"
EOF

# Install kexec trigger to switch to Ubuntu kernel on first boot
cat << 'EOF' | tee ${target_mnt}/etc/rcS.d/S00chrubuntu
!/bin/sh

test "x`uname -r`" = "x3.4.0" || exit 0
service kexec-load stop
service kexec stop
EOF
chmod +x ${target_mnt}/etc/rcS.d/S00chrubuntu

# Disabled LID interrupt to workaround cpu usage after lid closure
# (LID will stop working!)
sed -i 's/^exit\ 0/\necho\ disable\ >\ \/sys\/firmware\/acpi\/interrupts\/gpe1F\nexit\ 0/' ${target_mnt}/etc/rc.local

# Enabled energy savers
sed -i 's/splash/"splash intel_pstate=enable"/' ${target_mnt}/etc/default/grub
sed -i 's/^GOVERNOR=.*/GOVERNOR="powersave"/' ${target_mnt}/etc/init.d/cpufrequtils

# Install post install script
cat << 'EOF' | tee ${target_mnt}/postinst.sh
!/bin/sh

update-grub
add-apt-repository ppa:linrunner/tlp
aptitude update
aptitude install cpufrequtils thermald tlp tlp-rdw smartmontools ethtool synaptic
EOF
chmod +x ${target_mnt}/postinst.sh

# Disable auto interfaces
sed -i 's/^auto\ eth/#auto\ eth/' ${target_mnt}/etc/network/interfaces

# Use original ChromeOS kernel, modules and firmwares
kernel=${release%.*}.kernel.xz
lib=${release%.*}.tar.xz
kernel_unxz=/tmp/${release%.*}.kernel
cmdline=/tmp/${release%.*}.kernel.cmdline
kernel_ck=/tmp/${release%.*}.kernel.ck

# Prepare kernel comdline
# console= loglevel=7 init=/sbin/init cros_secure oops=panic panic=-1 root=/dev/dm-1 rootwait ro dm_verity.error_behavior=3 dm_verity.max_bios=-1 dm_verity.dev_wait=1 dm="2 vboot none ro1,0 2545920 bootcache PARTUUID=%U/PARTNROFF=1 2545920 b9d6fa324c47bc0c0a3f96c9a16d9a317432aa9d 512 20000 100000, vroot none ro 1,0 2506752 verity payload=254:0 hashtree=254:0 hashstart=2506752 alg=sha1 root_hexdigest=24393ba8b75a7fd85d73c233ceee70af4e9087ef salt=b012108da6fdd54d3d603ae24fe371ef18e787f788224c19711643bf8cd2e9af" noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3
		echo "console=tty1 debug verbose root=${target_root} rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic disablevmx=off runlevel=1" > $cmdline

# Install kernel
xzcat ${kernel} > ${kernel_unxz}
vbutil_kernel --repack ${kernel_ck} \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--version 1 \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config ${cmdline} \
	--oldblob ${kernel_unxz}
dd if=${newkern} of=${target_kern} bs=4M

# Install lib/{modules,fimrwares}
tar -C ${target_mnt} -xaf ${lib}

echo -e "Installation seems to be complete.\n"
read -p "Press [Enter] to unmount target device..."

sync
if [ -n "${crypt_user}" ]; then
	umount ${target_mnt}/home
	cryptsetup luksClose home
fi
umount ${target_mnt}
