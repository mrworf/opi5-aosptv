#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/disk-layout.sh"

MODE=flash
TARGET= EXPECTED_SERIAL= EXPECTED_CAPACITY= RELEASE_JSON= BACKUP=
BACKUP_ROOT="$ROOT/backups"
BACKUP_BEFORE_FLASH=false
CLEAR_DATA=false

usage() {
  printf '%s\n' \
    "Usage: $0 --target /dev/sdX-or-/dev/disk/by-id/ID [options]" \
    '' \
    'Modes:' \
    '  --mode flash       Flash boot/system/vendor (default)' \
    '  --mode backup      Back up GPT, metadata, and userdata only' \
    '  --mode restore     Restore --backup PATH' \
    '  --mode clear       Reformat metadata and userdata only' \
    '' \
    'Flash options:' \
    '  --release-json PATH       Required for flash mode' \
    '  --backup-before-flash     Complete and verify a backup first' \
    '  --clear-data              Clear data after flashing' \
    '' \
    'Safety and backup options:' \
    '  --expected-serial SERIAL' \
    '  --expected-capacity BYTES' \
    '  --backup-root PATH        Default: workspace backups/' \
    '  --backup PATH             Backup directory for restore mode'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE=${2:-}; shift 2 ;;
    --target) TARGET=${2:-}; shift 2 ;;
    --expected-serial) EXPECTED_SERIAL=${2:-}; shift 2 ;;
    --expected-capacity) EXPECTED_CAPACITY=${2:-}; shift 2 ;;
    --release-json) RELEASE_JSON=${2:-}; shift 2 ;;
    --backup-root) BACKUP_ROOT=${2:-}; shift 2 ;;
    --backup) BACKUP=${2:-}; shift 2 ;;
    --backup-before-flash) BACKUP_BEFORE_FLASH=true; shift ;;
    --clear-data) CLEAR_DATA=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_tool() { command -v "$1" >/dev/null || die "Missing host tool: $1"; }
confirm() {
  local token=$1 prompt=$2 reply
  [[ -r /dev/tty ]] || die "Confirmation requires an interactive terminal"
  printf '%s\nType %s to continue: ' "$prompt" "$token" >/dev/tty
  IFS= read -r reply </dev/tty || die "Unable to read confirmation"
  [[ $reply == "$token" ]] || die "Confirmation declined"
}

