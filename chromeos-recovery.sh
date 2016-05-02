#!/bin/bash -xe

shopt -s lastpipe           # Set *lastpipe* option
set +m                      # Disabling job control

# Download/Unpack/Mount/Unmount ChromeOS images
# https://support.google.com/chromebook/answer/1080595?hl=en
# Version 0.2
#
# Usage: ${0} [download|unpack|zmount|zunmount|mount|unmount|lmount|lunmount|binaries]

OUT="output"
IMAGE="${2}"

: ${DEVICE:="parrot"}
: ${KERNEL:="KERN-A"}
: ${ROOT:="ROOT-A"}

if [ -z "$(which fakeroot)" ] || [ -z "$(which xz)" ] || [ -z "$(which archivemount)" ] || [ -z "$(which cgpt)" ]; then
	echo "Missing tools: fakeroot|xz-utils|arhivemount|cgpt, installing..."
	[ -n `which fakeroot` ] || sudo aptitude install fakeroot
	[ -n `which xz` ] || sudo aptitude install xz-utils
	[ -n `which archivemount` ] || sudo aptitude install archivemount
	[ -n `which cgpt` ] || sudo aptitude install cgpt
else
	echo "Tools are pre-installed."
fi

if [ ! -x ${OUT}/ext4fuse/ext4fuse ] && [ "${1}" != "download" ]; then
	echo "Preparing to compile ext4fuse from source"
	[ -n `which gcc` ] || sudo aptitude install build-essential
	[ -n `which git` ] || sudo aptitude install git
	[ -r /usr/include/zlib.h ] || sudo aptitude install zlib1g-dev
	[ -r /usr/include/fuse/fuse.h ] || sudo aptitude install libfuse-dev

	[ -d ${OUT}/ext4fuse ] || git clone --depth 1 --single-branch --branch master https://github.com/gerard/ext4fuse.git ${OUT}/ext4fuse
	make -C ${OUT}/ext4fuse
else
	echo "Custom tools are pre-built or not required"
fi

if [ "${1}" == "download" ]; then
	# Download recovery script
	wget -c "https://dl.google.com/dl/edgedl/chromeos/recovery/recovery.conf?source=linux_recovery.sh" -O chromeos-recovery.conf

	# Parse links and download image for device
	wget -c $(grep "^url" chromeos-recovery.conf | grep "_${DEVICE}_recovery_stable" | cut -f2 -d'=')
fi

if [ "${1}" == "unpack" ]; then
	for PART in ${KERNEL} ${ROOT}; do
		cgpt show -b ${IMAGE} | grep ${PART} | awk '{print $1" "$2}' | read START SIZE
		#START=`cgpt show -b "${IMAGE}" | grep "${PART}" | awk '{print $1}'`
		#SIZE=`cgpt show -b "${IMAGE}" | grep "${PART}" | awk '{print $2}'`
		echo "Unpacking [${PART}]::[${SIZE}@${START}] from [${IMAGE}]"
		dd of=${OUT}/${PART} if=${IMAGE} bs=512 count=${SIZE} skip=${START}
	done
fi

if [ "${1}" == "zmount" ]; then
	echo "Mounting [${IMAGE}] as ZIP"
	mkdir -p ${OUT}/img
	archivemount -o allow_root ${IMAGE} ${OUT}/img
fi

if [ "${1}" == "lmount" ]; then
	cgpt show -b ${IMAGE} | grep ${ROOT} | awk '{print $1" "$2}' | read -a PARTINFO
	#START=`cgpt show -b ${IMAGE} | grep ${ROOT} | awk '{print $1}'`
	#SIZE=`cgpt show -b ${IMAGE} | grep ${ROOT} | awk '{print $2}'`
	START="${PARTINFO[0]}"
	SIZE="${PARTINFO[1]}"
	echo "Looping mount [${ROOT}]::[${SIZE}@${START}] from [${IMAGE}] as ext4"
	mkdir -p ${OUT}/mnt
	sudo mount -o loop,offset=$((${START} * 512)),sizelimit=$((${SIZE} * 512)),ro ${IMAGE} ${OUT}/mnt
fi

if [ "${1}" == "xmount" ]; then
	echo "xMounting system.img as ext4"
	mkdir -p ${OUT}/mnt
	fakeroot -s ${IMAGE}.fkdb -- ${OUT}/ext4fuse/ext4fuse ${IMAGE} ${OUT}/mnt -o ro,logfile=${OUT}/mnt.log
fi

if [ "${1}" == "xunmount" ]; then
	echo "xUn-Mounting system.mnt"
	fakeroot -s ${IMAGE}.fkdb -- fusermount -u ${OUT}/mnt
	rmdir ${OUT}/mnt
	rm ${IMAGE}.fkdb
fi

if [ "${1}" == "zunmount" ]; then
	echo "zUn-Mounting"
	fusermount -u ${OUT}/img
	rmdir ${OUT}/img
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
