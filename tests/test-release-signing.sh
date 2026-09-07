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

echo "release signing tests passed"
