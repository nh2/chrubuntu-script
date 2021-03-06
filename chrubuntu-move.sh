#!/bin/bash -xe
#
# Script to transfer Ubuntu to Chromebook's media
#
# Version 2.2
#
# Copyright 2012-2013 Jay Lee
# Copyright 2013-2016 Eugene San
#
# Post install procedure:
# https://github.com/darkknight1812/c710_ubuntu_pis/blob/master/install.sh
#
# Here would be nice to have some license - BSD one maybe
#
# Depends on following packages: cgpt vboot-kernel-utils parted rsync ecryptfs-utils libpam-mount lvm2

setterm -blank 0

# Generic settings
release="parrot-R50"
working_dir="."

# Default target specifications
chromebook_arch="`uname -m`"
esp_part=12
kernel_part=6
rootfs_part=7
homefs_part=1
runtime_kernel="/dev/sda${kernel_part}"
runtime_rootfs="/dev/sda${rootfs_part}"
runtime_homefs="/dev/sda${homefs_part}"
target_mnt="/tmp/urfs"

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
while getopts iu:fpqo:d:st opt; do
	case "$opt" in
		f)	no_format="yes";;
		s)	no_sync="yes";;
		k)	no_kernel="yes";;
		t)	no_tweak="yes";;
		o)	target_disk="${OPTARG}";;
		u)	if [ -n "${crypt_user}" ]; then crypt_users="${crypt_users} ${OPTARG}"; else crypt_user="${OPTARG}"; fi;;
		p)	packages="yes";;
		d)	working_dir="${OPTARG}";;
		*)	cat <<EOB
Usage: sudo $0 [-u user1]...[-u userx] [-n] [-q] [-t <disk>]
	-f : Skip partitioning and formatting
	-s : Skip syncing
	-w : Skip tweaking
	-p : Install target required packages on host
	-u : Specify user that will mount encrypted target home
	-d : Specify working directory
	-o : Specify target disk
Example: $0 -u user -n -t "/dev/sdb"
EOB
			exit 1;;
	esac
done

if [ "${packages}" == "yes" ]; then
	# Install target required packages on host
	echo "Going to install target required packages on host!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	aptitude install cgpt vboot{,-kernel}-utils parted rsync libpam-mount cryptsetup
fi

# ChrUbuntu partitions configuration
[ -z "${target_disk}" ] && echo "Invalid target specified" && exit 255
target_kernel="${target_disk}${kernel_part}"
target_rootfs="${target_disk}${rootfs_part}"
target_homefs="${target_disk}${homefs_part}"

# Sanity check target devices
if mount | grep ${target_disk} > /dev/null; then
	echo "Found formatted and mounted ${target_rootfs}."
	echo "Attemp to unmount will be made, but you continue on your own risk!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	set +e; umount ${target_mnt}/{dev/pts,dev,sys,proc,home,} ${target_rootfs} ${target_homefs}
fi
set +e; cryptsetup luksClose chrohome

# Partitioning
echo -e "Got ${target_disk} as target drive\n"
if [ "${no_format}" != "yes" ]; then
	echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
	read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

	parted --script ${target_disk} "mktable gpt"
	cgpt create ${target_disk}

	# Get target device size in 512b sectors
	ext_size="`blockdev --getsz ${target_disk}`"

	# GPT reserve (1M at the beginning and 1M at the end)
	gpt=1
	gpt_size=$((gpt * 1024 * 1024 / 512))

	# ESP [EFI System Partition] (255M)
	esp=255
	esp_start=$((gpt_size))
	esp_size=$((esp * 1024 * 1024 / 512))
	cgpt add -i ${esp_part} -b ${esp_start} -s ${esp_size} -l EFI-SYSTEM -t "efi" ${target_disk}

	# Chrome Kernel (16M)
	kern=16
	kern_start=$((esp_start + esp_size))
	kern_size=$((kern * 1024 * 1024 / 512))
	cgpt add -i ${kernel_part} -b ${kern_start} -s ${kern_size} -S 1 -P 1 -l KERN-A -t "kernel" ${target_disk}

	# RootFS (16GB)
	rootfs=$((16 * 1024))
	root_start=$((kern_start + kern_size))
	root_size=$((rootfs * 1024 * 1024 / 512))
	cgpt add -i ${rootfs_part} -b ${root_start} -s ${root_size} -l ROOT-A -t "rootfs" ${target_disk}

	# Home (Fill)
	home_start=$((root_start + root_size))
	home_size=$((ext_size - root_start - root_size - gpt_size))
	cgpt add -i ${homefs_part} -b ${home_start} -s ${home_size} -l DATA-A -t "data" ${target_disk}

	sync
	blockdev --rereadpt ${target_disk}
	partprobe ${target_disk}
