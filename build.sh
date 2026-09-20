#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/lib/profile.sh"
source "$ROOT/lib/release-signing.sh"
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
if [[ $OPI5_VARIANT == user ]]; then
  opi5_ensure_release_keys "$ROOT"
  opi5_require_release_keys "$ROOT" "$SOURCE"
  opi5_require_clean_release_sources "$ROOT" "$SOURCE"
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
python3 "$ROOT/tools/render-boot-script.py" \
  --input "$KERNEL_PACKAGE/boot.cmd" \
  --output "$KERNEL_PACKAGE/boot.scr" \
  --variant "$OPI5_VARIANT"

PROFILE_MK="$SOURCE/out/opi5/opi5-profile.mk"
export OPI5_BUILD_PROFILE="$OPI5_PROFILE"
export OPI5_BUILD_VARIANT="$OPI5_VARIANT"
if [[ $OPI5_WIDEVINE == enabled ]]; then
  export OPI5_ENABLE_WIDEVINE=true
else
  export OPI5_ENABLE_WIDEVINE=false
fi
{
  printf 'OPI5_BUILD_PROFILE := %s\n' "$OPI5_BUILD_PROFILE"
  printf 'OPI5_ENABLE_WIDEVINE := %s\n' "$OPI5_ENABLE_WIDEVINE"
  printf 'OPI5_BUILD_VARIANT := %s\n' "$OPI5_BUILD_VARIANT"
} > "$PROFILE_MK"
export OPI5_PRODUCT_PROFILE_MK="$PROFILE_MK"
export OPI5_ADB_KEYS=".opi5-config/adbkey.pub"
export OPI5_KERNEL_BUILD_OUT="$KERNEL_OUT"
export OPI5_KERNEL_PACKAGE_DIR="$KERNEL_PACKAGE"
OPI5_SOURCE_ID=$("$ROOT/tools/source-build-id.sh" "$SOURCE" "$OPI5_PROFILE" "$OPI5_WIDEVINE" "$OPI5_VARIANT")
export BUILD_NUMBER="OPI5.$OPI5_SOURCE_ID"
export BUILD_USERNAME=opi5
export BUILD_HOSTNAME=builder

cd "$SOURCE"
source build/envsetup.sh
if [[ $OPI5_PROFILE == oss ]]; then
  lunch "aosp_opi5_tv_oss-cp2a-$OPI5_VARIANT"
else
  lunch "aosp_opi5_tv_custom-cp2a-$OPI5_VARIANT"
fi
if [[ $OPI5_VARIANT == user ]]; then
  # BUILD_NUMBER is not a complete Ninja dependency for every partition's
  # build.prop. Reinstall the product tree before release packaging so an
  # incremental build cannot mix a new system identity with stale vendor/ODM
  # identities from the previous release.
  m -j26 installclean
  m -j26 target-files-package sign_target_files_apks img_from_target_files
  "$ROOT/tools/sign-release-images.sh" \
    --source "$SOURCE" --product-out "$SOURCE/out/target/product/opi5_pro" \
    --key-dir "$OPI5_SIGNING_DIR" \
    --output-dir "$SOURCE/out/opi5/signed/$OPI5_SOURCE_ID"
else
  m -j26 bootimage systemimage vendorimage
fi
RELEASE_STAMP=$(date -u +%Y%m%dT%H%M%SZ)
IMAGE_PATH="$SOURCE/out/target/product/opi5_pro/OrangePi_5-Android17-TV-${OPI5_PROFILE}-${OPI5_VARIANT}-widevine-${OPI5_ENABLE_WIDEVINE}-${RELEASE_STAMP}.img"
OPI5_IMAGE_PATH="$IMAGE_PATH" \
  "$ROOT/tools/assemble-image.sh" --product-out "$SOURCE/out/target/product/opi5_pro"
"$ROOT/tools/verify-release.sh" \
  --profile "$OPI5_PROFILE" --widevine "$OPI5_WIDEVINE" --variant "$OPI5_VARIANT" \
  --build-id "$OPI5_SOURCE_ID" --source "$SOURCE" --kernel-out "$KERNEL_OUT"
"$ROOT/tools/write-release-metadata.sh" \
  --profile "$OPI5_PROFILE" --widevine "$OPI5_WIDEVINE" --variant "$OPI5_VARIANT" \
  --build-id "$OPI5_SOURCE_ID" \
  --source "$SOURCE" --image "$IMAGE_PATH" \
  --output-dir "$ROOT/releases/${OPI5_PROFILE}-${OPI5_VARIANT}-widevine-${OPI5_ENABLE_WIDEVINE}-${RELEASE_STAMP}"
