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

Create the keys once on a trusted build machine:

```bash
./configure-release-signing
```

An organization may set the public certificate identity explicitly:

```bash
./configure-release-signing --subject '/O=Example Organization/CN=Orange Pi 5 Release/'
```

The command creates unencrypted Android PKCS#8 keys, their X.509 certificates,
the APEX payload key, and `local/signing/release.conf`. It is idempotent for a
valid setup and refuses to overwrite partial or invalid signing state.

The first `user` build also runs this setup automatically when signing has not
been configured. Key generation happens before compilation and never replaces
an existing or partial identity.

The controller rejects missing, malformed, or stock AOSP development keys.
Signing files and configuration are ignored by Git. Back them up securely:
losing them prevents future builds from updating an installed image without a
data reset. Never publish the `.pk8` or `apex.pem` private keys.
