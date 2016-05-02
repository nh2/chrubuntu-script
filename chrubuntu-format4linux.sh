#!/bin/bash -xe

# Generic settings
chromebook_arch="`uname -m`"
branch="release-R50-7978.B-chromeos-3.8"
release="parrot-R50-kplop"
kernel="$(dirname ${0})/images/${release}"
kernel_build="${release}.build"
working_dir="."

target_disk="/dev/sdb"
bgp_part=1
esp_part=12
kernel_part=2
rootfs_part=3
homefs_part=4

# Unpack kernel
[ -r "${kernel}" ] || xzcat "${kernel}.xz" > "${kernel}"

# Make dummy bootloader stub
[ -r "${kernel}.bootstub.efi" ] || echo "dummy" > ${kernel}.bootstub.efi

# Make comdline
[ -r "${kernel}.cmdline" ] || echo "dummy" > ${kernel}.cmdline

# Pack kernel in ChromeOS format
[ -r "${kernel}.ck" ] || ./futility vbutil_kernel --pack ${kernel}.ck \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config ${kernel}.cmdline \
	--bootloader ${kernel}.bootstub.efi \
	--vmlinuz ${kernel} \
	--arch x86 \
	--version 1

# Make sure the new kernel verifies OK.
vbutil_kernel --verbose --verify ${kernel}.ck

sudo cgpt show ${target_disk} || true

echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

sudo umount ${target_disk}${rootfs_part} ${target_disk}${homefs_part} /dev/mapper/homefs || true
sudo cryptsetup luksClose ${target_disk}${homefs_part} || sudo cryptsetup luksClose homefs || true

# Initialize disk with Chromebookalyout
sudo parted --script ${target_disk} "mktable gpt"
sudo cgpt create ${target_disk}

# Get target device size in 512b sectors
ext_size="`sudo blockdev --getsz ${target_disk}`"

# GPT reserve (1M at the beginning and 1M at the end)
gpt=1
gpt_size=$((gpt * 1024 * 1024 / 512))

# GRUB [Bios GRUB] (16M)
bgp=16
bgp_start=$((gpt_size))
bgp_size=$((bgp * 1024 * 1024 / 512))
sudo cgpt add -i ${bgp_part} -b ${bgp_start} -s ${bgp_size} -l BIOS-GRUB -t "data" ${target_disk}
sudo parted ${target_disk} set ${bgp_part} bios_grub on
sudo parted ${target_disk} set ${bgp_part} legacy_boot on

# ESP [EFI System Partition] (255M)
esp=255
esp_start=$((bgp_start + bgp_size))
esp_size=$((esp * 1024 * 1024 / 512))
sudo cgpt add -i ${esp_part} -b ${esp_start} -s ${esp_size} -l EFI-SYSTEM -t "efi" ${target_disk}

# Chrome Kernel (16M)
kern=16
kern_start=$((esp_start + esp_size))
kern_size=$((kern * 1024 * 1024 / 512))
sudo cgpt add -i ${kernel_part} -b ${kern_start} -s ${kern_size} -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}

# RootFS (12GB)
rootfs=$((12 * 1024))
root_start=$((kern_start + kern_size))
root_size=$((rootfs * 1024 * 1024 / 512))
sudo cgpt add -i ${rootfs_part} -b ${root_start} -s ${root_size} -l ROOTFS -t "data" ${target_disk}

# Home (Remaining)
home_start=$((root_start + root_size))
home_size=$((ext_size - root_start - root_size - gpt_size))
sudo cgpt add -i ${homefs_part} -b ${home_start} -s ${home_size} -l HOME -t "data" ${target_disk}

# Sync and report
sync
sudo blockdev --rereadpt ${target_disk}
sudo partprobe ${target_disk}
sudo cgpt show ${target_disk}

# Format root
sudo mkfs.btrfs -f -L "rootfs" ${target_disk}${rootfs_part}

# Format home
sudo cryptsetup -q -y -v luksFormat ${target_disk}${homefs_part}
sudo cryptsetup luksOpen ${target_disk}${homefs_part} homefs
sudo mkfs.btrfs -L "homefs" /dev/mapper/homefs

# Install kernel
sudo dd if=${kernel}.ck of=${target_disk}${kernel_part}

# Sync
sync
