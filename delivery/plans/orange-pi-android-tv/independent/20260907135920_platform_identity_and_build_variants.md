# Platform identity and build variants

Implement the approved platform-presentation cleanup in four dependency-ordered
slices. Keep every commit local until the owner explicitly requests a push.

## Slices

1. `20260907135920_platform_identity_and_build_variants_slice_01.md` — remove
   the unprovisioned Cast receiver from customized images and guard releases.
2. `20260907135920_platform_identity_and_build_variants_slice_02.md` — make
   `Orange Pi 5` the canonical device name and expose truthful community build
   identity without changing the legacy internal `opi5_pro` target.
3. `20260907135920_platform_identity_and_build_variants_slice_03.md` — present
   the standard image as an open-source AOSP TV build and describe Flicky as an
   F-Droid Android TV store client.
4. `20260907135920_platform_identity_and_build_variants_slice_04.md` — add
   explicit `userdebug` and hardened `user` variants with deterministic build
   identity, fail-closed signing input, and release checks.

The existing OSS/custom content profiles remain orthogonal to the build
variant. `userdebug` remains the default. No change may claim Google
certification, verified boot, hardware-backed attestation, or a security patch
level the sources do not substantiate.
