#!/bin/bash -ex

# Generic settings
chromebook_arch="`uname -m`"
release="seabios-latest.bin.elf"
coreboot="$(dirname ${0})/images/${release}"
working_dir="."

# Pack coreboot in ChromeOS format
xzcat "${coreboot}.xz" > "${coreboot}"
echo "dummy" > ${coreboot}.cmdline
vbutil_kernel --pack ${coreboot}.ck \
        --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
        --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
        --config ${coreboot}.cmdline \
        --bootloader ${coreboot}.cmdline \
	--vmlinuz ${coreboot} \
	--arch arm \
	--kloadaddr 0xfd120 \
	--version 1

# Make sure the new coreboot verifies OK.
vbutil_kernel --verbose --verify ${coreboot}.ck

# ChrUbuntu partitions configuration
target_disk="/dev/sdb"
target_kernel="${target_disk}2"

# Partitioning
echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"
        
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
sudo cgpt add -i 12 -b ${esp_start} -s ${esp_size} -l EFI-SYSTEM -t "efi" ${target_disk}
        
# Chrome Kernel (16M)
kern=16
kern_start=$((esp_start + esp_size))
kern_size=$((kern * 1024 * 1024 / 512))
sudo cgpt add -i 2 -b ${kern_start} -s ${kern_size} -S 1 -P 1 -l KERN-A -t "kernel" ${target_disk}

# RootFS (16GB)
rootfs=$((16 * 1024))
root_start=$((kern_start + kern_size))
root_size=$((rootfs * 1024 * 1024 / 512))
sudo cgpt add -i 3 -b ${root_start} -s ${root_size} -l ROOT-A -t "rootfs" ${target_disk}

# Home (Fill)
home_start=$((root_start + root_size))
home_size=$((ext_size - root_start - root_size - gpt_size))
sudo cgpt add -i 1 -b ${home_start} -s ${home_size} -l DATA-A -t "data" ${target_disk}

sync
sudo blockdev --rereadpt ${target_disk}
sudo partprobe ${target_disk}

# Actually write kernel to target
sudo dd if=${coreboot}.ck of=${target_kernel} bs=1M

sync
