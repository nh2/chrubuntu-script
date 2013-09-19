#!/bin/bash
#
# Script to install Ubuntu on Chromebooks
#
# Copyright 2012-2013 Jay Lee
#
# here would be nice to have some license - BSD one maybe
#

# Allow debugging
if [ -n $DEBUG ]; then
	DEBUG_WRAP="echo"
	DEBUG_CMD="set -x"
	set -x
	exec 2>&1
else
	set -e
fi

# User related defaults
user_name="user"
auto_login="[ -f /usr/lib/lightdm/lightdm-set-defaults ] && /usr/lib/lightdm/lightdm-set-defaults --autologin user"

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"

# Target specifications
target_mnt="/tmp/urfs"
chromebook_arch="`uname -m`"
ubuntu_metapackage="default"
ubuntu_latest=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release | grep "^Version: " | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
ubuntu_version=$ubuntu_latest
base_pkgs="ubuntu-minimal locales tzdata dialog wget"
ppas=""

setterm -blank 0

# Basic sanity checks

# Make sure that we have root permissions
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

# Make sure we run as bash
if [ ! $BASH_VERSION ]; then
	echo "This script must be run in bash"
	exit 1
fi

# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]; then
	echo -e "You're Chromebook is not running a developer BIOS!\n"
	echo -e "You need to run:\n"
	echo -e "\tsudo chromeos-firmwareupdate --mode=todev\n"
	echo -e "and then re-run this script."
	exit
fi

# Gather options from command line and set flags
while getopts aem:np:P:rt:u:v: opt; do
	case "$opt" in
		a)	always="yes"				;;
		e)	encrypt_home="--encrypt-home"
			base_pkgs="$base_pkgs ecryptfs-utils"	;;
		m)	ubuntu_metapackage=${OPTARG}		;;
		n)	unset auto_login			;;
		p)	pkgs="$pkgs ${OPTARG}"			;;
		P)	ppas="$ppas ${OPTARG}"			;;
		r)	repart="yes"				;;
		t)	target_disk=${OPTARG}			;;
		u)	user_name=${OPTARG}			;;
		v)	ubuntu_version=${OPTARG}		;;
		*)	cat <<EOB
Usage: [DEBUG=yes] sudo $0 [-m <ubuntu_metapackage>] [-n ] [-p <ppa:user/repo>] [-u <user>] [-r] [-t <disk>] [-v <ubuntu_version>]
	-a : Always boot into ubuntu
	-e : Enable user home folder encryption
	-m : Ubuntu meta package (Desktop environment)
	-n : Disable user auto logon
	-p : Specify additional packages, might be called multiple times (space separated)
	-P : Specify additional PPAs, might be called multiple times (space separated)
	-r : Repartition disk
	-t : Specify target disk
	-u : Specify user name
	-v : Specify ubuntu version (lts/latest/dev)
Example: $0  -a -e -m "ubuntu-standard" -n -p "mc htop" -P "ppa:eugenesan/ppa, ppa:nilarimogard/webupd8" -r -t "/dev/sdc" -u "user" -v "lts".
EOB
			exit 1					;;
	esac
done

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]; then
	echo -e "Stopping powerd to keep display from timing out..."
	initctl stop powerd
fi

# Partitioning
if [ -n "$target_disk" ]; then
	echo -e "Got ${target_disk} as target drive\n"
	echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
	read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

	ext_size="`blockdev --getsz ${target_disk}`"
	aroot_size=$((ext_size - 65600 - 33))
	parted --script ${target_disk} "mktable gpt"
	cgpt create ${target_disk} 
	cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
	cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
	sync
	blockdev --rereadpt ${target_disk}
	partprobe ${target_disk}
	crossystem dev_boot_usb=1
