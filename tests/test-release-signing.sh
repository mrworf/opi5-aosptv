#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/release-signing.sh"
mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/release-signing-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
SOURCE="$TEST_ROOT/source"
KEY_DIR="$TEST_ROOT/keys"
mkdir -p "$SOURCE/build/make/target/product/security" "$KEY_DIR"

GENERATOR_ROOT="$TEST_ROOT/generator"
mkdir -p "$GENERATOR_ROOT/lib"
cp "$ROOT/configure-release-signing" "$GENERATOR_ROOT/"
cp "$ROOT/lib/release-signing.sh" "$GENERATOR_ROOT/lib/"
"$GENERATOR_ROOT/configure-release-signing" >/dev/null
[[ -f $GENERATOR_ROOT/local/signing/release.conf ]]
[[ -f $GENERATOR_ROOT/local/signing/keys/platform.pk8 ]]
[[ -f $GENERATOR_ROOT/local/signing/keys/apex.pem ]]
"$GENERATOR_ROOT/configure-release-signing" >/dev/null
printf 'partial\n' > "$GENERATOR_ROOT/local/signing/keys/broken"
rm "$GENERATOR_ROOT/local/signing/release.conf"
if "$GENERATOR_ROOT/configure-release-signing" >/dev/null 2>&1; then
  echo "Signing generator overwrote partial state" >&2
  exit 1
fi

if opi5_resolve_signing_dir "$TEST_ROOT" 2>/dev/null; then
  echo "Missing signing configuration was accepted" >&2
  exit 1
fi
mkdir -p "$TEST_ROOT/local/signing"
printf 'key_dir=%s\n' "$KEY_DIR" > "$TEST_ROOT/local/signing/release.conf"
if opi5_require_release_keys "$TEST_ROOT" "$SOURCE" 2>/dev/null; then
  echo "Missing release keys were accepted" >&2
  exit 1
fi

for name in releasekey platform shared media networkstack sdk_sandbox bluetooth nfc cts_uicc_2021; do
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=$name/" \
    -keyout "$TEST_ROOT/$name.pem" -out "$KEY_DIR/$name.x509.pem" >/dev/null 2>&1
  openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
    -in "$TEST_ROOT/$name.pem" -out "$KEY_DIR/$name.pk8"
done
openssl genrsa -out "$KEY_DIR/apex.pem" 2048 >/dev/null 2>&1
opi5_require_release_keys "$TEST_ROOT" "$SOURCE"

cp "$KEY_DIR/releasekey.pk8" "$SOURCE/build/make/target/product/security/testkey.pk8"
if opi5_require_release_keys "$TEST_ROOT" "$SOURCE" 2>/dev/null; then
  echo "Stock AOSP development key was accepted" >&2
  exit 1
fi
rm "$SOURCE/build/make/target/product/security/testkey.pk8"
cp "$KEY_DIR/releasekey.pk8" "$KEY_DIR/platform.pk8"
if opi5_require_release_keys "$TEST_ROOT" "$SOURCE" 2>/dev/null; then
  echo "Mismatched key and certificate were accepted" >&2
  exit 1
fi

FAKE_SOURCE="$TEST_ROOT/sign-source"
PRODUCT_OUT="$TEST_ROOT/product-out"
SIGNED_OUT="$TEST_ROOT/signed-out"
mkdir -p "$FAKE_SOURCE/out/host/linux-x86/bin" \
  "$FAKE_SOURCE/build/make/target/product/security" \
  "$PRODUCT_OUT/obj/PACKAGING/target_files_intermediates"
for name in sdk_sandbox bluetooth nfc; do
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=stock-$name/" \
    -keyout "$TEST_ROOT/stock-$name.pem" \
    -out "$FAKE_SOURCE/build/make/target/product/security/$name.x509.pem" >/dev/null 2>&1
done
FIXTURE="$TEST_ROOT/target-files-fixture"
mkdir -p "$FIXTURE/META" "$FIXTURE/SYSTEM/etc/selinux"
{
  printf '<policy>'
  for name in sdk_sandbox bluetooth nfc; do
    cert="$FAKE_SOURCE/build/make/target/product/security/$name.x509.pem"
    hex=$(openssl x509 -in "$cert" -outform DER | od -An -vtx1 | tr -d ' \n')
    printf '<signer signature="%s"><seinfo value="%s"/></signer>' "$hex" "$name"
  done
  printf '</policy>\n'
} > "$FIXTURE/SYSTEM/etc/selinux/plat_mac_permissions.xml"
cat > "$FIXTURE/META/apkcerts.txt" <<'EOF'
name="Bluetooth.apk" certificate="packages/modules/Bluetooth/android/app/certs/com.android.bluetooth.x509.pem" private_key="packages/modules/Bluetooth/android/app/certs/com.android.bluetooth.pk8" partition="system"
name="NfcNciApex.apk" certificate="build/make/target/product/security/nfc.x509.pem" private_key="build/make/target/product/security/nfc.pk8" partition="system"
name="SdkSandbox.apk" certificate="build/make/target/product/security/sdk_sandbox.x509.pem" private_key="build/make/target/product/security/sdk_sandbox.pk8" partition="system"
EOF
(cd "$FIXTURE" && zip -qr "$PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/aosp_opi5_tv_oss-target_files.zip" META SYSTEM)
cat > "$FAKE_SOURCE/out/host/linux-x86/bin/sign_target_files_apks" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$FAKE_SIGN_ARGS"
cp "${@: -2:1}" "${@: -1}"
EOF
cat > "$FAKE_SOURCE/out/host/linux-x86/bin/img_from_target_files" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
stage="$2.files"
mkdir -p "$stage"
printf 'boot\n' > "$stage/boot.img"
printf 'system\n' > "$stage/system.img"
printf 'vendor\n' > "$stage/vendor.img"
(cd "$stage" && zip -q "$2" boot.img system.img vendor.img)
EOF
chmod +x "$FAKE_SOURCE/out/host/linux-x86/bin/sign_target_files_apks" \
  "$FAKE_SOURCE/out/host/linux-x86/bin/img_from_target_files"
FAKE_SIGN_ARGS="$TEST_ROOT/sign-args" "$ROOT/tools/sign-release-images.sh" \
  --source "$FAKE_SOURCE" --product-out "$PRODUCT_OUT" \
  --key-dir "$KEY_DIR" --output-dir "$SIGNED_OUT" >/dev/null
[[ -s $PRODUCT_OUT/boot.img && -s $PRODUCT_OUT/system.img && -s $PRODUCT_OUT/vendor.img ]]
grep -Fxq 'build/make/target/product/security/sdk_sandbox=build/make/target/product/security/sdk_sandbox' \
  "$TEST_ROOT/sign-args"
if grep -Fq "=$KEY_DIR/bluetooth" "$TEST_ROOT/sign-args" || \
    grep -Fq "=$KEY_DIR/nfc" "$TEST_ROOT/sign-args"; then
  echo "APEX-contained APK certificate was passed to the outer target-files signer" >&2
  exit 1
fi

echo "release signing tests passed"
