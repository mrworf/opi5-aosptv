#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/disk-layout.sh"

PRODUCT_OUT=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --product-out) PRODUCT_OUT=${2:-}; shift 2 ;;
    *) echo "Usage: $0 --product-out PATH" >&2; exit 2 ;;
  esac
done
[[ -n $PRODUCT_OUT ]] || { echo "Missing --product-out" >&2; exit 2; }
for tool in fallocate sfdisk dd mkfs.ext4 sgdisk sha256sum jq; do
  command -v "$tool" >/dev/null || { echo "Missing host tool: $tool" >&2; exit 2; }
done
for part in boot system vendor; do
  [[ -f "$PRODUCT_OUT/$part.img" ]] || { echo "Missing $PRODUCT_OUT/$part.img" >&2; exit 2; }
done
UBOOT=${OPI5_KERNEL_PACKAGE_DIR:?}/u-boot-rockchip.bin
[[ -f $UBOOT ]] || { echo "Missing $UBOOT" >&2; exit 2; }

profile=${OPI5_BUILD_PROFILE:-unknown}
widevine=${OPI5_ENABLE_WIDEVINE:-false}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
IMAGE=${OPI5_IMAGE_PATH:-$PRODUCT_OUT/OrangePi_5-Android17-TV-${profile}-widevine-${widevine}-${stamp}.img}
[[ ! -e $IMAGE ]] || { echo "Refusing to overwrite $IMAGE" >&2; exit 2; }
fallocate -l 19456MiB "$IMAGE"
opi5_emit_sfdisk_layout "$IMAGE" | sfdisk "$IMAGE"
for spec in "boot:$OPI5_BOOT_SIZE" "system:$OPI5_SYSTEM_SIZE" "vendor:$OPI5_VENDOR_SIZE"; do
  name=${spec%%:*}; sectors=${spec#*:}; bytes=$(stat -c %s "$PRODUCT_OUT/$name.img")
  (( bytes <= sectors * 512 )) || { echo "$name.img exceeds its partition" >&2; exit 2; }
done
dd if="$UBOOT" of="$IMAGE" bs="$OPI5_SECTOR_SIZE" seek="$OPI5_UBOOT_SEEK" conv=notrunc status=progress
dd if="$PRODUCT_OUT/boot.img" of="$IMAGE" bs="$OPI5_SECTOR_SIZE" seek="$OPI5_BOOT_START" conv=notrunc status=progress
dd if="$PRODUCT_OUT/system.img" of="$IMAGE" bs="$OPI5_SECTOR_SIZE" seek="$OPI5_SYSTEM_START" conv=notrunc status=progress
dd if="$PRODUCT_OUT/vendor.img" of="$IMAGE" bs="$OPI5_SECTOR_SIZE" seek="$OPI5_VENDOR_START" conv=notrunc status=progress
value() { sfdisk --json "$IMAGE" | jq -er --arg n "$1" --arg f "$2" '.partitiontable.partitions[]|select(.name==$n)|.[$f]'; }
ms=$(value metadata start); mz=$(value metadata size)
us=$(value userdata start); uz=$(value userdata size)
mkfs.ext4 -q -F -b 4096 -L metadata -E "offset=$((ms*OPI5_SECTOR_SIZE))" "$IMAGE" "$((mz/8))"
mkfs.ext4 -q -F -b 4096 -L userdata -E "offset=$((us*OPI5_SECTOR_SIZE))" "$IMAGE" "$((uz/8))"
sgdisk -v "$IMAGE"
sha256sum "$IMAGE" > "$IMAGE.sha256"
echo "$IMAGE"