else
	# Get default root device
	target_disk="`rootdev -d -s`"
	echo -e "Using ${target_disk} as target drive\n"

	# If KERN-C and ROOT-C are one, we partition, otherwise assume they're what they need to be...
	if [ "$ckern_size" =  "1" -o "$croot_size" = "1" -o "$repart" = "yes" ]; then
		echo -e "WARNING! All data on this device will be wiped out! Continue at your own risk!\n"
		read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

		# Read all required partitions parameters (ROOT-C and KERN-C starts are for optional restore later)
		ckern_start="`cgpt show -i 6 -n -b -q ${target_disk}`"
		ckern_size="`cgpt show -i 6 -n -s -q ${target_disk}`"
		croot_start="`cgpt show -i 7 -n -b -q ${target_disk}`"
		croot_size="`cgpt show -i 7 -n -s -q ${target_disk}`"
		state_size="`cgpt show -i 1 -n -s -q ${target_disk}`"
		state_start="`cgpt show -i 1 -n -b -q ${target_disk}`"
		broot_start="`cgpt show -i 5 -n -b -q ${target_disk}`"

		# Do partitioning (if we haven't already)
		max_ubuntu_size=$((($broot_start-$state_start)/1024/1024/2))

		# Try reverse order if calculations goes wrong.
		# Observed on recent Parrot machines with 320GB HDD
		if [ $max_ubuntu_size -lt 0 ]; then
			echo -e "WARNING! Looks like your system has weird partitions layout!"
			echo -e "ROOT-A/ROOT-B/STATEFUL resides in reverse order."
			echo -e "Continue at your own risk!"
			read -p "Press [Enter] to continue or CTRL+C to quit"
			max_ubuntu_size=$(($state_size/1024/1024/2))
			stateful_size=$state_size
		else
			stateful_size=$(($broot_start-$state_start))
		fi

		rec_ubuntu_size=$(($max_ubuntu_size - 1))

		while :; do
			echo -e "\nEnter the size in gigabytes you want to reserve for Ubuntu."
			echo -e "(Acceptable range is 5 to $max_ubuntu_size, but $rec_ubuntu_size is the recommended maximum)"
			read -p "Ubuntu Size: " ubuntu_size

			if [ ! $ubuntu_size -ne -1 2 > /dev/null ]; then
				echo -e "\n\nNumbers only please...\n\n"
				continue
			fi

			if [ $ubuntu_size -lt 0 -o $ubuntu_size -gt $max_ubuntu_size ]; then
				echo -e "\n\nThat number is out of range. Enter a number 5 through $max_ubuntu_size\n\n"
				continue
			fi

			break
		done

		# We've got our size in GB for ROOT-C so do the math...
		if [ "$ubuntu_size" = "0" ]; then
			# If zero size specified we revert to original layout
			# TODO: Store ckern_start and croot_start somewhere on device and use them for reconstruction
			rootc_size=1
			kernc_size=1
		else
			# Calculate sector size for rootc
			rootc_size=$(($ubuntu_size*1024*1024*2))

			# Pin kernc always at 16mb
			kernc_size=32768
		fi

		# New stateful start is the same as original one
		stateful_start=$state_start

		# New stateful size with rootc and kernc subtracted from original
		stateful_size=$((stateful_size - $rootc_size - $kernc_size))

		# Start kernc at stateful start plus stateful size
		kernc_start=$(($state_start + $stateful_size))

		# Start rootc at kernc start plus kernc size
		rootc_start=$(($kernc_start + $kernc_size))

		# Do the real work

		echo -e "\n\nModifying partition table to make room for Ubuntu."
		echo -e "Your Chromebook will reboot, wipe your data and then"
		echo -e "you should re-run this script..."
		read -p "Press [Enter] to continue or CTRL+C to quit"
		$DEBUG_WRAP umount -f /mnt/stateful_partition

		if [ "$repart" = "yes" ]; then
			# Kill old parts
			$DEBUG_WRAP cgpt add -i 1 -t unused ${target_disk}
			$DEBUG_WRAP cgpt add -i 6 -t unused ${target_disk}
			$DEBUG_WRAP cgpt add -i 7 -t unused ${target_disk}
		fi

		# Make stateful first
		$DEBUG_WRAP cgpt add -i 1 -b $stateful_start -s $stateful_size -t data -l STATE ${target_disk}

		# Now kernc
		$DEBUG_WRAP cgpt add -i 6 -b $kernc_start -s $kernc_size -t kernel -l KERN-C ${target_disk}

		# Finally rootc
		$DEBUG_WRAP cgpt add -i 7 -b $rootc_start -s $rootc_size -t rootfs -l ROOT-C ${target_disk}

		echo -e "Finished partitioning. Reboot is required to continue installation."
		echo -e "After reboot re-run the installation."
		read -p "Press [Enter] to reboot or CTRL+C to quit"

		reboot
		exit
	fi
