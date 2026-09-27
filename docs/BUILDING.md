# Building

## Host requirements

Install the Android `repo` launcher and the normal Android build prerequisites,
plus `git`, `python3`, `rsync`, `sfdisk`, `sgdisk`, `mtools`, `e2fsprogs`, and
`jq`.  The checkout and all output remain below this RAID-backed repository.

Configure the ignored repository-local ADB public key first.  Then bootstrap
and build one of the supported profiles.  Parallelism is fixed at `-j26`.
Source sync defaults to eight concurrent network fetches to avoid public-server
rate limits and can be overridden with `OPI5_SYNC_JOBS`.

```bash
./configure-adb-key --from "$HOME/.android/adbkey.pub"
./bootstrap.sh --profile oss
./build.sh --profile oss
```

## Build variants

Content profiles and Android build variants are independent. Authenticated
Ethernet ADB is enabled in every variant because the board deliberately keeps
all external USB connectors in host mode. `userdebug` is the default and also
keeps persistent kernel-log capture for development:

```bash
./build.sh --profile oss --variant userdebug
```

The `user` variant is non-debuggable, keeps ADB authentication enforced, does
not start persistent kernel logging, enables Android debugfs restrictions, and
removes the board's permissive SELinux boot argument. On the first `user`
build, the controller generates an ignored local release-signing identity
before compilation:

```bash
./build.sh --profile oss --variant user
```

Back up the generated `local/signing` directory securely and reuse it for all
future releases. You can generate it ahead of time or customize its public
certificate subject with `./configure-release-signing`; see
[`local/README.md`](../local/README.md). The build creates target-files, signs
source-built APK containers using the standard Android key mappings while
preserving explicitly presigned external artifacts, replaces every APEX payload
key with the configured APEX release key, regenerates partition images, and
only then assembles the Orange Pi disk image. This is application and APEX
release signing; this board does not currently implement AVB or rollback
protection.

Every build uses a deterministic `OPI5.<hash>` build number derived from the
selected profile, variant, and checked-out project revisions. It also uses the
neutral builder identity `opi5@builder`, so release properties do not disclose
the workstation account or hostname.

The build validates the ignored controller-repository copy and stages only that
public key under the selected Android source tree. Soong requires source inputs
to reside below the source root. The staged `.opi5-config/adbkey.pub` is local
build state and is never part of a Git project; ADB private keys are rejected.

The three isolated source slots are `sources/oss`, `sources/custom-gapps`, and
`sources/custom-widevine`. Within each source slot, builds use separate output
trees: `out/userdebug` and `out/user`. Each retains its own Android and kernel
intermediates, host signing tools, temporary files, and partition images. Images
are under `out/<variant>/target/product/opi5_pro`, while final image names
identify Orange Pi 5. Switching variants does not overwrite the other variant's
images or invalidate its compilation cache; the first build of each tree is
cold. The wrapper still reinstalls the selected variant's product staging tree
to ensure consistent partition build identities, but keeps compiled intermediates.

For manual `m` invocations from a source checkout, first export
`OUT_DIR=out/userdebug` (or `out/user`) and use that variant's kernel paths, as
the wrapper does. Existing legacy `out/target/product/opi5_pro` artifacts and
their release metadata are left untouched; no automatic migration is performed.

`bootstrap.sh` accepts `OPI5_PUBLIC_GIT_BASE` and defaults to the anonymous
public GitHub namespace `https://github.com/mrworf/`. Override it with a URL
prefix ending in `/` when validating another mirror.

When this repository is nested below an existing Android checkout, bootstrap
seeds a separate repo tool installation from the parent and still creates an
independent shallow client. It never reuses or syncs the parent checkout.

## Kernel modules

`build.sh` limits modular drivers to the board hardware, USB Wi-Fi families
covered by the bundled firmware, UVC webcams, Bluetooth support, USB audio,
and USB keyboard, mouse, and gamepad drivers. Standard USB audio, generic HID,
USB Bluetooth HCI, and several common gamepad drivers are built into the kernel.
The build packages only modules listed by the current kernel `modules.order`;
old `.ko` files in an incremental output directory cannot enter `vendor.img`.
Because the kernel uses `CONFIG_MODVERSIONS`, always deploy its matching
`boot.img` and `vendor.img` together.

## Controller checks

Run the fast controller-level checks before a long build:

```bash
bash tests/test-profiles.sh
bash tests/test-adb-key.sh
bash tests/test-build-identity.sh
bash tests/test-build-output.sh
bash tests/test-release-signing.sh
bash tests/test-release-verifier.sh
bash tests/test-release-metadata.sh
bash tests/test-flash-command.sh
bash tests/test-flicky-install-access.sh
bash tests/test-kernel-module-selection.sh
bash tests/test-documentation.sh
```

`build.sh` also invokes the release verifier after image assembly. It rejects
dirty source projects, a missing Orange Pi 5 DTB, a kernel/package mismatch,
and payloads that do not match the selected profile. Every image must contain
the pinned, maintainer-signed Flicky build and must not contain Google Photos.
An OSS image containing YouTube is rejected, while a custom image missing
YouTube is rejected.

Each successful build also creates an ignored record under `releases/` with a
`release.json` file and an exact-revision `source-manifest.xml`. The record
identifies the selected profile, Orange Pi 5 DTB, and SHA-256 hashes for the
full-disk, boot, system, and vendor images. It also records the variant,
source-derived build ID, and whether development or release signing was used.
Keep it with any image you retain;
it intentionally is not committed to the controller repository.
