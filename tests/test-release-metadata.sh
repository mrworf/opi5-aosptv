#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/release-metadata-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

SOURCE="$TEST_ROOT/source"
PRODUCT_OUT="$SOURCE/out/target/product/opi5_pro"
OUTPUT="$TEST_ROOT/release"
PACKAGE_DIR="$SOURCE/out/opi5/kernel-package"
mkdir -p "$SOURCE/.repo/repo" "$PRODUCT_OUT" "$PACKAGE_DIR"
printf '#!/usr/bin/env bash\nprintf '\''%%s\\n'\'' '\''<manifest revision="fixed"/>'\'' > "$4"\n' > "$SOURCE/.repo/repo/repo"
chmod +x "$SOURCE/.repo/repo/repo"
printf boot > "$PRODUCT_OUT/boot.img"
printf system > "$PRODUCT_OUT/system.img"
printf vendor > "$PRODUCT_OUT/vendor.img"
printf uboot > "$PACKAGE_DIR/u-boot-rockchip.bin"
printf image > "$PRODUCT_OUT/release.img"
sha256sum "$PRODUCT_OUT/release.img" > "$PRODUCT_OUT/release.img.sha256"

OPI5_KERNEL_PACKAGE_DIR="$PACKAGE_DIR" "$ROOT/tools/write-release-metadata.sh" \
  --profile custom --widevine enabled --source "$SOURCE" \
  --image "$PRODUCT_OUT/release.img" --output-dir "$OUTPUT" >/dev/null

jq -e '
  .schema == "opi5-release-v2" and
  .profile == "custom" and
  .widevine == "enabled" and
  .product == "Orange Pi 5" and
  .android_product == "opi5_pro" and
  .dtb == "rk3588s-orangepi-5.dtb" and
  .artifacts.disk_image.file == "release.img" and
  .artifacts.disk_image.size == 5 and
  (.artifacts.disk_image.path | startswith(".state/")) and
  (.source_manifest.sha256 | length == 64) and
  .artifacts.uboot.size == 5 and
  (.artifacts.uboot.path | endswith("u-boot-rockchip.bin")) and
  .artifacts.boot.size == 4 and
  (.artifacts.boot.sha256 | length == 64) and
  .artifacts.system.size == 6 and
  (.artifacts.system.sha256 | length == 64) and
  .artifacts.vendor.size == 6 and
  (.artifacts.vendor.sha256 | length == 64)
' "$OUTPUT/release.json" >/dev/null
grep -q 'revision="fixed"' "$OUTPUT/source-manifest.xml"

echo "release metadata tests passed"
