#!/bin/bash

# http://velvet-underscore.blogspot.co.il/2013/01/chrubuntu-virtualbox-with-kvm.html

#
# Extract old kernel config
#
#vbutil_kernel --verify /dev/sda6 --verbose | tail -1 > /config-$tstamp-orig.txt

#
# Add ``disablevmx=off`` to the command line, so that VMX is enabled (for VirtualBox & Co)
#
#sed -e 's/$/ disablevmx=off/' /config-$tstamp-orig.txt > /config-$tstamp.txt

#
# Define kernel coommand line
#
#vbutil_kernel --verify /dev/sda6 --verbose | tail -1 > /config-$tstamp-orig.txt
echo "console=tty1 loglevel=7 init=/sbin/init oops=panic panic=-1 root=${target_root} rootwait rw noinitrd kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic" > .cmdline
 
#
# Wrap the new kernel with the verified block and with the new config.
#
vbutil_kernel --pack ${1}.ck \
--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
--version 1 \
--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
--config=.cmdline \
--vmlinuz ${1} \
--arch x86_64
 
#
# Make sure the new kernel verifies OK.
#
vbutil_kernel --verify ${1}.ck
