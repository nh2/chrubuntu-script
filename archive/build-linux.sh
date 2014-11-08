#!/bin/bash

version="$(make kernelrelease)"

echo "Building [${version}]"
make -j32 bzImage modules

echo "Packing [$version}]"
[ ! -d install.old ] || rm -Rvf install.old
[ ! -d install ] || mv -vf install install.old
make INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=install INSTALL_HDR_PATH=install/usr modules_install firmware_install headers_install
rm -vf install/lib/modules/${version}/{source,build}
ln -svf ../../../usr/include install/lib/modules/${version}/build
tar -cJ -C install --exclude=.install --exclude=..install.cmd -f linux-${version}-lib.tar.xz .
cp -vf arch/x86/boot/bzImage linux-${version}-vmlinuz
