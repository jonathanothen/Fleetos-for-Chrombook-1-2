#!/bin/bash
# Cross-compiles Linux for armhf and produces .deb packages in $OUT_DIR/kernel/
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../config.env"

mkdir -p "$WORK_DIR" "$OUT_DIR/kernel"
cd "$WORK_DIR"

MAJOR="${KERNEL_VERSION%%.*}"
TARBALL="linux-${KERNEL_VERSION}.tar.xz"
BASE="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x"

[ -f "$TARBALL" ] || curl -fL -o "$TARBALL" "$BASE/$TARBALL"
# Verify checksum against kernel.org's list
curl -fsSL "$BASE/sha256sums.asc" -o sha256sums.asc
grep " $TARBALL\$" sha256sums.asc | sha256sum -c -

rm -rf "linux-${KERNEL_VERSION}"
tar xf "$TARBALL"
cd "linux-${KERNEL_VERSION}"

export ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
make multi_v7_defconfig
./scripts/kconfig/merge_config.sh -m .config "$HERE/fleet.config"
make olddefconfig

# Sanity check: critical symbols must be enabled, otherwise the machine will not boot
for sym in EXT4_FS MMC_DW_EXYNOS KEYBOARD_CROS_EC MWIFIEX_SDIO DRM_EXYNOS EFI_PARTITION; do
  grep -Eq "^CONFIG_${sym}=[ym]" .config || { echo "MISSING in .config: $sym"; exit 1; }
done

# DPKG_FLAGS=-d: skip the build-dep check (it wants armhf libssl-dev, which is not needed for cross-compiling)
make -j"$(nproc)" bindeb-pkg DPKG_FLAGS=-d KDEB_PKGVERSION="${KERNEL_VERSION}-1fleet1" \
  KBUILD_BUILD_USER=fleet KBUILD_BUILD_HOST=builder
cd "$WORK_DIR"
rm -f "$OUT_DIR"/kernel/*.deb
cp linux-image-*.deb "$OUT_DIR/kernel/"
ls -l "$OUT_DIR/kernel/"
