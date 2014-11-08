#!/bin/bash -xe
#
# Script to build kexec kernel for Chromebook Acer C710
#
# Version 0.2
#
# (c) 2014 Eugene San
#
# Here would be nice to have some license - BSD one maybe
#
# Depends on following packages: git kernel-package vboot-kernel-utils
#

# Allow debugging
if [ -n "$DEBUG" ]; then
	echo "Enabling debug mode"
	DEBUG_WRAP="echo"
	DEBUG_CMD="set -x"
	set -x
	exec 2>&1
else
	set -e
fi

# Generic settings
chromebook_arch="`uname -m`"
branch="release-R39-6310.B-chromeos-3.4"
release="parrot-c710-R39"
kernel="$(dirname ${0})/images/${release}"
kernel_build="/tmp/${release}.build"

setterm -blank 0

# Basic sanity checks

# Make sure we run as bash
if [ ! $BASH_VERSION ]; then
	echo "This script must be run in bash"
	exit 1
fi

# Gather options from command line and set flags
while getopts b:cfk:p opt; do
	case "$opt" in
		b)	branch=${OPTARG}	;;
		c)	compile="yes"		;;
		f)	force="yes"		;;
		k)	kernel="${OPTARG}"	;;
		p)	pack="yes"		;;
		*)	cat <<EOB
Usage: [DEBUG=yes] sudo $0 [-a] [-t <disk>]
	-f          : Force fresh kernel tree creation
	-b <branch> : Use specific remote branch
Example: $0 -f
EOB
			exit 1			;;
	esac
done

if [ ! -r "${kernel}" ] && [ -z "${compile}" ]; then
	echo "Invalid parameters specified"
	exit 255
fi

if [ "${compile}" == "yes" ]; then
	[ -z "${branch}" ] && echo "Invalid branch specified" && exit 255

	# Checkout kernel
	[ "${force}" == "yes" ] && mv -f "${kernel_build}" "${kernel_build}.old"
	[ -d "${kernel_build}" ] || git clone --depth=1 -b ${branch} https://chromium.googlesource.com/chromiumos/third_party/kernel.git "${kernel_build}"

	# Enter kernel tree
	pushd "${kernel_build}"

	# Fix kernel build on fresh distros
	sed -i 's/fstack-protector-strong/fstack-protector/' arch/x86/Makefile
	sed -i 's/Wall/fno-tree-vrp/' Makefile

	# Get default CromeOS kernel config
	./chromeos/scripts/prepareconfig chromeos-intel-pineview

	# Disabled modules
	sed -i 's/\=m/\=n/' .config

	# Enable KEXEC
	echo "CONFIG_KEXEC=y" >> .config

	# Disabled ChromeOS security checks
	echo "CONFIG_SECURITY_CHROMIUMOS=n" >> .config

	# Update kernel config
	yes "" | make oldconfig

	# Build kernel
	make -j32 bzImage

	# Return to script's home
	popd

	# Export kernel image
	xz -9 -c "${kernel_build}/arch/x86/boot/bzImage" > "${kernel}.xz"
	cp "${kernel_build}/.config" "${kernel}.config"
fi

if [ "${pack}" == "yes" ]; then
	# Prepare kernel comdline
	echo "console=tty1 debug verbose root=/dev/sda7 rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic disablevmx=off" > ${kernel}.cmdline

	xz -d -c "${kernel}.xz" > "${kernel}"
	vbutil_kernel --pack ${kernel}.ck \
		--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
		--version 1 \
		--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
		--config=${kernel}.cmdline \
		--vmlinuz ${kernel} \
		--arch x86_64
	#
	# Make sure the new kernel verifies OK.
	#
	vbutil_kernel --verify ${kernel}.ck
fi

if [ -r "${kernel}.ck" ]; then
	echo -e "Linux kernel seems to be complete.\n"
else
	echo -e "Linux kernel seems to be missing.\n"
fi
