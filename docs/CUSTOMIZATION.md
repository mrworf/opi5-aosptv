# Customizing the build

The OSS profile is complete and does not require additional components. The
controller also accepts local manifest overlays for builders who want to add
their own packages.

Create the ignored local configuration directory:

```bash
mkdir -p local/customization
cp manifests/gapps-overlay.example.xml local/customization/gapps.xml
```

Edit `gapps.xml` to use your own source location and an immutable revision. The
manifest must check out its product makefile at
`vendor/gapps_tv/arm64/arm64-vendor.mk`. The current release policy also expects
that makefile to package `YouTubeTV` at
`/product/app/YouTubeTV/YouTubeTV.apk`. Then run:

```bash
./bootstrap.sh --profile custom --without-widevine
./build.sh --profile custom --without-widevine
```

Widevine L3 is an independent, optional overlay. Copy and edit
`manifests/widevine-overlay.example.xml` as
`local/customization/widevine.xml`, then select it explicitly:

```bash
./bootstrap.sh --profile custom --with-widevine
./build.sh --profile custom --with-widevine
```

The Widevine source must provide `widevine-vendor.mk`, `Android.bp`, and a
verifiable `bundle-manifest.json`. Enabling Widevine fails before compilation
if its manifest or validated payload is absent. Merely placing files in an
Android checkout does not enable it.

Optional defaults can be stored as plain data in
`local/customization/profile.conf`:

```text
default_profile=custom
widevine=enabled
```

Command-line profile options override these defaults. User-supplied manifests,
source locations, payloads, and machine configuration stay below the ignored
`local/` directory and are never required or inspected by an OSS build. Users
are responsible for ensuring that they may use and distribute anything they
add.
