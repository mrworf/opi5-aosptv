#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/release-verifier-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

SOURCE="$TEST_ROOT/source"
PRODUCT_OUT="$SOURCE/out/target/product/opi5_pro"
OSS_SOURCE="$TEST_ROOT/oss-source"
OSS_PRODUCT_OUT="$OSS_SOURCE/out/target/product/opi5_pro"
KERNEL_OUT="$TEST_ROOT/kernel-out"
PACKAGE_DIR="$TEST_ROOT/kernel-package"
MOCK_BIN="$TEST_ROOT/bin"
mkdir -p "$PRODUCT_OUT" "$OSS_PRODUCT_OUT" \
  "$KERNEL_OUT/arch/arm64/boot/dts/rockchip" "$PACKAGE_DIR" "$MOCK_BIN" \
  "$SOURCE/.repo/repo" "$SOURCE/vendor/gapps_tv/arm64" "$OSS_SOURCE/.repo/repo"

printf 'kernel\n' > "$KERNEL_OUT/arch/arm64/boot/Image"
cp "$KERNEL_OUT/arch/arm64/boot/Image" "$PACKAGE_DIR/Image"
printf 'dtb\n' > "$KERNEL_OUT/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dtb"
cp "$KERNEL_OUT/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dtb" \
  "$PACKAGE_DIR/rk3588s-orangepi-5.dtb"
touch "$PRODUCT_OUT/boot.img" "$PRODUCT_OUT/system.img" "$PRODUCT_OUT/vendor.img" \
  "$OSS_PRODUCT_OUT/boot.img" "$OSS_PRODUCT_OUT/system.img" "$OSS_PRODUCT_OUT/vendor.img"
touch "$SOURCE/vendor/gapps_tv/arm64/arm64-vendor.mk"

cat > "$MOCK_BIN/debugfs" <<'EOF'
#!/usr/bin/env bash
request=${2:-}
present=0
case "$request" in
  *com.google.android.widevine*) present=${MOCK_WIDEVINE_PRESENT:-0} ;;
  *Flicky*) present=${MOCK_FLICKY_PRESENT:-1} ;;
  *YouTubeTV*) present=${MOCK_YOUTUBE_PRESENT:-1} ;;
  *GooglePhotos*) present=${MOCK_PHOTOS_PRESENT:-0} ;;
esac
if [[ $present == 1 ]]; then
  echo 'Inode: 42   Type: regular'
else
  echo "$request: File not found by ext2_lookup"
fi
exit 0
EOF
chmod +x "$MOCK_BIN/debugfs"

cat > "$SOURCE/.repo/repo/repo" <<'EOF'
#!/usr/bin/env bash
[[ ${MOCK_REPO_FAIL:-0} != 1 ]] || exit 1
[[ ${MOCK_REPO_DIRTY:-0} != 1 ]] || printf ' M dirty-file\n'
EOF
chmod +x "$SOURCE/.repo/repo/repo"
cp "$SOURCE/.repo/repo/repo" "$OSS_SOURCE/.repo/repo/repo"

run_verifier() {
  local profile=$1 widevine=$2 source=$SOURCE
  [[ $profile != oss ]] || source=$OSS_SOURCE
  env PATH="$MOCK_BIN:$PATH" OPI5_KERNEL_PACKAGE_DIR="$PACKAGE_DIR" \
    "$ROOT/tools/verify-release.sh" --profile "$profile" --widevine "$widevine" \
    --source "$source" --kernel-out "$KERNEL_OUT"
}

# debugfs returns success even for a missing path; absence must be judged by output.
MOCK_WIDEVINE_PRESENT=0 run_verifier custom disabled >/dev/null
if MOCK_WIDEVINE_PRESENT=0 run_verifier custom enabled >/dev/null 2>&1; then
  echo "Missing Widevine APEX was accepted" >&2
  exit 1
fi
MOCK_WIDEVINE_PRESENT=1 run_verifier custom enabled >/dev/null
if MOCK_WIDEVINE_PRESENT=1 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Unexpected Widevine APEX was accepted" >&2
  exit 1
fi

if MOCK_YOUTUBE_PRESENT=0 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image without YouTube was accepted" >&2
  exit 1
fi
if MOCK_PHOTOS_PRESENT=1 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image containing Google Photos was accepted" >&2
  exit 1
fi
MOCK_YOUTUBE_PRESENT=0 MOCK_PHOTOS_PRESENT=0 run_verifier oss disabled >/dev/null
if MOCK_YOUTUBE_PRESENT=1 MOCK_PHOTOS_PRESENT=0 run_verifier oss disabled >/dev/null 2>&1; then
  echo "OSS image containing YouTube was accepted" >&2
  exit 1
fi
if MOCK_YOUTUBE_PRESENT=0 MOCK_PHOTOS_PRESENT=1 run_verifier oss disabled >/dev/null 2>&1; then
  echo "OSS image containing Google Photos was accepted" >&2
  exit 1
fi
if MOCK_FLICKY_PRESENT=0 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image without Flicky was accepted" >&2
  exit 1
fi
if MOCK_FLICKY_PRESENT=0 MOCK_YOUTUBE_PRESENT=0 run_verifier oss disabled >/dev/null 2>&1; then
  echo "OSS image without Flicky was accepted" >&2
  exit 1
fi

if MOCK_REPO_DIRTY=1 MOCK_WIDEVINE_PRESENT=0 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Dirty source checkout was accepted" >&2
  exit 1
fi
if MOCK_REPO_FAIL=1 MOCK_WIDEVINE_PRESENT=0 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Failed source-state inspection was accepted" >&2
  exit 1
fi

echo "release verifier tests passed"