else
	echo -e "INFO: Partitioning skipped.\n"
fi

# Print summary
echo -e "Installer partitions: Kernel:[${target_kernel}], RootFS: [${target_mnt}@${target_rootfs}|${runtime_rootfs}], Home:[${target_mnt}/home@${target_homefs}|${runtime_homefs}]\n"
read -p "Press [Enter] to continue..."

# Creating target filesystems
if [ "${no_format}" != "yes" ]; then
	# Format rootfs
	mkfs.ext4 ${target_rootfs}

	# Format home
	if [ -n "${crypt_user}" ]; then
		echo -e "Target home will be encrypted: [$target_homefs]. Use [${crypt_user}]'s password at all stages.\n"
		read -p "Press [Enter] to continue..."
		cryptsetup -q -y -v luksFormat ${target_homefs}

		for user in ${crypt_users}; do
			echo -e "Setting password for [${crypt_users}].\nUse different password for each user!.\nTo change password use: cryptsetup luksChangeKey.\n"
			cryptsetup luksAddKey ${target_homefs}
		done

		cryptsetup luksOpen ${target_homefs} chrohome
		target_homefs="/dev/mapper/chrohome"
	fi
	mkfs.ext4 ${target_homefs}
else
	if [ -n "${crypt_user}" ]; then
		for user in ${crypt_users}; do
			echo -e "Setting password for [${crypt_users}].\nUse different password for each user!.\nTo change password use: cryptsetup luksChangeKey.\n"
			cryptsetup luksAddKey ${target_homefs}
		done

		cryptsetup luksOpen ${target_homefs} chrohome
		target_homefs="/dev/mapper/chrohome"
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
	rsync -ax --delete --exclude=/tmp/* --exclude=/var/cache/apt/archives/*.deb / /dev ${target_mnt}/
	#rsync -ax --delete $(for user in ${crypt_user}; do echo " --exclude=/home/${user}/*"; done) /home/ ${target_mnt}/home/
fi

# Tweak target system
if [ "${no_tweak}" != "yes" ]; then
	# Allow selected crypt user to mount home during login (libpam-mount is required)
	if [ -n "${crypt_user}" ]; then
		:> /tmp/crypt_pam_mount
		for user in ${crypt_user} ${crypt_users}; do
			echo "<volume user=\"${user}\" fstype=\"auto\" path=\"${runtime_homefs}\" mountpoint=\"/home\" />" >> /tmp/crypt_pam_mount
		done
		sed -i '/Volume\ definitions/r /tmp/crypt_pam_mount' ${target_mnt}/etc/security/pam_mount.conf.xml
	fi

	# Enabled touchpad modules
	cat << 'EOF' | tee -a /etc/modules
	i2c_i801
	i2c_dev
	chromeos_laptop
	cyapa
EOF

	# Cleanup Xorg configs in case VM installed it's config
	pushd ${target_mnt}
	OLDIFS=${IFS}; IFS=" "
	for conf in usr/share/X11/xorg.conf.d/*; do
		dpkg -S /${conf} || rm -v ${conf}
	done
	IFS=${OLDIFS}
	popd

	# Configure touchpad (replaced by xserver-xorg-input-cmt package)
	#sed -i '18i Option "VertHysteresis" "10"' ${target_mnt}/usr/share/X11/xorg.conf.d/50-synaptics.conf
	#sed -i '18i Option "HorizHysteresis" "10"' ${target_mnt}/usr/share/X11/xorg.conf.d/50-synaptics.conf
	#sed -i '18i Option "FingerLow" "1"' ${target_mnt}/usr/share/X11/xorg.conf.d/50-synaptics.conf
	#sed -i '18i Option "FingerHigh" "5"' ${target_mnt}/usr/share/X11/xorg.conf.d/50-synaptics.conf

	# Cleanup H/W pinning
	rm -f ${target_mnt}/etc/udev/rules.d/*.rules

	# Keep some CromeOS partitions from showing/mounting
	udev_target=${target_disk:5}
	cat << 'EOF' | tee ${target_mnt}/etc/udev/rules.d/50-chrubuntu.rules
	KERNEL=="${udev_target}6" ENV{UDISKS_IGNORE}="1"
EOF

	# Install kexec trigger to switch to Ubuntu kernel on first boot
	cat << 'EOF' | tee ${target_mnt}/etc/rcS.d/S00chrubuntu
	#!/bin/sh

	if test "x`uname -r`" = "x3.4.0"; then
		if test -r /boot/kexec.stamp; then
			echo "Kexec stamp is still here, aborting..."
			exit 255
		else
			echo "No Kexec stamp, switching to Ubuntu kernel..."
			touch /boot/kexec.stamp
			sync
			service kexec-load stop
			service kexec stop
		fi
	else
		echo "Kexec succeded, removing stamp..."
		rm -f /boot/kexec.stamp
		sync
	fi
EOF
	chmod +x ${target_mnt}/etc/rcS.d/S00chrubuntu

	# Disabled LID interrupt to workaround cpu usage after lid closure
	# (LID will stop working!)
	sed -i 's/^exit\ 0/\necho\ disable\ >\ \/sys\/firmware\/acpi\/interrupts\/gpe1F\nexit\ 0/' ${target_mnt}/etc/rc.local

	# Enabled energy savers
	sed -i 's/splash/"splash intel_pstate=enable"/' ${target_mnt}/etc/default/grub
	[ ! -r ${target_mnt}/etc/init.d/cpufrequtils ] || sed -i 's/^GOVERNOR=.*/GOVERNOR="powersave"/' ${target_mnt}/etc/init.d/cpufrequtils

	# Disable auto interfaces
	sed -i 's/^auto\ eth/#auto\ eth/' ${target_mnt}/etc/network/interfaces
