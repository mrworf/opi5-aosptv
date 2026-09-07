#!/usr/bin/env bash
set -euo pipefail

PROFILE= WIDEVINE= SOURCE= IMAGE= OUTPUT_DIR=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE=${2:-}; shift 2 ;;
    --widevine) WIDEVINE=${2:-}; shift 2 ;;
    --source) SOURCE=${2:-}; shift 2 ;;
    --image) IMAGE=${2:-}; shift 2 ;;
    --output-dir) OUTPUT_DIR=${2:-}; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

for value in PROFILE WIDEVINE SOURCE IMAGE OUTPUT_DIR; do
  [[ -n ${!value} ]] || { echo "Missing required release metadata option" >&2; exit 2; }
done
for tool in awk basename jq realpath sha256sum stat; do
  command -v "$tool" >/dev/null || { echo "Missing host tool: $tool" >&2; exit 2; }
done
[[ -x "$SOURCE/.repo/repo/repo" ]] || { echo "Missing repo tool in $SOURCE" >&2; exit 2; }

PRODUCT_OUT="$SOURCE/out/target/product/opi5_pro"
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UBOOT=${OPI5_KERNEL_PACKAGE_DIR:?Missing OPI5_KERNEL_PACKAGE_DIR}/u-boot-rockchip.bin
for artifact in "$IMAGE" "$IMAGE.sha256" \
    "$UBOOT" "$PRODUCT_OUT/boot.img" "$PRODUCT_OUT/system.img" "$PRODUCT_OUT/vendor.img"; do
  [[ -f $artifact ]] || { echo "Missing release artifact: $artifact" >&2; exit 2; }
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
MANIFEST="$OUTPUT_DIR/source-manifest.xml"
(cd "$SOURCE" && .repo/repo/repo manifest -r -o "$MANIFEST")

hash_of() { sha256sum "$1" | awk '{print $1}'; }
size_of() { stat -c %s "$1"; }
path_of() {
  local path
  path=$(realpath -e "$1")
  [[ $path == "$ROOT/"* ]] || {
    echo "Release artifact is outside the workspace: $path" >&2
    exit 2
  }
  realpath --relative-to="$ROOT" "$path"
}
IMAGE_NAME=$(basename "$IMAGE")

jq -n \
  --arg schema "opi5-release-v2" \
  --arg created_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg profile "$PROFILE" \
  --arg widevine "$WIDEVINE" \
  --arg product "Orange Pi 5" \
  --arg android_product "opi5_pro" \
  --arg dtb "rk3588s-orangepi-5.dtb" \
  --arg image_name "$IMAGE_NAME" \
  --arg image_path "$(path_of "$IMAGE")" \
  --arg image_sha256 "$(hash_of "$IMAGE")" \
  --argjson image_size "$(size_of "$IMAGE")" \
  --arg uboot_path "$(path_of "$UBOOT")" \
  --arg uboot_sha256 "$(hash_of "$UBOOT")" \
  --argjson uboot_size "$(size_of "$UBOOT")" \
  --arg boot_path "$(path_of "$PRODUCT_OUT/boot.img")" \
  --arg boot_sha256 "$(hash_of "$PRODUCT_OUT/boot.img")" \
  --argjson boot_size "$(size_of "$PRODUCT_OUT/boot.img")" \
  --arg system_path "$(path_of "$PRODUCT_OUT/system.img")" \
  --arg system_sha256 "$(hash_of "$PRODUCT_OUT/system.img")" \
  --argjson system_size "$(size_of "$PRODUCT_OUT/system.img")" \
  --arg vendor_path "$(path_of "$PRODUCT_OUT/vendor.img")" \
  --arg vendor_sha256 "$(hash_of "$PRODUCT_OUT/vendor.img")" \
  --argjson vendor_size "$(size_of "$PRODUCT_OUT/vendor.img")" \
  --arg manifest_sha256 "$(hash_of "$MANIFEST")" \
  '{
    schema: $schema,
    created_utc: $created_utc,
    profile: $profile,
    widevine: $widevine,
    product: $product,
    android_product: $android_product,
    dtb: $dtb,
    source_manifest: {file: "source-manifest.xml", sha256: $manifest_sha256},
    artifacts: {
      disk_image: {file: $image_name, path: $image_path, size: $image_size, sha256: $image_sha256},
      uboot: {path: $uboot_path, size: $uboot_size, sha256: $uboot_sha256},
      boot: {path: $boot_path, size: $boot_size, sha256: $boot_sha256},
      system: {path: $system_path, size: $system_size, sha256: $system_sha256},
      vendor: {path: $vendor_path, size: $vendor_size, sha256: $vendor_sha256}
    }
  }' > "$OUTPUT_DIR/release.json"

echo "$OUTPUT_DIR/release.json"
