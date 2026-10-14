#!/bin/bash
# Builds the FleetOS USB installer image. Run as root on Debian/Ubuntu.
#   sudo FLEET_PASSWORD='...' ./build.sh [deps|kernel|rootfs|image|all]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/config.env"
STEP="${1:-all}"
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)."; exit 1; }
: "${FLEET_PASSWORD:?Set FLEET_PASSWORD (password for user $FLEET_USER)}"

ROOTFS="$WORK_DIR/rootfs"
mkdir -p "$OUT_DIR" "$WORK_DIR"

deps() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y mmdebstrap qemu-user-static binfmt-support debian-archive-keyring \
    cgpt vboot-utils vboot-kernel-utils u-boot-tools device-tree-compiler e2fsprogs \
    gcc-arm-linux-gnueabihf build-essential bc flex bison libssl-dev libelf-dev \
    dpkg-dev fakeroot kmod cpio rsync xz-utils curl uuid-runtime
}

kernel() { bash "$HERE/kernel/build-kernel.sh"; }

rootfs() {
  rm -rf "$ROOTFS"
  cat > "$WORK_DIR/fleet-build.env" <<EOF
FLEET_USER='$FLEET_USER'
FLEET_PASSWORD='$FLEET_PASSWORD'
FLEET_SSH_KEY='${FLEET_SSH_KEY:-}'
EOF
  chmod 600 "$WORK_DIR/fleet-build.env"
  local debs; debs=$(ls "$OUT_DIR"/kernel/linux-image-*.deb)
  mmdebstrap --arch=armhf --variant=minbase \
    --components="main contrib non-free non-free-firmware" \
    --include="$(paste -sd, "$HERE/rootfs/packages.txt")" \
    --customize-hook="sync-in '$HERE/rootfs/overlay' /" \
    --customize-hook="copy-in $debs /tmp" \
    --customize-hook="copy-in '$WORK_DIR/fleet-build.env' '$HERE/rootfs/customize.sh' /tmp" \
    --customize-hook='chroot "$1" sh -c "chmod +x /usr/local/sbin/* /usr/local/bin/* /etc/kernel/postinst.d/zz-fleet-kernel"' \
    --customize-hook='chroot "$1" bash /tmp/customize.sh' \
    "$SUITE" "$ROOTFS" "$MIRROR"
  rm -f "$ROOTFS/tmp/fleet-build.env"
}

image() {
  local KVER; KVER=$(basename "$(ls "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -1)"); KVER=${KVER#vmlinuz-}
  local IMG="$OUT_DIR/fleetos-usb-${USB_MODEL}.img"
  local ROOT_MIB=$(( $(du -sm "$ROOTFS" | cut -f1) * 115 / 100 + 300 ))
  local ROOT_SECT=$(( ROOT_MIB * 2048 ))
  local TOTAL=$(( 270336 + ROOT_SECT + 64 ))
  local ROOTGUID; ROOTGUID=$(uuidgen)

  rm -f "$IMG"; truncate -s $(( TOTAL * 512 )) "$IMG"
  cgpt create "$IMG"
  cgpt add -i 1 -t kernel -b 8192   -s 131072 -l KERN-A -S 1 -T 0 -P 2 "$IMG"
  cgpt add -i 2 -t kernel -b 139264 -s 131072 -l KERN-B -S 0 -T 0 -P 0 "$IMG"
  cgpt add -i 3 -t data   -b 270336 -s "$ROOT_SECT" -l ROOT-A -u "$ROOTGUID" "$IMG"

  echo "PARTUUID=$ROOTGUID / ext4 defaults,noatime 0 1" > "$ROOTFS/etc/fstab"
  mke2fs -q -t ext4 -L fleetroot -d "$ROOTFS" -E offset=$(( 270336 * 512 )) "$IMG" "${ROOT_MIB}M"

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
