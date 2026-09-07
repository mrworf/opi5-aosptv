#!/usr/bin/env bash
set -euo pipefail

PROFILE= WIDEVINE= SOURCE= KERNEL_OUT=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE=$2; shift 2 ;;
    --widevine) WIDEVINE=$2; shift 2 ;;
    --source) SOURCE=$2; shift 2 ;;
    --kernel-out) KERNEL_OUT=$2; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
PRODUCT_OUT="$SOURCE/out/target/product/opi5_pro"
image_path_exists() {
  local image=$1 path=$2 output
  output=$(debugfs -R "stat $path" "$image" 2>&1) || return 1
  grep -q '^Inode:' <<<"$output"
}

require_image_path() {
  local image=$1 path=$2 description=$3
  image_path_exists "$image" "$path" || {
    echo "$description is missing from $(basename "$image"): $path" >&2
    exit 2
  }
}

reject_image_path() {
  local image=$1 path=$2 description=$3
  if image_path_exists "$image" "$path"; then
    echo "$description was packaged in $(basename "$image"): $path" >&2
    exit 2
  fi
}

for image in boot.img system.img vendor.img; do
  [[ -f "$PRODUCT_OUT/$image" ]] || { echo "Missing $image" >&2; exit 2; }
done
cmp "$KERNEL_OUT/arch/arm64/boot/Image" "$OPI5_KERNEL_PACKAGE_DIR/Image"
cmp "$KERNEL_OUT/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dtb" \
  "$OPI5_KERNEL_PACKAGE_DIR/rk3588s-orangepi-5.dtb"

require_image_path "$PRODUCT_OUT/system.img" \
  /product/app/Flicky/Flicky.apk "Flicky"
reject_image_path "$PRODUCT_OUT/system.img" \
  /product/app/GooglePhotos/GooglePhotos.apk "Google Photos"

if [[ $PROFILE == oss ]]; then
  [[ ! -e "$SOURCE/vendor/gapps_tv" ]] || { echo "OSS checkout contains GApps" >&2; exit 2; }
  [[ ! -e "$SOURCE/vendor/opi/widevine_local" ]] || { echo "OSS checkout contains Widevine" >&2; exit 2; }
  reject_image_path "$PRODUCT_OUT/system.img" \
    /product/app/YouTubeTV/YouTubeTV.apk "Google YouTube"
else
  [[ -f "$SOURCE/vendor/gapps_tv/arm64/arm64-vendor.mk" ]] || exit 2
  require_image_path "$PRODUCT_OUT/system.img" \
    /product/app/YouTubeTV/YouTubeTV.apk "Google YouTube"
fi
if [[ $WIDEVINE == enabled ]]; then
  image_path_exists "$PRODUCT_OUT/vendor.img" \
    /apex/com.google.android.widevine-15027108-cp2a.apex || {
      echo "Completed vendor.img lacks the required Widevine APEX" >&2; exit 2;
    }
else
  if image_path_exists "$PRODUCT_OUT/vendor.img" \
      /apex/com.google.android.widevine-15027108-cp2a.apex; then
    echo "Widevine was packaged while disabled" >&2; exit 2
  fi
fi

if ! status_output=$(cd "$SOURCE" && .repo/repo/repo forall -j1 \
    -c 'git status --porcelain --untracked-files=normal'); then
  echo "Unable to verify source repository cleanliness" >&2
  exit 2
fi
if [[ -n $status_output ]]; then
  printf '%s\n' "$status_output" >&2
  echo "Build left a source repository dirty" >&2
  exit 2
fi
sha256sum "$PRODUCT_OUT/boot.img" "$PRODUCT_OUT/system.img" "$PRODUCT_OUT/vendor.img"
