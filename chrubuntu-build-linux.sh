#!/bin/bash -xe
#
# Script to build kexec kernel for Chromebook Acer C710
#
# Version 0.5
#
# (c) 2014-2016 Eugene San
#
# Here would be nice to have some license - BSD one maybe
#
# Depends on following packages: git kernel-package vboot-kernel-utils
#
# https://gist.github.com/carletes/4674386

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
# https://chromium.googlesource.com/chromiumos/third_party/kernel.git/+refs
chromebook_arch="`uname -m`"
#branch="release-R39-6310.B-chromeos-3.4"
#branch="release-R39-6310.B-chromeos-3.4"
#branch="release-R46-7390.B-chromeos-3.4"
#branch="release-R48-7647.B-chromeos-3.8"
branch="release-R50-7978.B-chromeos-3.8"
release="parrot-R50"
kernel="$(dirname ${0})/images/${release}"
working_dir="."

setterm -blank 0

# Basic sanity checks

# Make sure we run as bash
if [ ! $BASH_VERSION ]; then
	echo "This script must be run in bash"
	exit 1
fi

# Gather options from command line and set flags
while getopts b:cfk:pd:to opt; do
	case "$opt" in
		b)	branch=${OPTARG}	;;
		c)	compile="yes"		;;
		f)	force="yes"		;;
		o)	orig_cmdline="yes"	;;
		k)	kernel="${OPTARG}"	;;
		p)	pack="yes"		;;
		t)	no_tweak="yes"		;;
		d)	working_dir="${OPTARG}"	;;
		*)	cat <<EOB
Usage: [DEBUG=yes] sudo $0 [-a] [-t <disk>]
	-b <branch> : Use specific remote branch
	-c          : Compile fresh kernel image
	-f          : Force fresh kernel tree creation/re-creation
	-o          : Use orig cmdline
	-k          : Specify pre-built kernel image
	-p          : Pack (wrap) kernel for ChromeBook firmware
	-d          : Specify working directory
	-t          : Skip kernel config tweaking
Example: $0 -c -p -w .
EOB
			exit 1			;;
	esac
done

#
kernel_build="${working_dir}/${release}.build"

if [ ! -r "${kernel}.xz" ] && [ -z "${compile}" ]; then
	echo "Invalid parameters specified"
	exit 255
fi

if [ "${compile}" == "yes" ]; then
	[ -z "${branch}" ] && echo "Invalid branch specified" && exit 255

	# Checkout kernel
	[ "${force}" == "yes" ] && mv -f "${kernel_build}" "${kernel_build}.old"
	[ -d "${kernel_build}" ] || git clone --depth=1 -b ${branch} https://chromium.googlesource.com/chromiumos/third_party/kernel.git "${kernel_build}"


	if [ -r "${kernel}.config.orig.gz" ] && [ "${no_tweak}" == "yes" ]; then
		# Use original config
		zcat "${kernel}.config.orig.gz" > ${kernel_build}/.config
	fi

	# Enter kernel tree
	pushd "${kernel_build}"

	if [ ! -r ".config" ]; then
		# Get default CromeOS kernel config
		./chromeos/scripts/prepareconfig chromeos-intel-pineview
	fi

	if [ "${no_tweak}" != "yes" ]; then
		# Build-in modules
		#sed -i 's/\=m/\=y/' .config

		# Disable modules
		#echo "CONFIG_MODULES=n" >> .config

		# Enable KEXEC
		echo "CONFIG_KEXEC=y" >> .config

		# Disabled ChromeOS security checks
		#echo "CONFIG_SECURITY_CHROMIUMOS=n" >> .config

		# Disable forced errors on warningns
		echo "CONFIG_ERROR_ON_WARNING=n" >> .config
	fi

	# Update kernel config
	yes "" | make oldconfig

	# Fix kernel build on fresh distros
	sed -i 's/fstack-protector-strong/fstack-protector/' arch/x86/Makefile
	#sed -i 's/Wall/fno-tree-vrp/' Makefile
	sed -i 's/defined\((@.*)\)/\1/' kernel/timeconst.pl

	# Build kernel
	make CC="ccache gcc-4.8" -j16 bzImage

	# Return to script's home
	popd

	# Export kernel image
	xz -9 -c "${kernel_build}/arch/x86/boot/bzImage" > "${kernel}.xz"
	cp "${kernel_build}/.config" "${kernel}.config"
fi

if [ "${pack}" == "yes" ]; then
	if [ "${orig_cmdline}" == "yes" ] && [ -r "${kernel}.cmdline.orig.gz" ]; then
		# Use original cmdline
		zcat "${kernel}.cmdline.orig.gz" > ${kernel}.cmdline
	else
		# Prepare kernel cmdline
		# R50-3.8
		#console= loglevel=7 init=/sbin/init cros_secure oops=panic panic=-1 root=/dev/dm-1 rootwait ro
		#dm_verity.error_behavior=3 dm_verity.max_bios=-1 dm_verity.dev_wait=1 dm="2 vboot none ro 1,0 2545920 bootcache PARTUUID=%U/PARTNROFF=1 2545920 c391d609f82f5bef9090bb7b552319810ea436bf 512 20000 100000, vroot none ro 1,0 2506752 verity payload=254:0 hashtree=254:0 hashstart=2506752 alg=sha1 root_hexdigest=6d99bf9262f92e30bfea287da5b22b4cbf96e953 salt=574b90772b7635a44a2f0b092491d471f3794b23fb697194a6d711b322d28634"
		#noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1
		#tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3

		#echo "console=tty1 root=/dev/sda3 rw i915.modeset=1 add_efi_memmap noinitrd vt.global_cursor_default=0 noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic disablevmx=off iTCO_vendor_support.vendorsupport=3" > ${kernel}.cmdline
		#echo "console=tty1 loglevel=7 cros_secure oops=panic panic=-1 root=/dev/sda2 rootwait rw noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3" > ${kernel}.cmdline
		#echo "cros_secure console=tty1 earlyprintk=tty1 root=/dev/sda3 rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap disablevmx=off runlevel=1" > ${kernel}.cmdline
		#echo "console=tty1 earlyprintk=tty1 panic=10 root=/dev/sda3 rw i915.modeset=1 add_efi_memmap noinitrd noresume noswap tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic disablevmx=off" > ${kernel}.cmdline

		echo "console=tty1 loglevel=7 oops=panic panic=-1 root=/dev/sda7 rootwait ro noinitrd vt.global_cursor_default=0 kern_guid=%U add_efi_memmap boot=local noresume noswap i915.modeset=1 tpm_tis.force=1 tpm_tis.interrupts=0 nmi_watchdog=panic,lapic iTCO_vendor_support.vendorsupport=3" > ${kernel}.cmdline
	fi

	# Unpack kernel
	xzcat "${kernel}.xz" > "${kernel}"

	# Make dummy bootloader stub
	[ -r "${kernel}.bootstub.efi" ] || echo "dummy" > ${kernel}.bootstub.efi

	# Pack kernel in ChromeOS format
	vbutil_kernel --pack ${kernel}.ck \
		--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
		--version 1 \
		--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
		--config ${kernel}.cmdline \
		--vmlinuz ${kernel} \
		--bootloader ${kernel}.bootstub.efi \
		--arch x86_64

	# Make sure the new kernel verifies OK.
	vbutil_kernel --verbose --verify ${kernel}.ck
fi

if [ -r "${kernel}.ck" ]; then
	echo -e "Linux kernel seems to be complete.\n"
else
	echo -e "Linux kernel seems to be missing or wasn't built.\n"
fi
