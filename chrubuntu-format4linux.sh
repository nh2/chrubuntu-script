#!/bin/bash -xe

# Generic settings
arch="`uname -m`"
release="stock-4.7.1-plopkexec"
kernel_image="$(dirname ${0})/images/${release}"
working_dir="."

target_disk="/dev/sdb"
esp_part=1
lbp_part=12
kernel_part=2
rootfs_part=3
homefs_part=4

# Unpack kernel
[ -r "${kernel_image}" ] || xz -d -k  "${kernel_image}.xz"

# Make dummy bootloader stub
[ -r "${kernel_image}.bootstub.efi" ] || echo "dummy" > ${kernel_image}.bootstub.efi

# Make comdline
[ -r "${kernel_image}.cmdline" ] || echo "dummy" > ${kernel_image}.cmdline

# Pack kernel in ChromeOS format
[ -r "${kernel_image}.ck" ] || ./futility vbutil_kernel --pack ${kernel_image}.ck \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config ${kernel_image}.cmdline \
	--bootloader ${kernel_image}.bootstub.efi \
	--vmlinuz ${kernel_image} \
	--arch x86 \
	--version 1

# Make sure the new kernel verifies OK.
vbutil_kernel --verbose --verify ${kernel_image}.ck

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

# ESP [EFI System Partition] (255M)
esp=255
esp_start=$((gpt_size))
esp_size=$((esp * 1024 * 1024 / 512))
sudo cgpt add -i ${esp_part} -b ${esp_start} -s ${esp_size} -l EFI-SYSTEM -t "efi" ${target_disk}

# GRUB [Bios GRUB] (16M)
lbp=16
lbp_start=$((esp_start + esp_size))
lbp_size=$((lbp * 1024 * 1024 / 512))
sudo cgpt add -i ${lbp_part} -b ${lbp_start} -s ${lbp_size} -l BIOS-GRUB -t "data" ${target_disk}
sudo parted ${target_disk} set ${lbp_part} bios_grub on
sudo parted ${target_disk} set ${lbp_part} legacy_boot on

# Chrome Kernel (16M)
kern=16
kern_start=$((lbp_start + lbp_size))
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
sudo dd if=${kernel_image}.ck of=${target_disk}${kernel_part}

# Sync
sync
