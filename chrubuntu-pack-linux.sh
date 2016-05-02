#!/bin/bash -xe

# Generic settings
arch="`uname -m`"
release="stock-4.4.8-plopkexec"
kernel="$(dirname ${0})/images/${release}"
working_dir="."

# Unpack kernel
[ -r "${kernel}" ] || xzcat "${kernel}.xz" > "${kernel}"

# Make dummy bootloader stub
[ -r "${kernel}.bootstub.efi" ] || echo "dummy" > ${kernel}.bootstub.efi

# Make comdline
[ -r "${kernel}.cmdline" ] || echo "dummy" > ${kernel}.cmdline

# Pack kernel in ChromeOS format
[ -r "${kernel}.ck" ] || ./futility vbutil_kernel --pack ${kernel}.ck \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config ${kernel}.cmdline \
	--bootloader ${kernel}.bootstub.efi \
	--vmlinuz ${kernel} \
	--arch x86 \
	--version 1

# Make sure the new kernel verifies OK.
vbutil_kernel --verbose --verify ${kernel}.ck
