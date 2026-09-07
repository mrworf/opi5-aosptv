# Orange Pi 5 Android TV

This repository builds Android 17 TV for the Orange Pi 5 v1.2. The legacy
upstream source and target directories remain named `opi5_pro`, but generated
images target the Orange Pi 5 and use `rk3588s-orangepi-5.dtb`.

## Feature highlights

- Hardware-accelerated 4K60 video playback, including a hardware-verified AV1
  3840 x 2160 at 60 fps path, with native 4K display output and HDMI 2.0 support
- End-to-end video color handling for full and limited range, BT.601, BT.709,
  BT.2020, PQ, and HLG metadata
- An interactive Bluetooth audio-sync tuner with a synchronized visual
  metronome and tick/tock track, live 10 ms adjustments, and Auto, Relative,
  and Absolute latency controls
- Persistent selection of built-in, HDMI/eARC, USB, A2DP, or LE Audio output,
  with automatic fallback while a preferred device is absent and restoration
  when it returns
- A persistent five-band system-wide equalizer with custom, Voice clarity, and
  Night presets across every output path
- A global right-side quick menu for Sleep Now, Restart, Audio Output,
  Equalizer, Apps, and Settings, opened from a remote's standard Menu key
- Genuine suspend-to-RAM deep sleep—not display-only standby—with wake from the
  power key, supported USB keyboards/remotes, and Bluetooth HID remotes
- USB Wi-Fi and Bluetooth integration, including packaged adapter firmware,
  adapter-aware Settings, Wi-Fi MAC/link-speed details, saved Bluetooth media
  volume, and A2DP reconnection after suspend

## Additional tested functionality

The following have been exercised on an Orange Pi 5 v1.2 with 8 GB RAM:

- NVMe boot and guarded whole-disk or partition flashing
- Built-in Ethernet, including MAC-address display in Settings
- Ethernet ADB using a repository-local, pre-authorized public key

## Known limitations

- A Bluetooth adapter may wake the device without a remote key being pressed.
  This spurious wake issue is known and remains to be fixed.
- Wi-Fi and Bluetooth require compatible USB adapters; the board has no onboard
  Wi-Fi or Bluetooth.
- Only the native display color mode is exposed. Broad HDR and wide-gamut
  tone-mapping support is not yet claimed, even when a connected display reports
  HDR capabilities.
- The OSS product contains neither Google apps nor Widevine.
- USB gadget ADB is intentionally not enabled because it conflicts with the
  shared upright USB-A host path; use Ethernet ADB.

## Media support

The Codec2 FFmpeg service exposes these decoders. Video decoding uses the
RK3588's stateless V4L2-request hardware wherever the codec and stream are
supported; RGA3 and DRM planes accelerate conversion and presentation. Streams
outside a supported hardware path fall back safely to software where feasible.

| Media | Codecs | Advertised limits |
| --- | --- | --- |
| Audio | AAC, AC-3, ALAC, FLAC, MP2, MP3, Vorbis | Up to 8 channels; 8-192 kHz |
| Video | H.264/AVC, HEVC/H.265 | Up to 7700 x 7700 |
| Video | AV1, VP9 | Up to 4096 x 4096 |
| Video | H.263, MPEG-2, MPEG-4, VP8 | Up to 2048 x 2048 |

These are codec-advertisement limits, not guarantees that every profile,
bitrate, resolution, and frame rate will play in real time. Hardware-accelerated
AV1 playback at 3840 x 2160 and 60 fps has been validated on the target board.
The RK3588-specific media work includes stateless V4L2-request HEVC decoding,
direct AV1 graphic buffers, recovery from undersized AV1 hardware frame pools,
and RGA3 conversion for compact NV15 and strided NV12 surfaces. RGA imports and
conversions have safe fallbacks, and Codec2 tolerates streams that omit frame
timestamps.

Decoded full/limited range, color primaries, transfer characteristics, and
matrix coefficients are propagated from FFmpeg into Codec2. Mappings cover
BT.601, BT.709, BT.2020, PQ, and HLG metadata. The display stack sends
unsupported layer color profiles through GPU composition and restores native
HDMI connector colorspace selection, avoiding the incorrect range and gamut
handling seen before these fixes.

## Flicky

[Flicky](https://github.com/mlm-games/flicky) is included in both OSS and
customized images under the
[GNU GPL v3.0 only](https://github.com/mrworf/opi5-aosptv-proprietary_vendor_opi/blob/android-17.0-opi5-tv/flicky/LICENSE).
The build pins the maintainer-signed ARM64 APK from the
[4.5.2 release](https://github.com/mlm-games/flicky/releases/tag/4.5.2), whose
tag also provides the corresponding source code.

The pinned artifact is version 4.5.2 (`970`), package `app.flicky`, with APK
SHA-256 `740a3e026decde4788ab0020c78b71d45d2b75f817275b72c39da3dd059387db`
and signer SHA-256
`4aed2f691df64a7b0fea25a6b8c80183c6dc520e049dac0178defa1d6472228f`.
The vendor component keeps the APK unmodified and declares it as a presigned,
product-specific `android_app_import`. The Orange Pi TV product adds the
`Flicky` module to `PRODUCT_PACKAGES`, which places it in the product image for
installation on first boot. Retaining the upstream signature allows a newer
APK signed by the same maintainer key to update the built-in copy normally.

## Build

```bash
git clone https://github.com/mrworf/opi5-aosptv.git
cd opi5-aosptv
./configure-adb-key --from "$HOME/.android/adbkey.pub"
./bootstrap.sh --profile oss
./build.sh --profile oss
```

See [Building](docs/BUILDING.md) for prerequisites and outputs. To supply your
own additional components, use the interface described in
[Customizing the build](docs/CUSTOMIZATION.md).

Repository provenance is recorded in [Component repositories and
upstreams](docs/UPSTREAMS.md), and installation is covered by
[Flashing and data recovery](docs/FLASHING.md).