[[ $MODE == flash || $MODE == backup || $MODE == restore || $MODE == clear ]] || die "Unsupported mode: $MODE"
[[ -n $TARGET ]] || die "Missing --target"
[[ $(id -u) -eq 0 ]] || die "This script must run as root through pkexec"
[[ $TARGET == /dev/* ]] || die "Target must be a device path under /dev"
[[ -b $TARGET ]] || die "$TARGET is not a block device"
[[ -z $EXPECTED_CAPACITY || $EXPECTED_CAPACITY =~ ^[1-9][0-9]*$ ]] || die "Expected capacity is invalid"
[[ $MODE == flash || $BACKUP_BEFORE_FLASH == false ]] || die "--backup-before-flash is only valid in flash mode"
[[ $MODE == flash || $CLEAR_DATA == false ]] || die "--clear-data is only valid in flash mode; use --mode clear"
[[ $MODE != restore || -n $BACKUP ]] || die "Restore mode requires --backup PATH"
[[ $MODE == restore || -z $BACKUP ]] || die "--backup is only valid in restore mode"

for tool in awk blkid blockdev dd findmnt grep id jq lsblk readlink sed sfdisk stat udevadm umount; do require_tool "$tool"; done

RESOLVED_TARGET=$(readlink -f "$TARGET")
[[ -b $RESOLVED_TARGET ]] || die "Target symlink does not resolve to a block device"
TARGET_TYPE=$(lsblk -dno TYPE "$RESOLVED_TARGET")
[[ $TARGET_TYPE == disk || $TARGET_TYPE == loop ]] || die "Target must be a whole disk"
ROOT_SOURCE=$(findmnt -nro SOURCE /)
if [[ $ROOT_SOURCE == /dev/* ]] && lsblk -srnpo NAME "$ROOT_SOURCE" | grep -Fxq "$RESOLVED_TARGET"; then
  die "Refusing to operate on the disk backing the host root filesystem"
fi

property() {
  local key=$1
  udevadm info --query=property --name="$TARGET" 2>/dev/null \
    | awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); value=$0} END {print value}'
}
MODEL=$(property ID_MODEL)
SERIAL=$(property ID_SERIAL_SHORT)
[[ -n $MODEL ]] || MODEL=$(lsblk -dno MODEL "$RESOLVED_TARGET" | sed 's/[[:space:]]*$//')
[[ -n $SERIAL ]] || SERIAL=$(lsblk -dno SERIAL "$RESOLVED_TARGET" | sed 's/[[:space:]]*$//')
CAPACITY=$(blockdev --getsize64 "$TARGET")
LOGICAL_SECTOR=$(blockdev --getss "$TARGET")
[[ $LOGICAL_SECTOR -eq $OPI5_SECTOR_SIZE ]] || die "Unsupported logical sector size: $LOGICAL_SECTOR (expected $OPI5_SECTOR_SIZE)"

# Capacity failure must precede confirmation, hashing, unmounting, and writes.
if [[ $MODE == flash ]]; then
  [[ -n $RELEASE_JSON && -f $RELEASE_JSON ]] || die "Flash mode requires --release-json PATH"
  jq -e '.schema == "opi5-release-v2"' "$RELEASE_JSON" >/dev/null || die "Flash requires opi5-release-v2 metadata"
  MINIMUM_CAPACITY=$(jq -er '.artifacts.disk_image.size' "$RELEASE_JSON") || die "Release metadata lacks disk image size"
  (( CAPACITY >= MINIMUM_CAPACITY )) || die "Target is too small: $CAPACITY bytes; release requires $MINIMUM_CAPACITY bytes"
fi

[[ -z $EXPECTED_SERIAL || $SERIAL == "$EXPECTED_SERIAL" ]] || die "$TARGET serial '$SERIAL' does not match '$EXPECTED_SERIAL'"
[[ -z $EXPECTED_CAPACITY || $CAPACITY -eq $EXPECTED_CAPACITY ]] || die "$TARGET capacity $CAPACITY does not match $EXPECTED_CAPACITY bytes"

if [[ -z $EXPECTED_SERIAL || -z $EXPECTED_CAPACITY ]]; then
  HUMAN_SIZE=$(lsblk -dno SIZE "$RESOLVED_TARGET" | tr -d ' ')
  printf 'Target identity is not fully pinned:\n'
  printf '  Target path: %s\n  Device:      %s\n  Model:       %s\n' "$TARGET" "$RESOLVED_TARGET" "${MODEL:-unknown}"
  printf '  Serial:      %s\n  Capacity:    %s (%s bytes)\n' "${SERIAL:-unknown}" "$HUMAN_SIZE" "$CAPACITY"
  confirm CONTINUE "Verify that this is the Orange Pi target disk."
fi

partition_path() { opi5_partition_path "$RESOLVED_TARGET" "$1"; }
BOOT_PARTITION=$(partition_path 1)
SYSTEM_PARTITION=$(partition_path 2)
VENDOR_PARTITION=$(partition_path 3)
METADATA_PARTITION=$(partition_path 4)
USERDATA_PARTITION=$(partition_path 5)

layout_valid() {
  local table
  table=$(sfdisk --json "$TARGET" 2>/dev/null) || return 1
  opi5_layout_json_valid "$table"
}

require_data_layout() {
  layout_valid || die "A compatible GPT with metadata and userdata is required for this operation"
  for partition in "$METADATA_PARTITION" "$USERDATA_PARTITION"; do [[ -b $partition ]] || die "Missing data partition: $partition"; done
}

data_filesystems_valid() {
  [[ $(blkid -s TYPE -o value "$METADATA_PARTITION" 2>/dev/null) == ext4 ]] &&
    [[ $(blkid -s TYPE -o value "$USERDATA_PARTITION" 2>/dev/null) == ext4 ]]
}

unmount_target() {
  local partition
  while IFS= read -r partition; do
    [[ $partition == "$RESOLVED_TARGET" ]] && continue
    umount "$partition" 2>/dev/null || true
  done < <(lsblk -nrpo NAME "$RESOLVED_TARGET")
}

owner_of_invocation() {
  local path=$1 uid gid
  uid=${PKEXEC_UID:-}
  [[ $uid =~ ^[0-9]+$ ]] || return 0
  gid=$(id -g "$uid")
  chown -R "$uid:$gid" "$path"
}

create_backup() {
  require_data_layout
  for tool in awk chown date df e2image sha256sum sgdisk tail tr tune2fs; do require_tool "$tool"; done
  unmount_target
  BACKUP_ROOT=$(readlink -m "$BACKUP_ROOT")
  [[ $BACKUP_ROOT != /tmp && $BACKUP_ROOT != /tmp/* ]] || die "Backups must not be stored under /tmp"
  mkdir -p "$BACKUP_ROOT"
  local stamp final partial available block_count free_blocks block_size estimate metadata_size userdata_size
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  final="$BACKUP_ROOT/opi5-data-$stamp"
  partial="$final.partial"
  [[ ! -e $final && ! -e $partial ]] || die "Backup destination already exists"
  mkdir -p "$partial"
  block_count=$(tune2fs -l "$USERDATA_PARTITION" | awk -F: '/^Block count:/ {gsub(/ /,"",$2); print $2}')
  free_blocks=$(tune2fs -l "$USERDATA_PARTITION" | awk -F: '/^Free blocks:/ {gsub(/ /,"",$2); print $2}')
  block_size=$(tune2fs -l "$USERDATA_PARTITION" | awk -F: '/^Block size:/ {gsub(/ /,"",$2); print $2}')
  [[ $block_count =~ ^[0-9]+$ && $free_blocks =~ ^[0-9]+$ && $block_size =~ ^[0-9]+$ ]] || die "Unable to estimate userdata backup size"
  estimate=$(( ((block_count - free_blocks) * block_size * 110) / 100 + OPI5_METADATA_SIZE * OPI5_SECTOR_SIZE + 64 * 1024 * 1024 ))
  available=$(df --output=avail -B1 "$BACKUP_ROOT" | tail -n 1 | tr -d ' ')
  (( available >= estimate )) || die "Backup destination needs approximately $estimate bytes; only $available available"
  printf 'Backing up partition table, metadata, and userdata to %s\n' "$final"
  sgdisk --backup="$partial/partition-table.gpt" "$TARGET"
  sfdisk --dump "$TARGET" > "$partial/partition-table.sfdisk"
  dd if="$METADATA_PARTITION" of="$partial/metadata.raw.img" bs=4M iflag=fullblock conv=sparse status=progress
  e2image -rap "$USERDATA_PARTITION" "$partial/userdata.raw.img"
  (cd "$partial" && sha256sum partition-table.gpt partition-table.sfdisk metadata.raw.img userdata.raw.img > SHA256SUMS)
  (cd "$partial" && sha256sum --check --strict SHA256SUMS)
  metadata_size=$(blockdev --getsize64 "$METADATA_PARTITION")
  userdata_size=$(blockdev --getsize64 "$USERDATA_PARTITION")
  jq -n --arg schema opi5-data-backup-v1 --arg created_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg target "$TARGET" --arg resolved_device "$RESOLVED_TARGET" --arg model "${MODEL:-}" --arg serial "${SERIAL:-}" \
    --argjson capacity "$CAPACITY" --argjson sector_size "$LOGICAL_SECTOR" \
    --argjson metadata_size "$metadata_size" --argjson userdata_size "$userdata_size" \
    '{schema:$schema,created_utc:$created_utc,device:{target:$target,target_by_id:(if ($target | startswith("/dev/disk/by-id/")) then $target else null end),resolved_device:$resolved_device,model:$model,serial:$serial,capacity_bytes:$capacity,logical_sector_size:$sector_size},partitions:{metadata:{number:4,size_bytes:$metadata_size,image:"metadata.raw.img"},userdata:{number:5,size_bytes:$userdata_size,image:"userdata.raw.img"}},gpt:"partition-table.gpt",checksums:"SHA256SUMS"}' > "$partial/backup.json"
  mv "$partial" "$final"
  owner_of_invocation "$final"
  printf 'Backup completed and verified: %s\n' "$final"
}

clear_data_partitions() {
  require_tool mkfs.ext4
  require_data_layout
  unmount_target
  mkfs.ext4 -q -F -b 4096 -L metadata "$METADATA_PARTITION"
  mkfs.ext4 -q -F -b 4096 -L userdata "$USERDATA_PARTITION"
  printf 'Metadata and userdata were cleared atomically.\n'
}

restore_backup() {
  for tool in cmp e2fsck partprobe sha256sum sgdisk sync; do require_tool "$tool"; done
  BACKUP=$(readlink -f "$BACKUP")
  [[ -d $BACKUP && -f $BACKUP/backup.json && -f $BACKUP/SHA256SUMS ]] || die "Invalid backup directory: $BACKUP"
  jq -e '.schema == "opi5-data-backup-v1"' "$BACKUP/backup.json" >/dev/null || die "Unsupported backup manifest"
  (cd "$BACKUP" && sha256sum --check --strict SHA256SUMS)
  local saved_capacity saved_sector saved_serial metadata_size userdata_size
  saved_capacity=$(jq -er '.device.capacity_bytes' "$BACKUP/backup.json")
  saved_sector=$(jq -er '.device.logical_sector_size' "$BACKUP/backup.json")
  saved_serial=$(jq -er '.device.serial' "$BACKUP/backup.json")
  [[ $CAPACITY -eq $saved_capacity && $LOGICAL_SECTOR -eq $saved_sector ]] || die "Backup disk geometry does not match the target"
  [[ -z $saved_serial || $SERIAL == "$saved_serial" ]] || die "Backup belongs to serial '$saved_serial', not '$SERIAL'"
  confirm RESTORE "This will overwrite the target GPT, metadata, and userdata from $BACKUP."
  unmount_target
  sgdisk --load-backup="$BACKUP/partition-table.gpt" "$TARGET"
  partprobe "$TARGET"
  udevadm settle
  require_data_layout
  metadata_size=$(jq -er '.partitions.metadata.size_bytes' "$BACKUP/backup.json")
  userdata_size=$(jq -er '.partitions.userdata.size_bytes' "$BACKUP/backup.json")
  [[ $(blockdev --getsize64 "$METADATA_PARTITION") -eq $metadata_size ]] || die "Restored metadata partition size is incompatible"
  [[ $(blockdev --getsize64 "$USERDATA_PARTITION") -eq $userdata_size ]] || die "Restored userdata partition size is incompatible"
  dd if="$BACKUP/metadata.raw.img" of="$METADATA_PARTITION" bs=4M iflag=fullblock conv=fsync status=progress
  dd if="$BACKUP/userdata.raw.img" of="$USERDATA_PARTITION" bs=16M iflag=fullblock conv=fsync status=progress
  sync
  cmp -n "$metadata_size" "$BACKUP/metadata.raw.img" "$METADATA_PARTITION"
  cmp -n "$userdata_size" "$BACKUP/userdata.raw.img" "$USERDATA_PARTITION"
  e2fsck -fn "$METADATA_PARTITION"
  e2fsck -fn "$USERDATA_PARTITION"
  printf 'GPT, metadata, and userdata restore completed and verified.\n'
}

artifact_path() {
  local name=$1 relative resolved
  relative=$(jq -er --arg name "$name" '.artifacts[$name].path' "$RELEASE_JSON") || die "Release metadata lacks the $name artifact path"
  [[ $relative != /* ]] || die "Release artifact path must be workspace-relative: $relative"
  resolved=$(readlink -m "$ROOT/$relative")
  [[ $resolved == "$ROOT/"* ]] || die "Release artifact escapes the workspace: $relative"
  printf '%s' "$resolved"
}

verify_artifact() {
  local name=$1 path=$2 expected expected_size actual_size
  require_tool sha256sum
  expected=$(jq -er --arg name "$name" '.artifacts[$name].sha256' "$RELEASE_JSON") || die "Release metadata lacks the $name hash"
  expected_size=$(jq -er --arg name "$name" '.artifacts[$name].size' "$RELEASE_JSON") || die "Release metadata lacks the $name size"
  [[ -f $path ]] || die "Missing image: $path"
  actual_size=$(stat -c %s "$path")
  [[ $actual_size -eq $expected_size ]] || die "$name size does not match release metadata"
  printf '%s  %s\n' "$expected" "$path" | sha256sum --check --strict
}

repartition_target() {
  local uboot=$1
  require_tool partprobe
  unmount_target
  opi5_emit_sfdisk_layout "$RESOLVED_TARGET" | sfdisk --wipe always "$TARGET"
  partprobe "$TARGET"
  udevadm settle
  layout_valid || die "New partition layout did not validate"
  dd if="$uboot" of="$TARGET" bs="$OPI5_SECTOR_SIZE" seek="$OPI5_UBOOT_SEEK" conv=fsync,notrunc status=progress
  clear_data_partitions
}

case "$MODE" in
  backup) create_backup; exit 0 ;;
  restore) restore_backup; exit 0 ;;
  clear)
    require_data_layout
    confirm CLEAR-DATA "This permanently erases Android metadata and userdata on $TARGET."
    clear_data_partitions
    exit 0
    ;;
esac

UBOOT=$(artifact_path uboot)
BOOT_IMAGE=$(artifact_path boot)
SYSTEM_IMAGE=$(artifact_path system)
VENDOR_IMAGE=$(artifact_path vendor)
verify_artifact uboot "$UBOOT"
verify_artifact boot "$BOOT_IMAGE"
verify_artifact system "$SYSTEM_IMAGE"
verify_artifact vendor "$VENDOR_IMAGE"
(( $(stat -c %s "$UBOOT") <= (OPI5_BOOT_START - OPI5_UBOOT_SEEK) * OPI5_SECTOR_SIZE )) \
  || die "U-Boot image would overlap the boot partition"

for spec in "$OPI5_BOOT_SIZE:$BOOT_IMAGE:boot" "$OPI5_SYSTEM_SIZE:$SYSTEM_IMAGE:system" "$OPI5_VENDOR_SIZE:$VENDOR_IMAGE:vendor"; do
  sectors=${spec%%:*}; remainder=${spec#*:}; image=${remainder%%:*}; name=${remainder##*:}
  (( $(stat -c %s "$image") <= sectors * OPI5_SECTOR_SIZE )) || die "$name image exceeds its canonical partition"
done

HAS_VALID_LAYOUT=false
layout_valid && HAS_VALID_LAYOUT=true
if [[ $BACKUP_BEFORE_FLASH == true && $HAS_VALID_LAYOUT == false ]]; then
  die "Cannot make a trustworthy pre-flash backup because the partition layout is incompatible"
fi
REPARTITIONED=false
if [[ $HAS_VALID_LAYOUT == true ]]; then
  require_data_layout
  if [[ $BACKUP_BEFORE_FLASH == true ]] && ! data_filesystems_valid; then
    die "Cannot make a filesystem-aware backup because metadata or userdata is not valid ext4"
  fi
  if [[ $BACKUP_BEFORE_FLASH == true ]]; then create_backup; fi
  if ! data_filesystems_valid; then
    printf 'Metadata or userdata is not valid ext4 and cannot be preserved safely.\n' >&2
    CLEAR_DATA=true
  fi
  if [[ $CLEAR_DATA == true ]]; then
    confirm CLEAR-DATA "Flashing will also permanently erase Android metadata and userdata on $TARGET."
  fi
fi
if [[ $HAS_VALID_LAYOUT == false ]]; then
  printf 'Current partition layout is missing or incompatible:\n' >&2
  sfdisk --dump "$TARGET" >&2 2>/dev/null || printf '  No readable partition table\n' >&2
  confirm REPARTITION "The target must be repartitioned; all existing data will be erased."
  repartition_target "$UBOOT"
  REPARTITIONED=true
fi

for partition in "$BOOT_PARTITION" "$SYSTEM_PARTITION" "$VENDOR_PARTITION"; do [[ -b $partition ]] || die "Missing partition after layout validation: $partition"; done
unmount_target
if [[ $REPARTITIONED == true ]]; then
  printf 'Writing boot, system, and vendor; metadata and userdata were freshly initialized.\n'
elif [[ $CLEAR_DATA == true ]]; then
  printf 'Writing boot, system, and vendor; metadata and userdata will be cleared.\n'
else
  printf 'Writing boot, system, and vendor; valid metadata and userdata are preserved.\n'
fi
dd if="$BOOT_IMAGE" of="$BOOT_PARTITION" bs=16M iflag=fullblock conv=fsync,notrunc status=progress
dd if="$SYSTEM_IMAGE" of="$SYSTEM_PARTITION" bs=16M iflag=fullblock conv=fsync,notrunc status=progress
dd if="$VENDOR_IMAGE" of="$VENDOR_PARTITION" bs=16M iflag=fullblock conv=fsync,notrunc status=progress
sync
require_tool cmp
require_tool e2fsck
cmp -n "$(stat -c %s "$BOOT_IMAGE")" "$BOOT_IMAGE" "$BOOT_PARTITION"
cmp -n "$(stat -c %s "$SYSTEM_IMAGE")" "$SYSTEM_IMAGE" "$SYSTEM_PARTITION"
cmp -n "$(stat -c %s "$VENDOR_IMAGE")" "$VENDOR_IMAGE" "$VENDOR_PARTITION"
e2fsck -fn "$SYSTEM_PARTITION"
e2fsck -fn "$VENDOR_PARTITION"
if [[ $CLEAR_DATA == true && $REPARTITIONED == false ]]; then clear_data_partitions; fi
printf 'Boot/system/vendor flash and read-back verification completed.\n'
