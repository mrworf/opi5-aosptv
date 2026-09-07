# Flashing and data recovery

Builds generate partition checksums and release metadata. The controller tooling
creates guarded commands but never invokes `pkexec` or writes a physical device
by itself. Machine-specific disk identity belongs below the ignored `local/`
directory.

For kernel changes, always flash matching `boot.img` and `vendor.img`. Normal
flashing updates boot, system, and vendor while preserving metadata and userdata
only when both data partitions contain valid ext4 filesystems. If either
filesystem is unrecognized, the flasher refuses to preserve it and requires the
exact `CLEAR-DATA` confirmation before continuing.

Generate a flash command from a release record and workstation configuration:

```bash
./tools/print-flash-command.sh \
  --machine local/customization/machines/build-workstation.json \
  --release-json releases/custom-widevine-true-TIMESTAMP/release.json
```

Review and run the printed command. Serial and exact-capacity guards are applied
when present in the machine file. If either guard is absent, the helper prints
the stable path, resolved device, model, serial, and capacity and requires the
exact token `CONTINUE` from an interactive terminal.

For the first boot of a new checkout, a changed product/profile identity, or a
scratch release-validation drive, generate an explicitly clean flash command:

```bash
./tools/print-flash-command.sh \
  --machine local/customization/machines/build-workstation.json \
  --release-json releases/custom-widevine-true-TIMESTAMP/release.json \
  --clear-data
```

This prevents stale Android or encrypted data from being mistaken for a build
failure. The command still requires interactive confirmation before erasing
anything.

`--target` accepts stable paths such as `/dev/disk/by-id/...` and direct whole
disk paths such as `/dev/sdc` or `/dev/nvme0n1`. Stable paths remain preferable
because direct `/dev/sdX` names can change after reconnecting hardware. The
whole-disk and host-root-disk checks apply to both forms, and partition paths are
derived from the resolved disk (`/dev/sdc1`, `/dev/nvme0n1p1`, and so on).

Release metadata supplies workspace-relative paths, sizes, and hashes for every
image. Targets smaller than the release disk image fail before hashing,
unmounting, or writing. Larger disks are supported: boot, system, vendor, and
metadata retain canonical geometry and userdata fills the remaining space.

## Back up data

Back up GPT, metadata, and userdata without flashing:

```bash
pkexec ./tools/flash-partitions.sh \
  --mode backup \
  --target /dev/disk/by-id/REPLACE_WITH_STABLE_ID \
  --backup-root "$PWD/backups"
```

Add `--backup-before-flash` and optionally `--backup-root PATH` to a generated
flash command to require a verified backup before writing. Flashing aborts if
any backup step or checksum fails. It also aborts if the existing partition
layout is not trustworthy enough to back up.

Each timestamped backup contains a GPT image and readable dump, raw metadata,
sparse raw userdata, SHA-256 checksums, and `backup.json`. Sparse userdata files
may have a large apparent size while using space primarily for allocated blocks.
Backups default to the ignored `backups/` directory and must remain on the
RAID-backed project storage, never `/tmp`.

## Restore data

Restore a backup to the same device and disk geometry:

```bash
pkexec ./tools/flash-partitions.sh \
  --mode restore \
  --target /dev/disk/by-id/REPLACE_WITH_STABLE_ID \
  --backup /absolute/path/to/opi5-data-TIMESTAMP
```

Restore verifies every checksum, the device serial when recorded, capacity,
sector size, and partition sizes. It requires the exact token `RESTORE` before
overwriting GPT, metadata, and userdata.

## Clear Android data

Clear userdata and metadata without flashing:

```bash
pkexec ./tools/flash-partitions.sh \
  --mode clear \
  --target /dev/disk/by-id/REPLACE_WITH_STABLE_ID
```

Add `--clear-data` to a flash command to clear after flashing. Both forms require
the exact token `CLEAR-DATA`. Metadata and userdata are always cleared together
because Android encryption state must not be separated from userdata.

## Repair an incompatible partition table

If GPT is absent or differs from the canonical Orange Pi 5 layout, normal flash
mode displays the current layout and requires the exact token `REPARTITION`.
That operation erases the disk, creates a capacity-adjusted GPT, restores U-Boot,
and initializes metadata and userdata. Repartitioning is never attempted when a
pre-flash backup was requested.
