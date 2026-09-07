# Troubleshooting

- Missing ADB key: run `./configure-adb-key --from PATH_TO_PUBLIC_KEY`.
- Missing GApps: add `local/customization/gapps.xml`; its checkout must provide
  `vendor/gapps_tv/arm64/arm64-vendor.mk`.
- Missing Widevine: use `--without-widevine`, or add
  `local/customization/widevine.xml` and its validated payload.
- Wrong board name: only legacy upstream source paths may contain `opi5_pro`;
  the lunch target and output directory must contain `opi5`.
- Dirty prebuilt-kernel checkout: the build is invalid; generated kernel files
  must be staged below `out/opi5/kernel-package`.
