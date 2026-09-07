#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/flash-command-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/release"
touch "$TEST_ROOT/release/release.json"

MACHINE="$TEST_ROOT/machine.json"
jq -n \
  --arg target '/dev/disk/by-id/ata-test_disk' \
  --arg serial 'SERIAL123' \
  --argjson capacity 512110190592 \
  '{target_by_id:$target, expected_serial:$serial, expected_capacity_bytes:$capacity}' \
  > "$MACHINE"

output=$("$ROOT/tools/print-flash-command.sh" \
  --machine "$MACHINE" \
  --release-json "$TEST_ROOT/release/release.json")
[[ $output == pkexec* ]]
[[ $output == *'/tools/flash-partitions.sh '* ]]
[[ $output == *'--target /dev/disk/by-id/ata-test_disk '* ]]
[[ $output == *'--expected-serial SERIAL123 '* ]]
[[ $output == *'--expected-capacity 512110190592 '* ]]
[[ $output != *'--product-out'* ]]

output=$($ROOT/tools/print-flash-command.sh \
  --machine "$MACHINE" \
  --release-json "$TEST_ROOT/release/release.json" \
  --clear-data)
[[ $output == *'--clear-data '* ]]

jq -n --arg target '/dev/disk/by-id/ata-unpinned' '{target_by_id:$target}' > "$MACHINE"
output=$("$ROOT/tools/print-flash-command.sh" --machine "$MACHINE" --release-json "$TEST_ROOT/release/release.json")
[[ $output == *'--target /dev/disk/by-id/ata-unpinned '* ]]
[[ $output != *'--expected-serial'* ]]
[[ $output != *'--expected-capacity'* ]]

jq -n --arg target '/dev/sdc' '{target:$target}' > "$MACHINE"
output=$("$ROOT/tools/print-flash-command.sh" --machine "$MACHINE" --release-json "$TEST_ROOT/release/release.json")
[[ $output == *'--target /dev/sdc '* ]]

grep -q 'blockdev --getsize64' "$ROOT/tools/flash-partitions.sh"
grep -q 'valid metadata and userdata are preserved' "$ROOT/tools/flash-partitions.sh"
grep -q 'sha256sum --check --strict' "$ROOT/tools/flash-partitions.sh"
grep -q 'confirm CLEAR-DATA' "$ROOT/tools/flash-partitions.sh"
grep -q 'confirm REPARTITION' "$ROOT/tools/flash-partitions.sh"
grep -q 'confirm RESTORE' "$ROOT/tools/flash-partitions.sh"
grep -q 'e2image -rap' "$ROOT/tools/flash-partitions.sh"
grep -q 'data_filesystems_valid' "$ROOT/tools/flash-partitions.sh"
grep -q 'Metadata or userdata is not valid ext4' "$ROOT/tools/flash-partitions.sh"

echo "flash command tests passed"
