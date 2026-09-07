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

The build validates the ignored controller-repository copy and stages only that
public key under the selected Android source tree. Soong requires source inputs
to reside below the source root. The staged `.opi5-config/adbkey.pub` is local
build state and is never part of a Git project; ADB private keys are rejected.

The three isolated source/output slots are `sources/oss`,
`sources/custom-gapps`, and `sources/custom-widevine`. Android retains the
upstream internal target directory `out/target/product/opi5_pro`, while final
image names identify Orange Pi 5.

`bootstrap.sh` accepts `OPI5_PUBLIC_GIT_BASE` and defaults to the anonymous
public GitHub namespace `https://github.com/mrworf/`. Override it with a URL
prefix ending in `/` when validating another mirror.

When this repository is nested below an existing Android checkout, bootstrap
seeds a separate repo tool installation from the parent and still creates an
independent shallow client. It never reuses or syncs the parent checkout.

## Controller checks

Run the fast controller-level checks before a long build:

```bash
bash tests/test-profiles.sh
bash tests/test-adb-key.sh
bash tests/test-release-verifier.sh
bash tests/test-release-metadata.sh
bash tests/test-flash-command.sh
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
full-disk, boot, system, and vendor images. Keep it with any image you retain;
it intentionally is not committed to the controller repository.
