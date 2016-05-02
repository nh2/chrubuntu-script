#!/bin/bash

# Generic settings
chromebook_arch="`uname -m`"
branch="release-R48-7647.B-chromeos-3.8"
release="parrot-R48"
kernel="$(dirname ${0})/images/${release}"
kernel_build="${release}.build"
working_dir="."

echo "console=tty1 single panic=10 loglevel=1 root=/dev/sda3 rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic disablevmx=off"

# Pack kernel in ChromeOS format
xzcat "${kernel}.xz" > "${kernel}"
vbutil_kernel --repack ${kernel}.ck \
        --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
        --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
        --config ${kernel}.cmdline \
        --oldblob ${kernel}
#        --bootloader ${kernel}.bootstub.efi \
#        --arch x86_64
#        --version 1 \

# Make sure the new kernel verifies OK.
vbutil_kernel --verbose --verify ${kernel}.ck
