#!/usr/bin/env bash

# Canonical Orange Pi 5 on-disk layout. The final userdata partition consumes
# the remaining usable space, so the same definition works across NVMe sizes.
OPI5_SECTOR_SIZE=512
OPI5_ALIGNMENT_SECTORS=2048
OPI5_UBOOT_SEEK=64
OPI5_BOOT_START=32768
OPI5_BOOT_SIZE=262144
OPI5_SYSTEM_START=303104
OPI5_SYSTEM_SIZE=6291456
OPI5_VENDOR_START=6596608
OPI5_VENDOR_SIZE=786432
OPI5_METADATA_START=7385088
OPI5_METADATA_SIZE=32768
OPI5_USERDATA_START=7417856
OPI5_EFI_GUID=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
OPI5_LINUX_GUID=0FC63DAF-8483-4772-8E79-3D69D8477DE4

opi5_partition_path() {
  local disk=$1 number=$2
  if [[ $disk =~ [0-9]$ ]]; then
    printf '%sp%s' "$disk" "$number"
  else
    printf '%s%s' "$disk" "$number"
  fi
}

opi5_emit_sfdisk_layout() {
  # The optional argument is retained for callers, but node names are omitted.
  # This makes the same script correct for images, sdX, and nvmeXnY devices.
  : "${1:-}"
  printf '%s\n' \
    'label: gpt' \
    'unit: sectors' \
    '' \
    "start=${OPI5_BOOT_START}, size=${OPI5_BOOT_SIZE}, type=${OPI5_EFI_GUID}, name=\"boot\"" \
    "start=${OPI5_SYSTEM_START}, size=${OPI5_SYSTEM_SIZE}, type=${OPI5_LINUX_GUID}, name=\"system\"" \
    "start=${OPI5_VENDOR_START}, size=${OPI5_VENDOR_SIZE}, type=${OPI5_LINUX_GUID}, name=\"vendor\"" \
    "start=${OPI5_METADATA_START}, size=${OPI5_METADATA_SIZE}, type=${OPI5_LINUX_GUID}, name=\"metadata\"" \
    "start=${OPI5_USERDATA_START}, type=${OPI5_LINUX_GUID}, name=\"userdata\""
}

opi5_layout_json_valid() {
  local table=$1
  jq -e --argjson sector "$OPI5_SECTOR_SIZE" --argjson alignment "$OPI5_ALIGNMENT_SECTORS" \
    --argjson bstart "$OPI5_BOOT_START" --argjson bsize "$OPI5_BOOT_SIZE" \
    --argjson sstart "$OPI5_SYSTEM_START" --argjson ssize "$OPI5_SYSTEM_SIZE" \
    --argjson vstart "$OPI5_VENDOR_START" --argjson vsize "$OPI5_VENDOR_SIZE" \
    --argjson mstart "$OPI5_METADATA_START" --argjson msize "$OPI5_METADATA_SIZE" \
    --argjson ustart "$OPI5_USERDATA_START" '
      .partitiontable.label == "gpt" and .partitiontable.sectorsize == $sector and
      (.partitiontable.partitions | length) == 5 and
      .partitiontable.partitions[0].name == "boot" and (.partitiontable.partitions[0].type | ascii_upcase) == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" and .partitiontable.partitions[0].start == $bstart and .partitiontable.partitions[0].size == $bsize and
      .partitiontable.partitions[1].name == "system" and (.partitiontable.partitions[1].type | ascii_upcase) == "0FC63DAF-8483-4772-8E79-3D69D8477DE4" and .partitiontable.partitions[1].start == $sstart and .partitiontable.partitions[1].size == $ssize and
      .partitiontable.partitions[2].name == "vendor" and (.partitiontable.partitions[2].type | ascii_upcase) == "0FC63DAF-8483-4772-8E79-3D69D8477DE4" and .partitiontable.partitions[2].start == $vstart and .partitiontable.partitions[2].size == $vsize and
      .partitiontable.partitions[3].name == "metadata" and (.partitiontable.partitions[3].type | ascii_upcase) == "0FC63DAF-8483-4772-8E79-3D69D8477DE4" and .partitiontable.partitions[3].start == $mstart and .partitiontable.partitions[3].size == $msize and
      .partitiontable.partitions[4].name == "userdata" and (.partitiontable.partitions[4].type | ascii_upcase) == "0FC63DAF-8483-4772-8E79-3D69D8477DE4" and .partitiontable.partitions[4].start == $ustart and .partitiontable.partitions[4].size > 0 and
      (.partitiontable.partitions[4].start + .partitiontable.partitions[4].size) == (((.partitiontable.lastlba + 1) / $alignment | floor) * $alignment)
    ' <<<"$table" >/dev/null
}
