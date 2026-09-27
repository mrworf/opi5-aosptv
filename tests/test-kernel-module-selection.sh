#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/.state"
TEST_OUT=$(mktemp -d "$ROOT/.state/kernel-module-test.XXXXXX")
trap 'rm -rf -- "$TEST_OUT"' EXIT
mkdir -p "$TEST_OUT/drivers/usb"
printf '%s\n' drivers/usb/uvcvideo.o > "$TEST_OUT/modules.order"
touch "$TEST_OUT/drivers/usb/uvcvideo.ko" "$TEST_OUT/drivers/usb/stale.ko"

"$ROOT/tools/write-kernel-module-list.sh" "$TEST_OUT" >/dev/null
[[ $(cat "$TEST_OUT/opi5-modules.list") == "$TEST_OUT/drivers/usb/uvcvideo.ko" ]]

printf '%s\n' drivers/usb/missing.o >> "$TEST_OUT/modules.order"
if "$ROOT/tools/write-kernel-module-list.sh" "$TEST_OUT" >/dev/null 2>&1; then
  echo "Missing current module was accepted" >&2
  exit 1
fi
echo "kernel module selection tests passed"
