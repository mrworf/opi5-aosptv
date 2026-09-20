#!/usr/bin/env bash
set -euo pipefail

SOURCE= PRODUCT_OUT= KEY_DIR= OUTPUT_DIR=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE=${2:-}; shift 2 ;;
    --product-out) PRODUCT_OUT=${2:-}; shift 2 ;;
    --key-dir) KEY_DIR=${2:-}; shift 2 ;;
    --output-dir) OUTPUT_DIR=${2:-}; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
for value in SOURCE PRODUCT_OUT KEY_DIR OUTPUT_DIR; do
  [[ -n ${!value} ]] || { echo "Missing required signing option" >&2; exit 2; }
done
for tool in unzip; do
  command -v "$tool" >/dev/null || { echo "Missing host tool: $tool" >&2; exit 2; }
done

SIGNER="$SOURCE/out/host/linux-x86/bin/sign_target_files_apks"
IMAGE_BUILDER="$SOURCE/out/host/linux-x86/bin/img_from_target_files"
[[ -x $SIGNER && -x $IMAGE_BUILDER ]] || {
  echo "Missing release tools; build sign_target_files_apks and img_from_target_files" >&2
  exit 2
}
TARGET_DIR="$PRODUCT_OUT/obj/PACKAGING/target_files_intermediates"
mapfile -t candidates < <(find "$TARGET_DIR" -maxdepth 1 -type f \
  \( -name '*-target_files.zip' -o -name '*-target_files-*.zip' \) -print | sort)
(( ${#candidates[@]} == 1 )) || {
  echo "Expected exactly one target-files archive under $TARGET_DIR; found ${#candidates[@]}" >&2
  exit 2
}

mkdir -p "$OUTPUT_DIR"
SIGNED_TARGET_FILES="$OUTPUT_DIR/signed-target_files.zip"
SIGNED_IMAGES="$OUTPUT_DIR/signed-images.zip"
[[ ! -e $SIGNED_TARGET_FILES && ! -e $SIGNED_IMAGES ]] || {
  echo "Refusing to overwrite existing signed output in $OUTPUT_DIR" >&2; exit 2;
}
"$SIGNER" -d "$KEY_DIR" \
  -k "build/make/target/product/security/sdk_sandbox=build/make/target/product/security/sdk_sandbox" \
  -k "build/make/target/product/security/cts_uicc_2021=$KEY_DIR/cts_uicc_2021" \
  --override_apex_keys "$KEY_DIR/apex.pem" \
  "${candidates[0]}" "$SIGNED_TARGET_FILES"
"$(dirname "$0")/verify-signed-target-files.sh" \
  --source "$SOURCE" --key-dir "$KEY_DIR" --target-files "$SIGNED_TARGET_FILES"
"$IMAGE_BUILDER" "$SIGNED_TARGET_FILES" "$SIGNED_IMAGES"

STAGE="$OUTPUT_DIR/images"
mkdir -p "$STAGE"
for image in boot.img system.img vendor.img; do
  unzip -p "$SIGNED_IMAGES" "$image" > "$STAGE/$image"
  [[ -s $STAGE/$image ]] || { echo "Signed archive lacks $image" >&2; exit 2; }
done
for image in boot.img system.img vendor.img; do
  install -m 0644 "$STAGE/$image" "$PRODUCT_OUT/$image"
done
printf '%s\n' "$SIGNED_TARGET_FILES"
