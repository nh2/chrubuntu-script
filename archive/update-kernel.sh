kernel_ver=`uname -r`
kernel=/boot/vmlinuz-${kernel_ver}
config=vmlinuz.cfg
vbutil_arch="x86"
url="https://dl.google.com/dl/edgedl/chromeos/recovery/chromeos_4319.96.0_parrot_recovery_stable-channel_mp-v3.bin.zip"

target_mnt="/"
target_disk=`df ${target_mnt} | grep dev | awk '{print $1}'`
target_kern="${target_disk}6"

mkdir -p $target_mnt/lib/modules/$kernel_ver/
cp -ar /lib/modules/$kernel_ver/* $target_mnt/lib/modules/$kernel_ver/
mkdir -p $target_mnt/lib/firmware/
cp -ar /lib/firmware/* $target_mnt/lib/firmware/

vbutil_kernel \
	--pack /tmp/newkern \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--version 1 \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config $config \
	--vmlinuz $kernel \
	--arch $vbutil_arch

dd if=/tmp/newkern of=${target_kern} bs=4M
