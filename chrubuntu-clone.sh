#!/bin/bash -xe
#
# Script to clone currently runing Ubuntu to Chromebook's media.
# That involves: partitioning, formatting, installing kernel with plopkexe bootloader, clonning and adapting current filesystem
#
# Version 2.4
#
# Copyright 2012-2013 Jay Lee
# Copyright 2013-2016 Eugene San
#
# Here would be nice to have some license - BSD one maybe
#
# Depends on following packages: cgpt vboot-kernel-utils parted rsync libpam-mount cryptsetup

# Make sure we run as bash
if [ ! $BASH_VERSION ]; then
	echo "This script must be invoked in bash"
	exit 1
fi


function help {
	cat <<EOB
Usage: sudo $0 [-d <work_dir>] [-e] [-f] [-h] [-k] [-p] [-s] [-t <disk>] [-w]
	-d : Specify working directory
	-e : Enable home encryption
	-f : Skip partitioning and formatting
	-h : Skip syncing home
	-k : Skip packing and installing kernel
	-p : Install target required packages on host
	-s : Skip syncing rootfs
	-t : Specify target disk
	-w : Skip tweaking
Example: $0 -e -t "/dev/sdb"
EOB
	exit 255
}


# Generic settings
arch="`uname -m`"
release="stock-4.4.8-plopkexec"
kernel_image="$(dirname ${0})/images/${release}"
working_dir="."
target_mnt="/tmp/chrubuntu"

# Default target specifications
esp_part=1
lbp_part=12
kernel_part=2
rootfs_part=3
homefs_part=4

# Gather options from command line and set flags
[ $# -ge 2 ] || help
while getopts d:efhkpst:w opt; do
	case "$opt" in
		d)	working_dir="${OPTARG}";;
		e)	encrypt_home="yes";;
		f)	no_format="yes";;
		h)	no_sync_home="yes";;
		k)	no_kernel="yes";;
		p)	packages="yes";;
		s)	no_sync="yes";;
		t)	target_disk="${OPTARG}";;
		w)	no_tweak="yes";;
		*)	help;;
	esac
done

setterm --clear all

# Make sure that we have root permissions
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

if [ "${packages}" == "yes" ]; then
	# Install target required packages on host
	echo "Going to install target required packages on host!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	aptitude install cgpt vboot{,-kernel}-utils parted rsync libpam-mount cryptsetup
fi

# ChrUbuntu partitions configuration
if [ -z "${target_disk}" ] || [ ! -b "${target_disk}" ]; then
	echo "Invalid target specified"
	exit 255
fi
target_esp="${target_disk}${esp_part}"
target_lbp="${target_disk}${lbp_part}"
target_kernel="${target_disk}${kernel_part}"
target_rootfs="${target_disk}${rootfs_part}"
target_homefs="${target_disk}${homefs_part}"
dir_esp="/boot/efi"
dir_rootfs="/"
dir_homefs="/home"
crypt_homefs="homefs_crypt"
runtime_esp="${target_disk::7}a${esp_part}"
runtime_kernel="${target_disk::7}a${kernel_part}"
runtime_rootfs="${target_disk::7}a${rootfs_part}"
runtime_homefs="${target_disk::7}a${homefs_part}"

# Sanity check target devices
if mount | grep ${target_disk} > /dev/null; then
	echo "Found one or more mounted partitions of ${target_rootfs}."
	echo "Attemp to unmount will be made, but you continue on your own risk!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	set +e; umount ${target_mnt}/{dev/pts,dev,sys,proc,home,} ${target_bootfs} ${target_rootfs} ${target_homefs}
fi

# Close encrypted volume of target home, just in case
cryptsetup luksClose "${crypt_homefs}" || true

