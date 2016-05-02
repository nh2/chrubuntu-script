#!/bin/sh

sudo debootstrap --variant=minbase --components main,universe,multiverse --include=petitboot,mc,rsync,ssh,cgpt,vboot-utils,vboot-kernel-utils xenial bootfs
sudo tar -C bootfs --exclude=var/cache/apt/archives --exclude=var/lib/apt/lists/*Packages -cJf bootfs.tar.xz .

#/media/cache/chrubuntu/src/chroboot/lib/systemd/system/getty@.service
