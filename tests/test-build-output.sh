#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/build-output.sh"

SOURCE="$ROOT/.state/output-fixture"
OUT_DIR=unexpected-inherited-output
opi5_configure_output_tree "$SOURCE" userdebug
[[ $OUT_DIR == out/userdebug ]]
[[ $OPI5_ANDROID_OUT == "$SOURCE/out/userdebug" ]]
[[ $OPI5_PRODUCT_OUT == "$SOURCE/out/userdebug/target/product/opi5_pro" ]]
debug_out=$OPI5_ANDROID_OUT

opi5_configure_output_tree "$SOURCE" user
[[ $OUT_DIR == out/user && $OPI5_ANDROID_OUT != "$debug_out" ]]
[[ $OPI5_PRODUCT_OUT == "$SOURCE/out/user/target/product/opi5_pro" ]]
if opi5_configure_output_tree "$SOURCE" invalid >/dev/null 2>&1; then
  echo "Invalid output variant was accepted" >&2
  exit 1
fi
[[ $OUT_DIR == out/user ]]
echo "variant output tests passed"