fi

# Ubuntu architecture
if [ "$chromebook_arch" = "x86_64" ]; then
	ubuntu_arch="amd64"
	[ "$ubuntu_metapackage" = "default" ] && ubuntu_metapackage="ubuntu-desktop"
elif [ "$chromebook_arch" = "i686" ]; then
	ubuntu_arch="i386"
	[ "$ubuntu_metapackage" = "default" ] && ubuntu_metapackage="ubuntu-desktop"
elif [ "$chromebook_arch" = "armv7l" ]; then
	ubuntu_arch="armhf"
	[ "$ubuntu_metapackage" = "default" ] && ubuntu_metapackage="xubuntu-desktop"
else
	echo -e "Error: This script doesn't know how to install ChrUbuntu on $chromebook_arch"
	exit
fi

# Ubuntu versioning
if [ "$ubuntu_version" = "lts" ]; then
	ubuntu_version=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release | grep "^Version:" | grep "LTS" | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
elif [ "$ubuntu_version" = "latest" ]; then
	ubuntu_version=$ubuntu_latest
fi

if [ "$ubuntu_version" = "dev" ]; then
	ubuntu_codename=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release-development | grep "^Dist: " | tail -1 | sed -r 's/^Dist: (.*)$/\1/'`
	ubuntu_version=`wget --quiet -O - http://changelogs.ubuntu.com/meta-release-development | grep "^Version:" | tail -1 | sed -r 's/^Version: ([^ ]+)( LTS)?$/\1/'`
	tar_file="http://cdimage.ubuntu.com/ubuntu-core/daily/current/$ubuntu_codename-core-$ubuntu_arch.tar.gz"
else
	tar_file="http://cdimage.ubuntu.com/ubuntu-core/releases/$ubuntu_version/release/ubuntu-core-$ubuntu_version-core-$ubuntu_arch.tar.gz"
fi

# Convert $ubuntu_version from 12.04.3 to 1204
ubuntu_version=`echo $ubuntu_version | cut -f1,2 -d. | sed -e 's/\.//g'`

# ChrUbuntu partitions configuration
if [[ "${target_disk}" =~ "mmcblk" ]]; then
	target_rootfs="${target_disk}p7"
	target_kern="${target_disk}p6"
else
	target_rootfs="${target_disk}7"
	target_kern="${target_disk}6"
fi

# Print summary
echo -e "\nChrome device model is: $hwid\n"
echo -e "Installing Ubuntu $ubuntu_version with metapackage $ubuntu_metapackage\n"
echo -e "Kernel Arch is: $chromebook_arch  Installing Ubuntu Arch: $ubuntu_arch\n"
echo -e "Target Kernel Partition: $target_kern, Target Root FS: ${target_rootfs}, Target Mount Point: ${target_mnt}\n"
read -p "Press [Enter] to continue..."

# Entering working folder
mkdir -p /mnt/stateful_partition/ubuntu
cd /mnt/stateful_partition/ubuntu

if mount | grep ${target_rootfs}; then
	echo "Found formatted and mounted ${target_rootfs}."
	echo "Continue at your own risk!"
	read -p "Press [Enter] to continue or CTRL+C to quit"
	umount ${target_mnt}/{dev/pts,dev,sys,proc,}
fi

# Creating target filesystem
mkfs.ext4 ${target_rootfs}
mkdir -p $target_mnt
mount -t ext4 ${target_rootfs} $target_mnt

# Fetching and unpacking target template
wget -O - $tar_file | tar xzp -C $target_mnt/

# Preparing target's mounts for chroot
for mnt in dev dev/pts sys proc; do
	mount -o bind /$mnt $target_mnt/$mnt
done

