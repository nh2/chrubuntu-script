#!/bin/sh -ex

KERNEL="linux-4.4.8"
KEXEC="kexec-tools-2.0.11"
PLOP="plop"
BASE=$(pwd)
BUILD=".build"

mkdir -p $BASE/$BUILD
touch $BASE/$BUILD/.fdb

if [ ! -d $BASE/$BUILD/$KERNEL ]; then
	echo "Fetching and unpacking kernel"
	[ -r $BASE/$BUILD/$KERNEL.tar.xz ] || wget https://cdn.kernel.org/pub/linux/kernel/v4.x/$KERNEL.tar.xz -O $BASE/$BUILD/$KERNEL.tar.xz

	echo "Extracting Linux kernel source code"
	tar -C $BASE/$BUILD -xaf $BASE/$BUILD/$KERNEL.tar.xz
fi

if [ ! -d $BASE/$BUILD/$KEXEC ]; then
	echo "Fetching and unpacking kexec"
	[ -r $BASE/kexec/$KEXEC.tar.xz ] || wget http://horms.net/projects/kexec/kexec-tools/$KEXEC.tar.gz -O $BASE/$BUILD/$KEXEC.tar.xz

	echo "Extracting and patching kexec source code"
	tar -C $BASE/$BUILD -xaf $BASE/$BUILD/$KEXEC.tar.xz
	patch -d $BASE/$BUILD/$KEXEC -p1 < $BASE/kexec/$KEXEC.patch
fi

if [ ! -d $BASE/$BUILD/$PLOP ]; then
	echo "Clonning plop"
	make -C $BASE/$PLOP clean 
	rsync -a $BASE/$PLOP/ $BASE/$BUILD/$PLOP/
fi

if [ ! -r $BASE/$BUILD/kexec ]; then
	echo "Building kexec"
	cd $BASE/$BUILD/$KEXEC
	./configure
	make
	cd -

	cp -v $BASE/$BUILD/$KEXEC/build/sbin/kexec $BASE/$BUILD/
	strip -s $BASE/$BUILD/kexec
fi

if [ ! -r $BASE/$BUILD/init ]; then
	echo "Building plop"
	make -C $BASE/$BUILD/$PLOP
	cp -afv $BASE/$BUILD/$PLOP/init $BASE/$BUILD/
fi

echo "Installing initramfs"
fakeroot -i $BASE/$BUILD/.fdb -s $BASE/$BUILD/.fdb tar -C $BASE/$BUILD/$KERNEL -xaf $BASE/kernel/initramfs.tar.xz

echo "Installing kexec"
cp -afv $BASE/$BUILD/kexec $BASE/$BUILD/$KERNEL/initramfs/

echo "Installing plop"
cp -afv $BASE/$BUILD/$PLOP/init $BASE/$BUILD/$KERNEL/initramfs/

echo "Building kernel"
if [ ! -r $BASE/$BUILD/bzImage ]; then
	cp -afvr $BASE/kernel/.config $BASE/$BUILD/$KERNEL/
	fakeroot -i $BASE/$BUILD/.fdb -s $BASE/$BUILD/.fdb make -C $BASE/$BUILD/$KERNEL CC="ccache gcc" -j16 bzImage
	cp -afv $BASE/$BUILD/$KERNEL/arch/x86/boot/bzImage $BASE/$BUILD/
fi

if [ ! -r $BASE/$BUILD/plopkexec.iso ]; then
	echo "Building ISO"
	mkdir -p $BASE/$BUILD/iso
	cp -av $BASE/$BUILD/bzImage $BASE/$BUILD/iso/
	cp -av $BASE/iso/isolinux.* $BASE/$BUILD/iso/
	cp -av $BASE/COPYING $BASE/LICENSE $BASE/$BUILD/iso/

	cd $BASE/$BUILD/iso
	mkisofs -J -r -input-charset utf-8 -V plopKexec \
		-hide-joliet-trans-tbl -hide-rr-moved \
		-allow-leading-dots -no-emul-boot -boot-load-size 4 \
		-o $BASE/$BUILD/plopkexec.iso \
		-c boot.catalog -b isolinux.bin -boot-info-table -l .
	cd -
fi

echo "Successfully built plopkexec and plopkexec.iso"
echo "Find them in the $BUILD'' directory."
