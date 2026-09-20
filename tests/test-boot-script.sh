#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "$ROOT/.state/test-boot-script.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/boot.cmd" <<'EOF'
if test "${recovery}" = "true"; then
    setenv recovery_bootargs "androidboot.boot_device=${boot_device}"
else
    setenv recovery_bootargs ""
fi
setenv bootargs "${recovery_bootargs} androidboot.hardware=opi5 androidboot.selinux=permissive"
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
EOF

for variant in user userdebug; do
  python3 "$ROOT/tools/render-boot-script.py" \
    --input "$WORK/boot.cmd" --output "$WORK/$variant.scr" --variant "$variant"
  python3 "$ROOT/tools/verify-boot-script.py" \
    --input "$WORK/$variant.scr" --variant "$variant"
done

python3 - "$WORK/user.scr" <<'PY'
import struct
import sys
from pathlib import Path

image = Path(sys.argv[1]).read_bytes()
data_size = struct.unpack_from(">I", image, 12)[0]
script_size, terminator = struct.unpack_from(">II", image, 64)
assert terminator == 0
assert script_size == data_size - 8 == len(image) - 72
PY

cp "$WORK/user.scr" "$WORK/corrupt.scr"
printf '\001' | dd of="$WORK/corrupt.scr" bs=1 seek=80 conv=notrunc status=none
if python3 "$ROOT/tools/verify-boot-script.py" \
    --input "$WORK/corrupt.scr" --variant user 2>/dev/null; then
  echo "corrupt boot script unexpectedly passed verification" >&2
  exit 1
fi

echo "boot script tests passed"