# Inject working network config into target
cp /etc/resolv.conf $target_mnt/etc/
echo chrubuntu > $target_mnt/etc/hostname

# Select coresponding apt repos tool
if [ $ubuntu_version -lt 1210 ]; then
	add_apt_repository_package='python-software-properties'
else
	add_apt_repository_package='software-properties-common'
	base_pkgs="$base_pkgs libnss-myhostname"
fi

# Create and run 1st 2nd stage installation script
echo "$DEBUG_CMD" > $target_mnt/install-ubuntu.sh

echo "
$DEBUG_CMD
apt-get -y update
apt-get -y install aptitude
aptitude -y dist-upgrade
aptitude -y install $base_pkgs $add_apt_repository_package
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
dpkg-reconfigure tzdata
" >> $target_mnt/install-ubuntu.sh
chmod a+x $target_mnt/install-ubuntu.sh
chroot $target_mnt /bin/bash -c /install-ubuntu.sh
rm $target_mnt/install-ubuntu.sh

# Enable all ubuntu components
if [ $ubuntu_version -lt 1210 ]; then
	for component in main universe restricted multiverse partner; do
		sed -i "/^# deb.*$component/ s/^# //" $target_mnt/etc/apt/sources.list
	done
else
	ubuntu_components="main universe restricted multiverse partner"
fi

# Create and run 2nd 2nd-stage installation script
echo "$DEBUG_CMD" > $target_mnt/install-ubuntu.sh

for ppa in $ppas; do
	# Add repositories addition to 2nd stage installation script
	echo "add-apt-repository -y $ubuntu_components $ppa" >> $target_mnt/install-ubuntu.sh
done

if echo "$ubuntu_metapackage" | grep desktop; then
	if [ ! $ubuntu_arch = 'armhf' ] ; then
		echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> $target_mnt/etc/apt/sources.list.d/google-chrome.list
		pkgs="$pkgs google-chrome-stable"
	else
		pkgs="$pkgs chromium-browser"
	fi
fi

echo "
aptitude -y update
aptitude -y dist-upgrade
aptitude -y --allow-untrusted install $pkgs $ubuntu_metapackage
" >> $target_mnt/install-ubuntu.sh
chmod a+x $target_mnt/install-ubuntu.sh
chroot $target_mnt /bin/bash -c /install-ubuntu.sh
rm $target_mnt/install-ubuntu.sh

# Keep CrOS partitions from showing/mounting in Ubuntu
udev_target=${target_disk:5}
echo "KERNEL==\"$udev_target1\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"$udev_target3\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"$udev_target5\" ENV{UDISKS_IGNORE}=\"1\"
KERNEL==\"$udev_target8\" ENV{UDISKS_IGNORE}=\"1\"
" > $target_mnt/etc/udev/rules.d/99-hide-disks.rules

# Create and run 3rd 2nd-stage installation script
echo "$DEBUG_CMD" > $target_mnt/install-ubuntu.sh
if [ $ubuntu_version -lt 1304 ]; then
	# pre-raring

	# Inject cgpt tool into target
	if [ -f /usr/bin/old_bins/cgpt ]; then
		cp -p /usr/bin/old_bins/cgpt $target_mnt/usr/bin/
	else
		cp -p /usr/bin/cgpt $target_mnt/usr/bin/
	fi
else
	# post-raring

	# Inject cgpt and vboot tools into target
	echo "aptitude -y install cgpt vboot-kernel-utils" >> $target_mnt/install-ubuntu.sh

	if [ $ubuntu_arch = "armhf" ]; then
		cat > $target_mnt/usr/share/X11/xorg.conf.d/exynos5.conf <<EOZ
Section "Device"
        Identifier      "Mali FBDEV"
        Driver          "armsoc"
        Option          "fbdev"                 "/dev/fb0"
        Option          "Fimg2DExa"             "false"
        Option          "DRI2"                  "true"
        Option          "DRI2_PAGE_FLIP"        "false"
        Option          "DRI2_WAIT_VSYNC"       "true"
#       Option          "Fimg2DExaSolid"        "false"
#       Option          "Fimg2DExaCopy"         "false"
#       Option          "Fimg2DExaComposite"    "false"
        Option          "SWcursorLCD"           "false"
