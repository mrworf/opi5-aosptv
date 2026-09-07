# Local configuration

The `local/customization` directory is ignored. It can contain optional,
machine-local inputs described in [the customization guide](../docs/CUSTOMIZATION.md):

```text
local/customization/profile.conf
local/customization/gapps.xml
local/customization/widevine.xml   # optional
local/customization/machines/      # optional flashing configurations
```

These files are never required or inspected by an OSS build.
