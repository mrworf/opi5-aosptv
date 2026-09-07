# Local configuration

The `local/customization` directory is ignored. It can contain optional,
machine-local inputs described in [the customization guide](../docs/CUSTOMIZATION.md):

```text
local/customization/profile.conf
local/customization/gapps.xml
local/customization/widevine.xml   # optional
local/customization/machines/      # optional flashing configurations
local/signing/release.conf         # required only for user builds
local/signing/keys/                # required only for user builds
```

The customization files are never required or inspected by an OSS build.
Signing inputs are required for any `user` variant, including OSS.

## Local release signing

Create a key directory only on a trusted build machine. From a bootstrapped
Android source slot, use AOSP's `make_key` for the Android certificate pairs and
OpenSSL for the APEX payload key. Choose and protect an appropriate certificate
subject for your own build:

```bash
mkdir -p local/signing/keys
for key in releasekey platform shared media networkstack sdk_sandbox \
    bluetooth nfc cts_uicc_2021; do
  sources/oss/development/tools/make_key "local/signing/keys/$key" \
    '/C=US/O=Local Android Build/CN=Orange Pi 5/'
done
openssl genrsa -out local/signing/keys/apex.pem 4096
chmod 0600 local/signing/keys/*.pk8 local/signing/keys/apex.pem
```

Then create `local/signing/release.conf`:

```text
key_dir=local/signing/keys
```

The controller rejects missing, malformed, or stock AOSP development keys.
Signing files and configuration are ignored by Git. Back them up securely:
losing them prevents future builds from updating an installed image without a
data reset. Never publish the `.pk8` or `apex.pem` private keys.