# Print summary
echo "Installer partitions:"
echo "Kernel:[${target_kernel}|${runtime_kernel}], ESP:[${target_mnt}${dir_esp}@${target_esp}|${runtime_esp}]"
echo "RootFS:[${target_mnt}${dir_rootfs}@${target_rootfs}|${runtime_rootfs}]"
echo "Home:[${target_mnt}${dir_homefs}@${target_homefs}|${runtime_homefs}(${crypt_homefs})]"
read -p "Press [Enter] to continue..."

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

	# ESP [EFI System Partition] (237M = 256 - gpt - lbp - kernel)
	esp=237
	esp_start=$((gpt_size))
	esp_size=$((esp * 1024 * 1024 / 512))
	cgpt add -i ${esp_part} -b ${esp_start} -s ${esp_size} -l EFI-SYSTEM -t "efi" ${target_disk}

	# Legacy Bios [GRUB] (2M)
	lbp=2
	lbp_start=$((esp_start + esp_size))
	lbp_size=$((lbp * 1024 * 1024 / 512))
	sudo cgpt add -i ${lbp_part} -b ${lbp_start} -s ${lbp_size} -l LEGACY-BOOT -t "data" ${target_disk}
	sudo parted ${target_disk} set ${lbp_part} legacy_boot on
	sudo parted ${target_disk} set ${lbp_part} bios_grub on

	# Chrome Kernel (16M)
	kernel=16
	kernel_start=$((lbp_start + lbp_size))
	kernel_size=$((kernel * 1024 * 1024 / 512))
	cgpt add -i ${kernel_part} -b ${kernel_start} -s ${kernel_size} -S 1 -P 1 -l KERN-C -t "kernel" ${target_disk}

	# RootFS (12GB)
	rootfs=$((12 * 1024))
	root_start=$((kernel_start + kernel_size))
	root_size=$((rootfs * 1024 * 1024 / 512))
	cgpt add -i ${rootfs_part} -b ${root_start} -s ${root_size} -l ROOT-C -t "rootfs" ${target_disk}

	# Home (Remaining - 2nd GPT copy at the end)
	home_start=$((root_start + root_size))
	home_size=$((ext_size - root_start - root_size - gpt_size))
	cgpt add -i ${homefs_part} -b ${home_start} -s ${home_size} -l DATA-C -t "data" ${target_disk}

	sync
	while ! blockdev --rereadpt ${target_disk}; do echo "."; sleep 1; done
	#while ! partprobe ${target_disk}; do echo "."; sleep 1; done
else
	echo -e "INFO: Partitioning skipped.\n"
fi

# Creating target filesystems
if [ "${no_format}" != "yes" ]; then
	# Format esp
	mkfs.vfat -F 32 ${target_esp}

	# Format rootfs
	mkfs.btrfs -f ${target_rootfs}

	# Format home
	if [ "${encrypt_home}" == "yes" ]; then
		echo -e "Target home will be encrypted: [$target_homefs].\nUse password of user [${USER}].\n"
		read -p "Press [Enter] to continue..."
		cryptsetup -q -y -v luksFormat ${target_homefs}

		cryptsetup luksOpen ${target_homefs} "${crypt_homefs}"
		target_homefs="/dev/mapper/${crypt_homefs}"
		echo -e "Target home is encrypted: [$target_homefs].\nAfter first boot, add encryption passwords for all users using:'sudo cryptsetup luksAddKey username'\n"
		read -p "Press [Enter] to continue..."
	fi
	mkfs.btrfs -f ${target_homefs}
else
	echo -e "INFO: Formatting skipped.\n"

	if [ "${encrypt_home}" == "yes" ]; then
		echo -e "Trying to decrypt home is: [$target_homefs].\nUse password of user [${USER}].\n"

		cryptsetup luksOpen ${target_homefs} "${crypt_homefs}"
		target_homefs="/dev/mapper/${crypt_homefs}"
		echo -e "Target home is encrypted: [$target_homefs].\nAfter first boot, add encryption passwords for all users using:'sudo cryptsetup luksAddKey username'\n"
		read -p "Press [Enter] to continue..."
	fi
fi

# Mounting target filesystems
mkdir -p ${target_mnt}${dir_rootfs}
mount -t auto ${target_rootfs} ${target_mnt}
mkdir -p ${target_mnt}${dir_esp} ${target_mnt}${dir_homefs} ${target_mnt}/tmp
mount -t auto ${target_esp} ${target_mnt}${dir_esp}
mount -t auto ${target_homefs} ${target_mnt}${dir_homefs}

