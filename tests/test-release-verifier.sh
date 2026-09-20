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

cat >"$TEST_ROOT/boot.cmd" <<'EOF'
if test "${recovery}" = "true"; then
    setenv recovery_bootargs "androidboot.boot_device=${boot_device}"
else
    setenv recovery_bootargs ""
fi;
setenv bootargs "${recovery_bootargs} androidboot.hardware=opi5 androidboot.selinux=permissive"
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
EOF
python3 "$ROOT/tools/render-boot-script.py" --input "$TEST_ROOT/boot.cmd" \
  --output "$TEST_ROOT/user.scr" --variant user
python3 "$ROOT/tools/render-boot-script.py" --input "$TEST_ROOT/boot.cmd" \
  --output "$TEST_ROOT/userdebug.scr" --variant userdebug
cp "$TEST_ROOT/user.scr" "$PRODUCT_OUT/boot.img"
cp "$TEST_ROOT/user.scr" "$OSS_PRODUCT_OUT/boot.img"

cat > "$MOCK_BIN/debugfs" <<'EOF'
#!/usr/bin/env bash
request=${2:-}
present=0
case "$request" in
  *vendor_sepolicy.cil*)
    if [[ ${MOCK_AUDIO_FMQ_POLICY:-good} == good ]]; then
      echo '(allow hal_audio_default tmpfs_202604 (file (read write map)))'
      echo '(allow audioserver tmpfs_202604 (file (read write map)))'
      echo '(allow system_server audioserver_tmpfs_202604 (file (read write map)))'
      echo '(allow hal_power_default hal_power_default_tmpfs (file (read write getattr map)))'
      echo '(allow system_server_202604 hal_power_default_tmpfs (file (read write getattr map)))'
    else
      echo '(allow hal_audio_default tmpfs_202604 (file (write map)))'
      echo '(allow audioserver tmpfs_202604 (file (read write map)))'
      echo '(allow system_server audioserver_tmpfs_202604 (file (read write map)))'
    fi
    exit 0
    ;;
  *'/system/build.prop'*)
    printf 'ro.build.version.incremental=%s\n' "${MOCK_SYSTEM_BUILD_ID:-OPI5.test-build}"
    exit 0
    ;;
  *'cat /build.prop'*)
    printf 'ro.vendor.build.version.incremental=%s\n' "${MOCK_VENDOR_BUILD_ID:-OPI5.test-build}"
    exit 0
    ;;
  *com.google.android.widevine*) present=${MOCK_WIDEVINE_PRESENT:-0} ;;
  *Flicky*) present=${MOCK_FLICKY_PRESENT:-1} ;;
  *YouTubeTV*) present=${MOCK_YOUTUBE_PRESENT:-1} ;;
  *GooglePhotos*) present=${MOCK_PHOTOS_PRESENT:-0} ;;
  *AndroidMediaShell*) present=${MOCK_MEDIASHELL_PRESENT:-0} ;;
  *Backdrop*) present=${MOCK_BACKDROP_PRESENT:-0} ;;
  *TvProvision*) present=${MOCK_TVPROVISION_PRESENT:-0} ;;
  *adb_keys*) present=${MOCK_ADB_KEYS_PRESENT:-0} ;;
  *logcatd*) present=${MOCK_LOGCATD_PRESENT:-0} ;;
esac
if [[ $present == 1 ]]; then
  echo 'Inode: 42   Type: regular'
else
  echo "$request: File not found by ext2_lookup"
fi
exit 0
EOF
chmod +x "$MOCK_BIN/debugfs"

cat > "$MOCK_BIN/mtype" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == -i && -f ${2:-} ]] || exit 1
cat "$2"
EOF
chmod +x "$MOCK_BIN/mtype"

cat > "$SOURCE/.repo/repo/repo" <<'EOF'
#!/usr/bin/env bash
[[ ${MOCK_REPO_FAIL:-0} != 1 ]] || exit 1
[[ ${MOCK_REPO_DIRTY:-0} != 1 ]] || printf ' M dirty-file\n'
EOF
chmod +x "$SOURCE/.repo/repo/repo"
cp "$SOURCE/.repo/repo/repo" "$OSS_SOURCE/.repo/repo/repo"

run_verifier() {
  local profile=$1 widevine=$2 variant=${3:-user} source=$SOURCE
  [[ $profile != oss ]] || source=$OSS_SOURCE
  env PATH="$MOCK_BIN:$PATH" OPI5_KERNEL_PACKAGE_DIR="$PACKAGE_DIR" \
    "$ROOT/tools/verify-release.sh" --profile "$profile" --widevine "$widevine" --variant "$variant" \
    --build-id test-build --source "$source" --kernel-out "$KERNEL_OUT"
}

