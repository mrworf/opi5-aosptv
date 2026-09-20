#!/usr/bin/env bash
set -euo pipefail

SOURCE= KEY_DIR= TARGET_FILES=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE=${2:-}; shift 2 ;;
    --key-dir) KEY_DIR=${2:-}; shift 2 ;;
    --target-files) TARGET_FILES=${2:-}; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
for value in SOURCE KEY_DIR TARGET_FILES; do
  [[ -n ${!value} ]] || { echo "Missing signed-target verification option" >&2; exit 2; }
done
for tool in openssl unzip; do
  command -v "$tool" >/dev/null || { echo "Missing host tool: $tool" >&2; exit 2; }
done
[[ -f $TARGET_FILES ]] || { echo "Missing signed target-files archive: $TARGET_FILES" >&2; exit 2; }

certificate_hex() {
  openssl x509 -in "$1" -outform DER | od -An -vtx1 | tr -d ' \n'
}

policy=$(unzip -p "$TARGET_FILES" SYSTEM/etc/selinux/plat_mac_permissions.xml)
apkcerts=$(unzip -p "$TARGET_FILES" META/apkcerts.txt)

# sign_target_files_apks cannot re-sign APKs nested inside APEX payloads. Their
# SELinux signer entries must therefore retain the certificates used when the
# APEX was built, rather than being rewritten to unrelated local release keys.
for name in sdk_sandbox bluetooth nfc; do
  stock="$SOURCE/build/make/target/product/security/$name.x509.pem"
  [[ -s $stock ]] || { echo "Missing AOSP $name certificate: $stock" >&2; exit 2; }
  stock_hex=$(certificate_hex "$stock")
  release_hex=$(certificate_hex "$KEY_DIR/$name.x509.pem")
  [[ $policy == *"$stock_hex"* ]] || {
    echo "Signed SELinux policy lost the packaged $name certificate" >&2
    exit 2
  }
  [[ $policy != *"$release_hex"* ]] || {
    echo "Signed SELinux policy falsely maps APEX-contained $name to a release certificate" >&2
    exit 2
  }
done

[[ $apkcerts == *'name="SdkSandbox.apk" certificate="build/make/target/product/security/sdk_sandbox.x509.pem"'* ]] || {
  echo "SdkSandbox certificate metadata was unexpectedly rewritten" >&2; exit 2;
}
[[ $apkcerts == *'name="NfcNciApex.apk" certificate="build/make/target/product/security/nfc.x509.pem"'* ]] || {
  echo "NFC certificate metadata was unexpectedly rewritten" >&2; exit 2;
}
[[ $apkcerts == *'name="Bluetooth.apk" certificate="packages/modules/Bluetooth/android/app/certs/com.android.bluetooth.x509.pem"'* ]] || {
  echo "Bluetooth certificate metadata was unexpectedly rewritten" >&2; exit 2;
}

echo "signed target-files certificate policy verified"
