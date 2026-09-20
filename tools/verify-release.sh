#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

PROFILE= WIDEVINE= VARIANT= BUILD_ID= SOURCE= KERNEL_OUT=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE=$2; shift 2 ;;
    --widevine) WIDEVINE=$2; shift 2 ;;
    --variant) VARIANT=$2; shift 2 ;;
    --build-id) BUILD_ID=$2; shift 2 ;;
    --source) SOURCE=$2; shift 2 ;;
    --kernel-out) KERNEL_OUT=$2; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ $VARIANT == userdebug || $VARIANT == user ]] || { echo "Invalid build variant" >&2; exit 2; }
[[ -n $BUILD_ID ]] || { echo "Missing build ID" >&2; exit 2; }
PRODUCT_OUT="$SOURCE/out/target/product/opi5_pro"
image_path_exists() {
  local image=$1 path=$2 output
  output=$(debugfs -R "stat $path" "$image" 2>&1) || return 1
  grep -q '^Inode:' <<<"$output"
}

boot_script_contains() {
  local pattern=$1
  # Do not use grep -q here: an early grep exit can SIGPIPE mtype and turn a
  # successful check into status 141 under pipefail.  Consuming the complete
  # boot script also avoids storing its embedded NUL bytes in a shell variable.
  mtype -i "$PRODUCT_OUT/boot.img" ::boot.scr 2>/dev/null |
    grep -aF "$pattern" >/dev/null
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

require_fmq_policy() {
  local policy rule permission source target description
  policy=$(debugfs -R "cat /etc/selinux/vendor_sepolicy.cil" \
    "$PRODUCT_OUT/vendor.img" 2>/dev/null) || {
      echo "Unable to inspect vendor SELinux policy" >&2
      exit 2
    }
  grep -Eq '^\(policycap memfd_class\)$' <<<"$policy" || {
    echo "Vendor policy does not enable the required Android 17 memfd_class capability" >&2
    exit 2
  }
  while read -r source target description; do
    rule=$(grep -m 1 -E "^\(allow ${source}(_[^ ]+)? ${target}(_[^ ]+)? \(file \([^)]*\)\)\)$" \
      <<<"$policy") || true
    [[ -n $rule ]] || {
      echo "Vendor policy lacks the $description FMQ rule" >&2
      exit 2
    }
    for permission in read write map; do
      grep -qw "$permission" <<<"$rule" || {
        echo "$description FMQ rule lacks $permission permission" >&2
        exit 2
      }
    done
  done <<'EOF'
hal_audio_default tmpfs audio-HAL
audioserver tmpfs audio-server
system_server audioserver_tmpfs audio-policy
hal_power_default hal_power_default_tmpfs power-HAL
system_server hal_power_default_tmpfs power-manager
EOF
}

require_partition_build_id() {
  local image=$1 path=$2 property=$3 partition=$4 actual
  actual=$(debugfs -R "cat $path" "$image" 2>/dev/null |
    awk -F= -v key="$property" '$1 == key { print $2; exit }')
  [[ $actual == "OPI5.$BUILD_ID" ]] || {
    echo "$partition build ID mismatch: expected OPI5.$BUILD_ID, found ${actual:-missing}" >&2
    exit 2
  }
}

for image in boot.img system.img vendor.img; do
  [[ -f "$PRODUCT_OUT/$image" ]] || { echo "Missing $image" >&2; exit 2; }
done
require_fmq_policy
require_partition_build_id "$PRODUCT_OUT/system.img" /system/build.prop \
  ro.build.version.incremental system
require_partition_build_id "$PRODUCT_OUT/vendor.img" /build.prop \
  ro.vendor.build.version.incremental vendor
mtype -i "$PRODUCT_OUT/boot.img" ::boot.scr 2>/dev/null |
  python3 "$ROOT/tools/verify-boot-script.py" --input - --variant "$VARIANT"
if [[ $VARIANT == user ]]; then
  if boot_script_contains 'androidboot.selinux=permissive'; then
    echo "User boot image requests permissive SELinux" >&2
    exit 2
  fi
  reject_image_path "$PRODUCT_OUT/system.img" \
    /system/bin/logcatd "persistent log daemon in user build"
else
  boot_script_contains 'androidboot.selinux=permissive' || {
    echo "Userdebug boot image unexpectedly lacks permissive SELinux" >&2; exit 2;
  }
  require_image_path "$PRODUCT_OUT/system.img" \
    /system/bin/logcatd "userdebug persistent log daemon"
fi
require_image_path "$PRODUCT_OUT/system.img" \
  /product/etc/security/adb_keys "pre-authorized Ethernet ADB public key"
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
  require_image_path "$PRODUCT_OUT/system.img" \
    /product/priv-app/TvProvision/TvProvision.apk "AOSP TV provisioner"
  reject_image_path "$PRODUCT_OUT/system.img" \
    /product/app/YouTubeTV/YouTubeTV.apk "Google YouTube"
else
  [[ -f "$SOURCE/vendor/gapps_tv/arm64/arm64-vendor.mk" ]] || exit 2
  reject_image_path "$PRODUCT_OUT/system.img" \
    /product/priv-app/TvProvision/TvProvision.apk "duplicate AOSP TV provisioner"
  require_image_path "$PRODUCT_OUT/system.img" \
    /product/app/YouTubeTV/YouTubeTV.apk "Google YouTube"
  reject_image_path "$PRODUCT_OUT/system.img" \
    /product/priv-app/AndroidMediaShell/AndroidMediaShell.apk "unprovisioned Cast receiver"
  reject_image_path "$PRODUCT_OUT/system.img" \
    /product/priv-app/Backdrop/Backdrop.apk "Cast-dependent Backdrop dream"
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
