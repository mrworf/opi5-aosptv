#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/disk-layout.sh"

[[ $(opi5_partition_path /dev/sdc 1) == /dev/sdc1 ]]
[[ $(opi5_partition_path /dev/nvme0n1 2) == /dev/nvme0n1p2 ]]
[[ $(opi5_partition_path /dev/mmcblk0 5) == /dev/mmcblk0p5 ]]
[[ $(opi5_partition_path /dev/loop7 4) == /dev/loop7p4 ]]

layout=$(opi5_emit_sfdisk_layout /dev/test)
grep -q '^start=32768, size=262144' <<<"$layout"
grep -q '^start=303104, size=6291456' <<<"$layout"
grep -q '^start=6596608, size=786432' <<<"$layout"
grep -q '^start=7385088, size=32768' <<<"$layout"
grep -q '^start=7417856' <<<"$layout"
grep -q 'opi5_emit_sfdisk_layout' "$ROOT/tools/assemble-image.sh"
grep -q 'opi5_emit_sfdisk_layout' "$ROOT/tools/flash-partitions.sh"

mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/disk-layout-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
image="$TEST_ROOT/test.img"
truncate -s 5G "$image"
opi5_emit_sfdisk_layout "$image" | sfdisk "$image" >/dev/null
table=$(sfdisk --json "$image")
opi5_layout_json_valid "$table"

for mutation in \
    '.partitiontable.partitions[0].name = "wrong"' \
    '.partitiontable.partitions[0].type = "0FC63DAF-8483-4772-8E79-3D69D8477DE4"' \
    '.partitiontable.partitions[2].start += 1' \
    '.partitiontable.partitions[4].size -= 2048' \
    'del(.partitiontable.partitions[4])'; do
  invalid=$(jq "$mutation" <<<"$table")
  if opi5_layout_json_valid "$invalid"; then
    echo "Invalid disk layout was accepted: $mutation" >&2
    exit 1
  fi
done

echo "disk layout tests passed"
