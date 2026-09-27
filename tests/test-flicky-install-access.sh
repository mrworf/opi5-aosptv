#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

for slot in oss custom-widevine; do
  source_root="$ROOT/sources/$slot"
  [[ -d $source_root ]] || continue

  framework="$source_root/frameworks/base"
  device="$source_root/device/opi/opi5_pro"
  policy="$framework/services/core/java/com/android/server/policy/PermissionPolicyService.java"
  framework_config="$framework/core/res/res/values/config.xml"
  symbols="$framework/core/res/res/values/symbols.xml"
  overlay="$device/overlay/AndroidOpiOverlay/res/values/config.xml"

  grep -Fq 'name="config_defaultRequestInstallPackagesAppOpPackages"' "$framework_config"
  grep -Fq 'name="config_defaultRequestInstallPackagesAppOpPackages"' "$symbols"
  grep -Fq 'grantDefaultRequestInstallPackagesAppOps(userId)' "$policy"
  grep -Fq 'applicationInfo.isSystemApp()' "$policy"
  grep -Fq 'Manifest.permission.REQUEST_INSTALL_PACKAGES' "$policy"
  grep -Fq 'AppOpsManager.OP_REQUEST_INSTALL_PACKAGES' "$policy"
  grep -Fq 'DEFAULT_REQUEST_INSTALL_PACKAGES_APP_OP_INITIALIZED_PREFIX' "$policy"
  grep -Fq '<item>app.flicky</item>' "$overlay"
done

echo "Flicky install-source access tests passed"
