#!/bin/bash
# Builds the FleetOS USB installer image. Run as root on Debian/Ubuntu.
#   sudo ./build.sh [deps|kernel|rootfs|image|all]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/config.env"
STEP="${1:-all}"
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)."; exit 1; }

ROOTFS="$WORK_DIR/rootfs"
mkdir -p "$OUT_DIR" "$WORK_DIR"

deps() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y mmdebstrap qemu-user-static binfmt-support debian-archive-keyring \
    cgpt vboot-utils vboot-kernel-utils u-boot-tools device-tree-compiler e2fsprogs \
    gcc-arm-linux-gnueabihf build-essential bc flex bison libssl-dev libelf-dev \
    dpkg-dev debhelper fakeroot kmod cpio rsync xz-utils curl uuid-runtime
}

kernel() {
  if ls "$OUT_DIR"/kernel/linux-image-*.deb >/dev/null 2>&1; then
    echo "Kernel already built (cache), skipping."
  else
    bash "$HERE/kernel/build-kernel.sh"
  fi
}

rootfs() {
  rm -rf "$ROOTFS"
  local debs; debs=$(ls "$OUT_DIR"/kernel/linux-image-*.deb)
  mmdebstrap --arch=armhf --variant=minbase \
    --components="main contrib non-free non-free-firmware" \
    --include="$(paste -sd, "$HERE/rootfs/packages.txt")" \
    --customize-hook="sync-in '$HERE/rootfs/overlay' /" \
    --customize-hook="copy-in $debs /tmp" \
    --customize-hook="copy-in '$HERE/rootfs/customize.sh' /tmp" \
    --customize-hook='chroot "$1" sh -c "chmod +x /usr/local/sbin/* /usr/local/bin/* /etc/kernel/postinst.d/zz-fleet-kernel"' \
    --customize-hook='chroot "$1" bash /tmp/customize.sh' \
    "$SUITE" "$ROOTFS" "$MIRROR"
}

image() {
  local KVER; KVER=$(basename "$(ls "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -1)"); KVER=${KVER#vmlinuz-}
  local IMG="$OUT_DIR/fleetos-usb-${USB_MODEL}.img"
  local ROOT_MIB=$(( $(du -sm "$ROOTFS" | cut -f1) * 115 / 100 + 300 ))
  local ROOT_SECT=$(( ROOT_MIB * 2048 ))
  local ROOT_START=73728   # 8192 + 2 x 32768 (16 MiB kernel partitions, as on ChromeOS and Kali)
  local TOTAL=$(( ROOT_START + ROOT_SECT + 64 ))
  local ROOTGUID; ROOTGUID=$(uuidgen)

  rm -f "$IMG"; truncate -s $(( TOTAL * 512 )) "$IMG"
  cgpt create "$IMG"
  cgpt boot -p "$IMG"   # protective MBR: Linux ignores GPT disks without it
  cgpt add -i 1 -t kernel -b 8192   -s 32768 -l KERN-A -S 1 -T 0 -P 2 "$IMG"
  cgpt add -i 2 -t kernel -b 40960  -s 32768 -l KERN-B -S 0 -T 0 -P 0 "$IMG"
  cgpt add -i 3 -t data   -b "$ROOT_START" -s "$ROOT_SECT" -l ROOT-A -u "$ROOTGUID" "$IMG"

  echo "PARTUUID=$ROOTGUID / ext4 defaults,noatime 0 1" > "$ROOTFS/etc/fstab"
  # Build the root filesystem as a separate file via a real loop mount (mke2fs -d has bugs with large
  # directories: "checksumming directory block 0" errors seen on the first images), verify it with
  # e2fsck, then write it into the image at the partition offset.
  local RFS="$WORK_DIR/root.ext4"
  rm -f "$RFS"; truncate -s "${ROOT_MIB}M" "$RFS"
  mkfs.ext4 -q -F -L fleetroot "$RFS"
  mkdir -p "$WORK_DIR/mnt"
  if mount -o loop "$RFS" "$WORK_DIR/mnt"; then
    rsync -aHAX --numeric-ids "$ROOTFS"/ "$WORK_DIR/mnt"/
    sync; umount "$WORK_DIR/mnt"
  else
    echo "WARNING: loop mount failed, falling back to mke2fs -d"
    mke2fs -q -t ext4 -F -L fleetroot -d "$ROOTFS" "$RFS"
  fi
  e2fsck -fn "$RFS" || { echo "ERROR: root filesystem failed e2fsck, refusing to build the image"; exit 1; }
  dd if="$RFS" of="$IMG" bs=1M seek=$(( ROOT_START * 512 / 1048576 )) conv=notrunc status=none
  rm -f "$RFS"

  bash "$HERE/rootfs/overlay/usr/local/sbin/fleet-mkkernel" -r "$ROOTFS" -v "$KVER" \
    -R "$ROOTGUID" -m "$USB_MODEL" -c "fleet_install=1" -o "$WORK_DIR/kern-usb.bin"
  dd if="$WORK_DIR/kern-usb.bin" of="$IMG" bs=512 seek=8192 conv=notrunc status=none

  cgpt show "$IMG"
  xz -T0 -6 -f -k "$IMG"
  ( cd "$OUT_DIR" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256" )
  ls -lh "$OUT_DIR"
}

case "$STEP" in
  deps) deps;;
  kernel) kernel;;
  rootfs) rootfs;;
  image) image;;
  all) kernel; rootfs; image;;
  *) echo "usage: $0 [deps|kernel|rootfs|image|all]"; exit 2;;
esac
