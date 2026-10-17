#!/bin/sh
# Rebuilds images/inkterminal-bzImage.bin (Linux 6.6 i386 + BusyBox initramfs).
# Needs a Linux PC (or a CI runner) with: gcc gcc-multilib make flex bison bc cpio libelf-dev git.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
mkdir -p "$WORK" && cd "$WORK"
[ -d linux ] || git clone --depth 1 --branch v6.6 https://github.com/torvalds/linux linux
[ -d busybox ] || git clone https://github.com/mirror/busybox busybox && (cd busybox && git checkout 371fe9f71d445d18be28c82a2a6d82115c8af19d)

# BusyBox: static 32-bit
cd busybox
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/CONFIG_TC=y/# CONFIG_TC is not set/' .config
sed -i 's|CONFIG_EXTRA_CFLAGS=""|CONFIG_EXTRA_CFLAGS="-m32 -march=i686"|; s|CONFIG_EXTRA_LDFLAGS=""|CONFIG_EXTRA_LDFLAGS="-m32"|' .config
yes "" | make oldconfig
make -j"$(nproc)"
cd ..

# Root filesystem
rm -rf rootfs && mkdir -p rootfs/bin rootfs/proc rootfs/sys rootfs/dev rootfs/tmp rootfs/root rootfs/home rootfs/var rootfs/mnt
cp busybox/busybox rootfs/bin/
for p in $(rootfs/bin/busybox --list-full); do
  [ "$p" = bin/busybox ] && continue
  mkdir -p "rootfs/$(dirname "$p")"; ln -sf /bin/busybox "rootfs/$p"
done
cp -r "$HERE/rootfs-overlay/." rootfs/
chmod +x rootfs/init

# Kernel
cd linux
make ARCH=i386 tinyconfig
sed "s|@ROOTFS@|$WORK/rootfs|; s|@LIST@|$HERE/initramfs.list|" "$HERE/kernel-extra.config" >> .config
make ARCH=i386 olddefconfig
make ARCH=i386 -j"$(nproc)" bzImage
cp arch/x86/boot/bzImage "$HERE/../images/inkterminal-bzImage.bin"
echo "OK: images/inkterminal-bzImage.bin"
