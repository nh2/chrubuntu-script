#!/bin/sh -xe

target_kern="/dev/sdb6"
target_root="/dev/sda7"
kernel=parrot-c710-move-stock-2014-10.img
config=/tmp/vmlinuz.cfg
newkern=parrot-c710-move-stock-2014-10.cx

# Prepare kernel comdline
echo "console=tty1 debug verbose root=${target_root} rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic" > $config

vbutil_kernel --repack ${newkern} \
        --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
        --version 1 \
        --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
        --config ${config} \
        --oldblob ${kernel}

#
# Make sure the new kernel verifies OK.
#
vbutil_kernel --verify ${1}.ck

dd if=${newkern} of=${target_kern} bs=4M
