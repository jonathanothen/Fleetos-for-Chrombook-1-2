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

# Local patch: mwifiex treats ANY failed command during init as fatal. The Marvell 8797 firmware answers
# CHAN_REGION_CFG (0x242) with "not supported" (result 0x2), so init aborts and no wlan0 appears.
# Make that single command non-fatal.
perl -0pi -e 's|(\t/\* Check init command response \*/\n)|\t/* FleetOS patch: sd8797 firmware does not support CHAN_REGION_CFG; not fatal. */\n\tif (ret \&\& cmdresp_no == HostCmd_CMD_CHAN_REGION_CFG)\n\t\tret = 0;\n\n$1|' \
  drivers/net/wireless/marvell/mwifiex/cmdevt.c
grep -q "FleetOS patch" drivers/net/wireless/marvell/mwifiex/cmdevt.c \
  || { echo "ERROR: mwifiex patch did not apply (kernel source changed?)"; exit 1; }

export ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
# exynos_defconfig (not multi_v7): the old ChromeOS firmware only loads a small kernel.
# The Kali Exynos image that boots on these machines has a 4.4 MB kernel.
make exynos_defconfig
./scripts/kconfig/merge_config.sh -m .config "$HERE/fleet.config"
make olddefconfig

# Sanity check: critical symbols must be enabled, otherwise the machine will not boot
for sym in EXT4_FS MMC_DW_EXYNOS KEYBOARD_CROS_EC MWIFIEX_SDIO DRM_EXYNOS EFI_PARTITION; do
  grep -Eq "^CONFIG_${sym}=[ym]" .config || { echo "MISSING in .config: $sym"; exit 1; }
done

# Report kernel size (known-good Kali kernel: 4.4 MB; our first 11.9 MB build did not boot)
for sym in PROVE_LOCKING LOCKDEP DEBUG_ATOMIC_SLEEP PROVE_RCU; do
  grep -Eq "^CONFIG_${sym}=y" .config && { echo "UNWANTED debug option still enabled: $sym"; exit 1; }
done

make -j"$(nproc)" zImage
ZSIZE=$(stat -c %s arch/arm/boot/zImage)
echo "zImage size: $ZSIZE bytes ($((ZSIZE/1024/1024)) MiB)"
[ "$ZSIZE" -gt 7340032 ] && echo "WARNING: zImage is larger than 7 MiB, the firmware may refuse to load it"

# DPKG_FLAGS=-d: skip the build-dep check (it wants armhf libssl-dev, which is not needed for cross-compiling)
make -j"$(nproc)" bindeb-pkg DPKG_FLAGS=-d KDEB_PKGVERSION="${KERNEL_VERSION}-1fleet1" \
  KBUILD_BUILD_USER=fleet KBUILD_BUILD_HOST=builder
cd "$WORK_DIR"
rm -f "$OUT_DIR"/kernel/*.deb
cp linux-image-*.deb "$OUT_DIR/kernel/"
ls -l "$OUT_DIR/kernel/"