fi

# Install chrome kernel
if [ "${no_kernel}" != "yes" ]; then
	kernel_image=${working_dir}/images/${release}

	if [ -r "${kernel_image}.cmdline_.orig.gz" ]; then
		# Use original cmdline
		zcat "${kernel_image}.cmdline.orig.gz" > ${kernel_image}.cmdline
	else
		# Prepare kernel cmdline
		#echo "console=tty1 root=${runtime_rootfs} rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic disablevmx=off" > ${kernel_image}.cmdline
		#echo "console=tty1 loglevel=7 oops=panic panic=-1 root=${runtime_rootfs} rootwait ro noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3" > ${kernel_image}.cmdline
		echo "cros_secure console=tty1 root=/dev/sda7 rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap disablevmx=off runlevel=1 verbose" > ${kernel_image}.cmdline
	fi

	# Unpack kernel image
	[ -r "${kernel_image}" ] || xz -d -k "${kernel_image}.xz"

	# Make dummy bootloader stub
	[ -r "${kernel_image}.bootstub.efi" ] || echo "dummy" > ${kernel_image}.bootstub.efi

	# Prepare and install ChromeOS kernel
	vbutil_kernel --pack ${kernel_image}.ck \
		--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
		--version 1 \
		--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
		--config ${kernel_image}.cmdline \
		--vmlinuz ${kernel_image} \
		--bootloader ${kernel_image}.bootstub.efi \
		--arch x86_64

	# Make sure the new kernel verifies OK.
	vbutil_kernel --verify ${kernel_image}.ck --verbose

	# Actually write kernel to target
	dd if=${kernel_image}.ck of=${target_kernel}
fi

# Flush disk wtites
sync

echo -e "Installation seems to be complete.\n"
read -p "Press [Enter] to unmount target device..."

if [ -n "${crypt_user}" ]; then
	umount ${target_mnt}/home
	cryptsetup luksClose chrohome
fi
umount ${target_mnt}

