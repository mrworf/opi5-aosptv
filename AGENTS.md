# Orange Pi 5 Android TV build rules

- Build Android, the kernel, and related components with `-j26`.
- The hardware target is Orange Pi 5 v1.2 with 8 GB RAM.  The legacy upstream
  source directories named `opi5_pro` are not the product identity.
- Always package `rk3588s-orangepi-5.dtb`.
- With `CONFIG_MODVERSIONS`, package boot and vendor from the same kernel/module
  build and never deploy a rebuilt kernel with stale modules.
- Keep all build output and temporary files below this repository; do not use
  `/tmp` for large or compiler-generated data.
- OSS builds contain neither GApps nor Widevine. Custom builds require
  user-supplied GApps; Widevine L3 is required only when explicitly enabled.
- Keep user-specific customization manifests and defaults below the ignored
  `local/customization` directory. Public files must not assume how or where
  those inputs are hosted.
- Every build requires the ignored `config/adb/adbkey.pub`.  Never read, copy,
  commit, or package the corresponding private `adbkey`.
- Keep USB-C in host-capable mode and use Ethernet ADB.
- Do not add timing-based workarounds without explicit user approval.
- Do not flash physical media automatically.  Generate an exact guarded
  `pkexec` command and wait for the user to run it.
- Validate the first boot of a new product/profile identity with metadata and
  userdata cleared together.  The flasher must never silently preserve data
  partitions whose filesystems it cannot recognize.