# Transferring host system to target
if [ "${no_sync}" != "yes" ]; then
	rsync -ax --delete --exclude=/tmp/* --exclude=${dir_homefs} --exclude=/var/cache/apt/archives/*.deb ${dir_rootfs} /dev ${target_mnt}/
	rsync -ax --delete ${dir_esp} ${target_mnt}/boot/

	# Transferring host home to target
	[ "${no_sync_home}" == "yes" ] || rsync -ax --delete $(for folder in .ccache .gradle .wine Android Downloads Mobile Personal Public Temp; do echo " --exclude=/home/*/${folder}/*"; done) ${dir_homefs}/ ${target_mnt}${dir_homefs}/
fi

# Tweak target system
if [ "${no_tweak}" != "yes" ]; then
	# Allow users to mount home during login (libpam-mount is required)
	echo "<volume user=\"*\" fstype=\"auto\" path=\"${runtime_homefs}\" mountpoint=\"/home\" />" > ${target_mnt}/tmp/crypt_pam_mount
	sed -i '/Volume\ definitions/r /tmp/crypt_pam_mount' ${target_mnt}/etc/security/pam_mount.conf.xml

	# Enabled touchpad modules (cyapatp-kernel-source and xserver-xorg-input-cmt are recommended)
	sed -i 's/blacklist i2c_i801/#blacklist i2c_i801/g' ${target_mnt}/etc/modprobe.d/blacklist.conf

	# Cleanup Xorg configs in we are clonning from VM with guest tools installed
	#pushd ${target_mnt}
	#OLDIFS=${IFS}; IFS=" "
	#for conf in ${target_mnt}/usr/share/X11/xorg.conf.d/*; do
	#	dpkg -S /${conf} || rm -v ${conf}
	#done
	#IFS=${OLDIFS}
	#popd

	# Cleanup H/W pinning
	rm -f ${target_mnt}/etc/udev/rules.d/*.rules

	# Keep some Crome kernel partitions from showing/mounting
	echo "KERNEL==\"${runtime_kernel}\" ENV{UDISKS_IGNORE}=\"1\"" > ${target_mnt}/etc/udev/rules.d/50-chrubuntu.rules

	# Disable LID interrupt to workaround cpu usage after lid closure (LID will stop working!)
	sed -i 's/^exit\ 0/\necho\ disable\ >\ \/sys\/firmware\/acpi\/interrupts\/gpe1F\nexit\ 0/' ${target_mnt}/etc/rc.local

	# Allow network-manager to manage interfaces
	sed -i 's/^auto\ eth/#auto\ eth/' ${target_mnt}/etc/network/interfaces
fi

# Install chrome kernel
if [ "${no_kernel}" != "yes" ]; then
	kernel_image=${working_dir}/images/${release}

	# Unpack kernel image
	[ -r "${kernel_image}" ] || xz -d -k "${kernel_image}.xz"

	# Prepare dummy bootloader stub
	[ -r "${kernel_image}.bootstub.efi" ] || echo "dummy" > ${kernel_image}.bootstub.efi

	# Prepare kernel cmdline
	[ -r "${kernel_image}.cmdline" ] || echo "dummy" > ${kernel_image}.cmdline

	# Pack kernel in ChromeOS format
	[ -r "${kernel}.ck" ] || ./futility vbutil_kernel --pack ${kernel_image}.ck \
		--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
		--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
		--config ${kernel_image}.cmdline \
		--bootloader ${kernel_image}.bootstub.efi \
		--vmlinuz ${kernel_image} \
		--arch ${arch} \
		--version 1

	# Make sure the new kernel verifies OK.
	vbutil_kernel --verbose --verify ${kernel_image}.ck

	# Actually write kernel to target
	dd if=${kernel_image}.ck of=${target_kernel}
fi

# Flush disk wtites
sync

echo -e "Installation seems to be complete.\n"

# Unmount filesystems
read -p "Press [Enter] to unmount target device..."
[ "${encrypt_home}" != "yes" ] || cryptsetup luksClose ${crypt_homefs}
umount ${target_mnt}${dir_esp} ${target_mnt}${dir_homefs} ${target_mnt}
