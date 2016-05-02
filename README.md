ChrUbuntu Scripts
=================

*** WARNING ***
The following scripts are intented for use of expirienced users.
Running those scripts might result in data loss, be warned!
***************

This is a collection of scripts related to installation of Linux on Chromebooks, specifically on Acer C710 (parrot).

Normally, users of Acer C7xx chromebook are able to flash customized firmware which provides normal boot suquence.

For those willing to use factory provided firmware, for whatever reason, are welcome here.

There are few possibilites for running Linux (not crouton etc) on those Chromebooks without altering firmware:

1. Use original kernel with userspace from distro.
   This was the approach during Ubuntu 12.04 -> 13.10.
2. Use original kernel with kexec enabled and switch to userspace from distro during early stages of boot.
   This was the approach during 14.04 -> 14.10
3. Use original kernel while adding systemd related features and switch to userspace from distro during early stages of boot.
   This was the approach during development stage of 16.04.
4. Use "stock" kernel with customized config and switch to userspace from distro during early stages of boot.
   This should work with virtualy any release/distro but wasn't tesed.
5. Use "stock" kernel with customized config and use custom boot loader, petit-boot, kexec-loader and plopkexec found to be working.

***
As of today (20160502), options 5 from above is available and it is the recommended options.
It allows almost normal use of your Chromebook.
***

Quick start:
============
Here is the most simple procedure:
1. Backup all data on your Chromebook!
2. Connect your Chromebook's harddrive to Ubuntu machine.
   For example using SATA or USB interface.
3. Carefully check which device name was designated to your harddrive.
   For example use "Gnome Disks" utility.
4. Fetch this project to your machine using Git or zip/tarball from GitHub.
5. Modify "target_disk" in chrubuntu-format4linux.sh
6. run ./chrubuntu-format4linux.sh and follow the instractions.
7. Install your harddrive back to Chromebook
8. Once power-on your Chromebook will show bootloader screen and wait for any "bootable" media.
9. You may use regular xbuntu CD/USB to install your system.

***
 Do not repartition your harddrive in any way during installtion process.
 If you with to use different disk layout, modify chrubuntu-format4linux.sh and re-format your harddrive.
***

Project contents
================

Scripts:
 - chromeos-recovery.sh                   : Download, unpack etc chromeos recovery images
 - chrubuntu-build-linux.sh               : Fetch, Build and pack ChromeOS kernels
 - chrubuntu-format4linux.sh              : Repartitiona, format and install prebuilt bootloader on Chromebook harddrive
 - chrubuntu-install.sh                   : Install freshly bootstrapped Ubuntu onto Chromebook harddrive (old and unmaintained)
 - chrubuntu-move.sh / chrubuntu-clone.sh : Two variants of script that transfers current system onto Chromebook harddrive
 - chrubuntu-pack-linux.sh                : Packs Kernel to be used as ChromOS kernel partition
 - chrubuntu-repack-linux.sh              : RePacks ChromeOS kernel partition with required modifications

Code: 
 - plopkexec                              : Modified versions of plopkexec[https://www.plop.at/en/plopkexec.html] bootloader with everything you would need to install andrun recent distributions.

Images: (Binaries are available only for active releases older ones might be in Git history)
 - stock-4.4.8-plopkexec                  : Images of mainline Linux 4.4.8 with built-in plopkexec boot loader
 - parrot-R39                             : Reference images and config of corresponding ChromeOS release
 - parrot-R48                             : Reference images and config of corresponding ChromeOS release

Archives:
 Archived versions of scripts

Configs:
 Archived configuration files store for reference

Notes:
======
* You will need to install the following on your system prior to running any script; cgpt, vbutil, parted, rsync, cryptsetup

References:
===========
Chromebook recovery:
https://support.google.com/chromebook/answer/6002417

Linux:
https://dl.google.com/dl/edgedl/chromeos/recovery/linux_recovery.sh

Recovery script:
https://dl.google.com/dl/edgedl/chromeos/recovery/recovery.conf?source=linux_recovery.sh

Obtain the current kernel config:
modprobe configs; zcat /proc/config.gz

Releases:
https://cros-omahaproxy.appspot.com/

Recovery images:
R40 - https://dl.google.com/dl/edgedl/chromeos/recovery/chromeos_6457.107.0_parrot_recovery_stable-channel_mp-v3.bin.zip
R41 - https://dl.google.com/dl/edgedl/chromeos/recovery/chromeos_6680.58.0_parrot_recovery_stable-channel_mp-v3.bin.zip
R48 - https://dl.google.com/dl/edgedl/chromeos/recovery/chromeos_7647.84.0_parrot_recovery_stable-channel_mp-v3.bin.zip
