#!/bin/bash

# https://gist.github.com/Computertechgurus/5565382
# http://superuser.com/questions/583269/chrubuntu-acer-how-to-load-kernel-3-8-0-16-instead-3-4-0
# http://velvet-underscore.blogspot.co.il/2013/01/chrubuntu-virtualbox-with-kvm.html
# https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1156306
# https://launchpadlibrarian.net/140249252/bug%231156306.patch
# cd /lib/firmware/ar3k
# wget https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1024884/+attachment/3244421/+files/{AthrBT_0x11020000,ramps_0x11020000_40}.dfu

set -x

#
# Install verified boot utilities for Chromebook Boot Loader.
#
sudo aptitude install cgpt vboot-kernel-utils vboot-utils

#
# Fetch ChromeOS kernel sources from the Git repo.
#
apt-get install git-core
cd /usr/src
git clone  https://git.chromium.org/git/chromiumos/third_party/kernel-next.git
cd kernel-next
git checkout origin/chromeos-3.8

#
# Configure the kernel
#
# First we patch ``base.config`` to set ``CONFIG_SECURITY_CHROMIUMOS``
# to ``n`` ...
cp ./chromeos/config/base.config ./chromeos/config/base.config.orig
sed -e \
  's/CONFIG_SECURITY_CHROMIUMOS=y/CONFIG_SECURITY_CHROMIUMOS=n/' \
  ./chromeos/config/base.config.orig > ./chromeos/config/base.config
./chromeos/scripts/prepareconfig chromeos-intel-pineview
#
# ... and then we proceed as per Olaf's instructions
#
yes "" | make oldconfig

#
# Build the Ubuntu kernel packages
#
apt-get install kernel-package
make-kpkg kernel_image kernel_headers

#
# Backup current kernel image, modules and firmwares
#
dd if=/dev/sda6 of=/kernel.old
tar -cJhf /kernel.old.tar.xz /lib/firmware/* /lib/modules/`uname -r`

#
# Install kernel image and modules from the Ubuntu kernel packages we
# just created.
#
#dpkg -i /usr/src/linux-*.deb

#
# Extract old kernel config
#
vbutil_kernel --verify /dev/sda6 --verbose | tail -1 > /config.old

#
# Add ``disablevmx=off`` to the command line, so that VMX is enabled (for VirtualBox & Co)
#
sed -e 's/$/ disablevmx=off/' /config.old > /config.new

#
# Wrap the new kernel with the verified block and with the new config.
#
vbutil_kernel --pack /kernel.new \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --version 1 \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --config=/config.new \
  --vmlinuz /boot/vmlinuz-3.8.0 \
  --arch x86_64

#
# Make sure the new kernel verifies OK.
#
vbutil_kernel --verify /kernel.new

#
# Copy the new kernel to the KERN-C partition.
#
dd if=/dev/sda6 of=/kernel.old

#
# Copy the new kernel to the KERN-C partition.
#
#dd if=/kernel.new of=/dev/sda6
