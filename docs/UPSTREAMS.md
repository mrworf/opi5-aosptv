# Component repositories and upstreams

Every modified Android component is published under the `mrworf` account with
an `opi5-aosptv-` prefix. GitHub records a fork relationship where the source
project is hosted on GitHub. Components sourced from Android Git repositories
that GitHub cannot represent as forks are standalone mirrors with their
upstream recorded here.

| Component suffix | Publication kind | Upstream |
| --- | --- | --- |
| `android_build_release` | standalone mirror | `https://android.googlesource.com/platform/build/release` |
| `android_device_google_atv` | standalone mirror | `https://android.googlesource.com/device/google/atv` |
| `android_device_opi_opi5_pro` | GitHub fork | `https://github.com/dvab-sarma/android_device_opi_opi5_pro` |
| `android_device_opi_opi5_pro-kernel` | GitHub fork | `https://github.com/dvab-sarma/android_device_opi_opi5_pro-kernel` |
| `android_external_drm_hwcomposer` | GitHub fork | `https://github.com/dvab-sarma/android_external_drm_hwcomposer` |
| `android_external_ffmpeg` | GitHub fork | `https://github.com/dvab-sarma/android_external_ffmpeg` |
| `android_external_ffmpeg_codec2` | GitHub fork | `https://github.com/dvab-sarma/android_external_ffmpeg_codec2` |
| `android_external_minigbm` | GitHub fork | `https://github.com/dvab-sarma/android_external_minigbm` |
| `android_frameworks_av` | standalone mirror | `https://android.googlesource.com/platform/frameworks/av` |
| `android_frameworks_base` | GitHub fork | `https://github.com/aosp-mirror/platform_frameworks_base` |
| `android_frameworks_native` | standalone mirror | `https://android.googlesource.com/platform/frameworks/native` |
| `android_hardware_rockchip_librga` | standalone mirror | `https://github.com/yisding/librga` |
| `android_kernel_rk_opi` | GitHub fork | `https://github.com/dvab-sarma/android_kernel_rk_opi` |
| `android_packages_apps_TvSettings` | standalone mirror | `https://android.googlesource.com/platform/packages/apps/TvSettings` |
| `android_packages_modules_Bluetooth` | standalone mirror | `https://android.googlesource.com/platform/packages/modules/Bluetooth` |
| `android_packages_modules_Permission` | standalone mirror | `https://android.googlesource.com/platform/packages/modules/Permission` |
| `android_packages_modules_Wifi` | standalone mirror | `https://android.googlesource.com/platform/packages/modules/Wifi` |
| `android_system_core` | GitHub fork | `https://github.com/aosp-mirror/platform_system_core` |
| `android_system_memory_libmeminfo` | standalone mirror | `https://android.googlesource.com/platform/system/memory/libmeminfo` |
| `android_system_sepolicy` | standalone mirror | `https://android.googlesource.com/platform/system/sepolicy` |
| `proprietary_vendor_opi` | GitHub fork with OSS-only publication history | `https://github.com/dvab-sarma/proprietary_vendor_opi` |

Unmodified projects referenced directly by the manifest remain pinned to their
original upstream repositories and do not get redundant project forks.