EndSection
Section "Screen"
        Identifier      "DefaultScreen"
        Device          "Mali FBDEV"
        DefaultDepth    24
EndSection
EOZ
                cat > $target_mnt/usr/share/X11/xorg.conf.d/touchpad.conf <<EOZ
Section "InputClass"
        Identifier "touchpad"
        MatchIsTouchpad "on"
        Option "FingerHigh" "5"
        Option "FingerLow" "5"
EndSection
EOZ
		echo "aptitude -y --without-recommends install linux-image-chromebook xserver-xorg-video-armsoc" >> $target_mnt/install-ubuntu.sh

		# Valid for raring, so far also for saucy but will change
		kernel=$target_mnt/boot/vmlinuz-3.4.0-5-chromebook
	fi

	chmod a+x $target_mnt/install-ubuntu.sh
	chroot $target_mnt /bin/bash -c /install-ubuntu.sh
	rm $target_mnt/install-ubuntu.sh
fi

# Treat user creation on live system due to missing ecryptfs support in ChromeOS kernel
mv $target_mnt/etc/rc.local $target_mnt/etc/rc.local.orig
echo"
echo -e \"$user_name\\n$user_name\\n\" | adduser $user_name $encrypt_home --gecos "$user_name,,,"
adduser $user_name adm
adduser $user_name sudo
$auto_login
mv /etc/rc.local.orig /etc/rc.local
" > $target_mnt/etc/rc.local
chmod +x $target_mnt/etc/rc.local

# We do not have kernel for x86 chromebooks in archive at all
# and ARM one only in 13.04 and later
if [ $ubuntu_arch != "armhf" -o $ubuntu_version -lt 1304 ]; then
	KERN_VER=`uname -r`
	mkdir -p $target_mnt/lib/modules/$KERN_VER/
	cp -ar /lib/modules/$KERN_VER/* $target_mnt/lib/modules/$KERN_VER/
	[ ! -d $target_mnt/lib/firmware/ ] && mkdir $target_mnt/lib/firmware/
	cp -ar /lib/firmware/* $target_mnt/lib/firmware/
	kernel=/boot/vmlinuz-`uname -r`
fi

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > kernel-config

if [ $ubuntu_arch = "armhf" ]; then
	vbutil_arch="arm"
else
	vbutil_arch="x86"
fi

vbutil_kernel --pack newkern \
	--keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--version 1 \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
	--config kernel-config \
	--vmlinuz $kernel \
	--arch $vbutil_arch

dd if=newkern of=${target_kern} bs=4M

umount ${target_mnt}/{dev/pts,dev,sys,proc,}

echo -e "Installation seems to be complete.\n"
echo -e "The ChrUbuntu login is:"
echo -e "\tUsername: $user_name"
echo -e "\tPassword: $user_name\n"

if [ "$always" = "yes" ]; then
	echo "Setting Ubuntu kernel partition as top priority for all following boots."
	cgpt add -i 6 -P 5 -S 1 ${target_disk}
	echo -e "If ChrUbuntu fails when you reboot, you will have to perform full ChromeOS recovery "
	echo -e "After thay you may retry ChrUbuntu install."
	echo -e "If you're unhappy with ChrUbuntu when you reboot be sure to run:"
	echo -e "\tsudo cgpt add -i 2 -P 5 -S 1 ${target_disk}\n"
	echo -e "To make ChromeOS the default boot option.\n"
else
	echo "Setting Ubuntu kernel partition as top priority for next boot only."
	cgpt add -i 6 -P 5 -T 1 ${target_disk}
	echo -e "If ChrUbuntu fails when you reboot, power off your Chrome OS device."
	echo -e "When turned on, you'll be back in Chrome OS."
	echo -e "If you're happy with ChrUbuntu when you reboot be sure to run:"
	echo -e "\tsudo cgpt add -i 6 -P 5 -S 1 ${target_disk}\n"
	echo -e "To make ChruBuntu the default boot option.\n"
fi

read -p "We're now ready to start ChrUbuntu, Press [Enter] to reboot..."

reboot