# Hardened builds must not request permissive SELinux, while development builds
# retain the board's explicit diagnostic mode.
cp "$TEST_ROOT/userdebug.scr" "$PRODUCT_OUT/boot.img"
if run_verifier custom disabled user >/dev/null 2>&1; then
  echo "Permissive user image was accepted" >&2
  exit 1
fi
MOCK_ADB_KEYS_PRESENT=1 MOCK_LOGCATD_PRESENT=1 \
  run_verifier custom disabled userdebug >/dev/null
cp "$TEST_ROOT/user.scr" "$PRODUCT_OUT/boot.img"

if MOCK_ADB_KEYS_PRESENT=0 run_verifier custom disabled user >/dev/null 2>&1; then
  echo "User image without the pre-authorized ADB public key was accepted" >&2
  exit 1
fi
export MOCK_ADB_KEYS_PRESENT=1
if MOCK_VENDOR_BUILD_ID=OPI5.stale-build run_verifier custom disabled >/dev/null 2>&1; then
  echo "Stale vendor build identity was accepted" >&2
  exit 1
fi
if MOCK_AUDIO_FMQ_POLICY=bad run_verifier custom disabled >/dev/null 2>&1; then
  echo "Audio HAL policy without FMQ read access was accepted" >&2
  exit 1
fi
if MOCK_ADB_KEYS_PRESENT=1 MOCK_LOGCATD_PRESENT=1 \
    run_verifier custom disabled user >/dev/null 2>&1; then
  echo "User image containing persistent logcatd was accepted" >&2
  exit 1
fi

# debugfs returns success even for a missing path; absence must be judged by output.
MOCK_ADB_KEYS_PRESENT=1 MOCK_WIDEVINE_PRESENT=0 run_verifier custom disabled >/dev/null
if MOCK_ADB_KEYS_PRESENT=1 MOCK_WIDEVINE_PRESENT=0 run_verifier custom enabled >/dev/null 2>&1; then
  echo "Missing Widevine APEX was accepted" >&2
  exit 1
fi
MOCK_ADB_KEYS_PRESENT=1 MOCK_WIDEVINE_PRESENT=1 run_verifier custom enabled >/dev/null
if MOCK_ADB_KEYS_PRESENT=1 MOCK_WIDEVINE_PRESENT=1 run_verifier custom disabled >/dev/null 2>&1; then
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
if MOCK_MEDIASHELL_PRESENT=1 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image containing the unprovisioned Cast receiver was accepted" >&2
  exit 1
fi
if MOCK_BACKDROP_PRESENT=1 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image containing the Cast-dependent Backdrop dream was accepted" >&2
  exit 1
fi
if MOCK_TVPROVISION_PRESENT=1 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image containing a second setup wizard was accepted" >&2
  exit 1
fi
MOCK_TVPROVISION_PRESENT=1 MOCK_YOUTUBE_PRESENT=0 MOCK_PHOTOS_PRESENT=0 \
  run_verifier oss disabled >/dev/null
if MOCK_TVPROVISION_PRESENT=0 MOCK_YOUTUBE_PRESENT=0 \
    run_verifier oss disabled >/dev/null 2>&1; then
  echo "OSS image without its setup wizard was accepted" >&2
  exit 1
fi
if MOCK_TVPROVISION_PRESENT=1 MOCK_YOUTUBE_PRESENT=1 MOCK_PHOTOS_PRESENT=0 \
    run_verifier oss disabled >/dev/null 2>&1; then
  echo "OSS image containing YouTube was accepted" >&2
  exit 1
fi
if MOCK_TVPROVISION_PRESENT=1 MOCK_YOUTUBE_PRESENT=0 MOCK_PHOTOS_PRESENT=1 \
    run_verifier oss disabled >/dev/null 2>&1; then
  echo "OSS image containing Google Photos was accepted" >&2
  exit 1
fi
if MOCK_FLICKY_PRESENT=0 run_verifier custom disabled >/dev/null 2>&1; then
  echo "Custom image without Flicky was accepted" >&2
  exit 1
fi
if MOCK_TVPROVISION_PRESENT=1 MOCK_FLICKY_PRESENT=0 MOCK_YOUTUBE_PRESENT=0 \
    run_verifier oss disabled >/dev/null 2>&1; then
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
