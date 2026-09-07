#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/lib/profile.sh"
opi5_resolve_profile "$ROOT" "$@"
opi5_require_adb_key "$ROOT"

SOURCE_SLOT=$(opi5_source_slot)
SOURCE="$ROOT/sources/$SOURCE_SLOT"
[[ -d "$SOURCE/.repo" ]] || { echo "Run ./bootstrap.sh first" >&2; exit 2; }
ADB_KEY_SOURCE="$ROOT/config/adb/adbkey.pub"
ADB_KEY_STAGE="$SOURCE/.opi5-config/adbkey.pub"
mkdir -p "$(dirname "$ADB_KEY_STAGE")"
install -m 0644 "$ADB_KEY_SOURCE" "$ADB_KEY_STAGE"
if [[ $OPI5_PROFILE == custom ]]; then
  [[ -f "$SOURCE/vendor/gapps_tv/arm64/arm64-vendor.mk" ]] || {
    echo "Custom profile requires a valid GApps checkout" >&2; exit 2;
  }
fi
if [[ $OPI5_WIDEVINE == enabled ]]; then
  [[ -f "$SOURCE/vendor/opi/widevine_local/widevine-vendor.mk" ]] || {
    echo "Widevine enabled but its bundle is unavailable" >&2; exit 2;
  }
fi

export TMPDIR="$SOURCE/out/opi5/tmp"
export TMP="$TMPDIR" TEMP="$TMPDIR" GOCACHE="$SOURCE/out/opi5/go-cache"
KERNEL_ROOT="$SOURCE/kernel/opi/rk3588"
KERNEL_OUT="$SOURCE/out/kernel/opi5"
KERNEL_PACKAGE="$SOURCE/out/opi5/kernel-package"
STATIC_KERNEL="$SOURCE/device/opi/opi5_pro-kernel"
mkdir -p "$TMPDIR" "$GOCACHE" "$KERNEL_OUT" "$KERNEL_PACKAGE"

CLANG_BIN="$SOURCE/prebuilts/clang/host/linux-x86/clang-r596125/bin"
export PATH="$CLANG_BIN:$PATH"
make -C "$KERNEL_ROOT" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 android_orangepi5_defconfig
make -C "$KERNEL_ROOT" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 -j26 Image dtbs modules
rsync -a --delete --exclude=.git/ "$STATIC_KERNEL/" "$KERNEL_PACKAGE/"
install -m 0644 "$KERNEL_OUT/arch/arm64/boot/Image" "$KERNEL_PACKAGE/Image"
install -m 0644 "$KERNEL_OUT/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dtb" \
  "$KERNEL_PACKAGE/rk3588s-orangepi-5.dtb"

PROFILE_MK="$SOURCE/out/opi5/opi5-profile.mk"
export OPI5_BUILD_PROFILE="$OPI5_PROFILE"
if [[ $OPI5_WIDEVINE == enabled ]]; then
  export OPI5_ENABLE_WIDEVINE=true
else
  export OPI5_ENABLE_WIDEVINE=false
fi
{
  printf 'OPI5_BUILD_PROFILE := %s\n' "$OPI5_BUILD_PROFILE"
  printf 'OPI5_ENABLE_WIDEVINE := %s\n' "$OPI5_ENABLE_WIDEVINE"
} > "$PROFILE_MK"
export OPI5_PRODUCT_PROFILE_MK="$PROFILE_MK"
export OPI5_ADB_KEYS=".opi5-config/adbkey.pub"
export OPI5_KERNEL_BUILD_OUT="$KERNEL_OUT"
export OPI5_KERNEL_PACKAGE_DIR="$KERNEL_PACKAGE"

cd "$SOURCE"
source build/envsetup.sh
if [[ $OPI5_PROFILE == oss ]]; then
  lunch aosp_opi5_tv_oss-cp2a-userdebug
else
  lunch aosp_opi5_tv_custom-cp2a-userdebug
fi
m -j26 bootimage systemimage vendorimage
RELEASE_STAMP=$(date -u +%Y%m%dT%H%M%SZ)
IMAGE_PATH="$SOURCE/out/target/product/opi5_pro/OrangePi_5-Android17-TV-${OPI5_PROFILE}-widevine-${OPI5_ENABLE_WIDEVINE}-${RELEASE_STAMP}.img"
OPI5_IMAGE_PATH="$IMAGE_PATH" \
  "$ROOT/tools/assemble-image.sh" --product-out "$SOURCE/out/target/product/opi5_pro"
"$ROOT/tools/verify-release.sh" \
  --profile "$OPI5_PROFILE" --widevine "$OPI5_WIDEVINE" \
  --source "$SOURCE" --kernel-out "$KERNEL_OUT"
"$ROOT/tools/write-release-metadata.sh" \
  --profile "$OPI5_PROFILE" --widevine "$OPI5_WIDEVINE" \
  --source "$SOURCE" --image "$IMAGE_PATH" \
  --output-dir "$ROOT/releases/${OPI5_PROFILE}-widevine-${OPI5_ENABLE_WIDEVINE}-${RELEASE_STAMP}"
