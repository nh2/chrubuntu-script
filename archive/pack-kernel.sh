#!/bin/sh

# Prepare kernel comdline
echo "console=tty1 debug verbose root=/dev/sda7 rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic" > .cmdline

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
