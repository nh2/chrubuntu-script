#!/bin/bash

set -x

#
# Grab verified boot utilities from ChromeOS.
#
aptitude install vboot-kernel-utils vboot-utils cgpt

#
# Fetch ChromeOS kernel sources from the Git repo.
#
aptitude install git
git clone -b chromeos-3.10 https://chromium.googlesource.com/chromiumos/third_party/kernel-next
cd kernel-next

#
# Configure the kernel
#
# First we patch ``base.config`` to set ``CONFIG_SECURITY_CHROMIUMOS``
# to ``n`` ...
sed -i 's/CONFIG_SECURITY_CHROMIUMOS=y/CONFIG_SECURITY_CHROMIUMOS=n/' ./chromeos/config/base.config
./chromeos/scripts/prepareconfig chromeos-intel-pineview

#
# ... and then we proceed as per Olaf's instructions
#
yes "" | make oldconfig

#
# Build the Ubuntu kernel packages
#
aptitude install kernel-package
make-kpkg kernel_image kernel_headers

#
# Extract old kernel config
#
vbutil_kernel --verify ..//dev/sda6 --verbose | tail -1 > /config-$tstamp-orig.txt
#
# Add ``disablevmx=off`` to the command line, so that VMX is enabled (for VirtualBox & Co)
#
sed -e 's/$/ disablevmx=off/' \
  /config-$tstamp-orig.txt > /config-$tstamp.txt
 
#
# Wrap the new kernel with the verified block and with the new config.
#
vbutil_kernel --pack /newkernel \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --version 1 \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --config=/config-$tstamp.txt \
  --vmlinuz /boot/vmlinuz-3.8.0 \
  --arch x86_64
 
#
# Make sure the new kernel verifies OK.
#
vbutil_kernel --verify /newkernel
 
#
# Copy the new kernel to the KERN-C partition.
#
dd if=/newkernel of=/dev/sda6