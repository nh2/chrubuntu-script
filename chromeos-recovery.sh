#!/bin/bash

# Download/Unpack/Mount/Unmount ChromeOS images
# https://support.google.com/chromebook/answer/1080595?hl=en
# Version 0.1
#
# Usage: ${0} [download|unpack|mount|unmount]

OUT="output"
IMAGE="${2}"
: ${IMAGE:="$OUT/ROOT-A"}

if [ -z "$(which cc)" ] || [ -z "$(which fakeroot)" ] || [ -z "$(which git)" ]; then
	echo "Missing tools: cc|fakeroot|git, aborting..."
	exit 1
fi

if [ ! -x ${OUT}/ext4fuse/ext4fuse ]; then
	echo "Preparing to compile ext4fuse from source"
	[ -n `which gcc` ] || sudo apt-get install build-essential
	[ -n `which git` ] || sudo apt-get install git
	[ -r /usr/include/zlib.h ] || sudo apt-get install zlib1g-dev
	[ -r /usr/include/fuse/fuse.h ] || sudo apt-get install libfuse-dev

	[ -d ${OUT}/ext4fuse ] || git clone --depth 1 --single-branch --branch master https://github.com/gerard/ext4fuse.git ${OUT}/ext4fuse
	make -C ${OUT}/ext4fuse
else
	echo "Tools are pre-built."
fi

if [ "${1}" == "download" ]; then
	DEVICE="parrot"
	# Download recovery script
	wget -c "https://dl.google.com/dl/edgedl/chromeos/recovery/recovery.conf?source=linux_recovery.sh" -O linux_recovery.sh

	# Parse links and download image for device
	wget -c $(grep "^url" linux_recovery.sh | grep "_${DEVICE}_recovery_stable" | cut -f2 -d'=')
fi

if [ "${1}" == "unpack" ]; then
	for PART in ROOT-A KERN-A; do
		START=`cgpt show -b ${IMAGE} | grep ${PART} | awk '{print $1}'`
		SIZE=`cgpt show -b ${IMAGE} | grep ${PART} | awk '{print $2}'`
		echo "Unpacking [${PART}]::[${SIZE}@${START}] from [${IMAGE}]"
		dd of=${OUT}/${PART} if=${IMAGE} bs=512 count=${SIZE} skip=${START}
	done
fi

if [ "${1}" == "xmount" ]; then
	echo "Mounting system.img as ext4"
	mkdir -p ${OUT}/mnt
	fakeroot -s ${IMAGE}.fkdb -- ${OUT}/ext4fuse/ext4fuse ${IMAGE} ${OUT}/mnt -o ro,logfile=${OUT}/mnt.log
fi

if [ "${1}" == "xunmount" ]; then
	echo "Un-Mounting system.mnt"
	fakeroot -s ${IMAGE}.fkdb -- fusermount -u ${OUT}/mnt
	rmdir ${OUT}/mnt
	rm ${IMAGE}.fkdb
fi

if [ "${1}" == "mount" ]; then
	echo "Mounting [${IMAGE}] as ext4"
	mkdir -p ${OUT}/mnt
	sudo mount -o loop,ro ${IMAGE} ${OUT}/mnt
fi

if [ "${1}" == "unmount" ]; then
	echo "Un-Mounting system.mnt"
	sudo umount ${OUT}/mnt
	rmdir ${OUT}/mnt
fi

if [ "${1}" == "binaries" ]; then
	echo "Grabbing binaries from [${IMAGE}]"
	sudo XZ_OPT="-9e" tar -C ${OUT}/mnt -cJf ${IMAGE}.binaries.tar.xz \
		etc \
		lib/{firmware,modprobe.d,modules,udev} \
		opt/google/touch \
		usr/share/{alsa,baselayout,chromeos-assets/wallpaper,laptop-mode-tools,misc,vboot}
	sudo chown ${USER}:${USER} ${IMAGE}.binaries.tar.xz
fi
