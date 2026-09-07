#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

prohibited=(
  "opi5-aosptv-""private-"
  "private/""integration"
  "PRIVATE_""INTEGRATION_URL"
  "PRIVATE_""GIT_BASE"
  "private_git_""base"
  "authorized to"" use"
  "private"" integration"
  "private"" repositories"
  "private"" repo"
  "private"" plug-in"
  "workstation-""private"
  "private"" profile"
  "private"" source"
)

for phrase in "${prohibited[@]}"; do
  if git grep -I -i -F -- "$phrase" -- ':!tests/test-documentation.sh'; then
    echo "Prohibited publication wording found: $phrase" >&2
    exit 1
  fi
done

grep -Fq 'This repository builds Android 17 TV for the Orange Pi 5 v1.2.' README.md
grep -Fq 'may wake the device without a remote key being pressed' README.md
grep -Fq 'https://github.com/mlm-games/flicky' README.md
grep -Fq 'https://github.com/mlm-games/flicky/releases/tag/4.5.2' README.md
grep -Fq 'GNU GPL v3.0 only' README.md
grep -Fq '740a3e026decde4788ab0020c78b71d45d2b75f817275b72c39da3dd059387db' README.md
grep -Fq '4aed2f691df64a7b0fea25a6b8c80183c6dc520e049dac0178defa1d6472228f' README.md
grep -Fq 'local/customization/gapps.xml' docs/CUSTOMIZATION.md
grep -Fq 'local/customization/widevine.xml' docs/CUSTOMIZATION.md

vendor_repo="$ROOT/sources/oss/vendor/opi"
device_repo="$ROOT/sources/oss/device/opi/opi5_pro"
if [[ -d $vendor_repo/.git || -f $vendor_repo/.git ]]; then
  actual_apk_hash=$(git -C "$vendor_repo" show HEAD:flicky/Flicky-4.5.2-arm64-v8a.apk | sha256sum)
  [[ ${actual_apk_hash%% *} == 740a3e026decde4788ab0020c78b71d45d2b75f817275b72c39da3dd059387db ]]
  git -C "$vendor_repo" show HEAD:flicky/Android.bp | grep -Fq 'SPDX-license-identifier-GPL-3.0-only'
  git -C "$vendor_repo" show HEAD:flicky/Android.bp | grep -Fq 'presigned: true'
  git -C "$vendor_repo" show HEAD:flicky/README.md | grep -Fq 'Version: `4.5.2` (`970`)'
fi
if [[ -d $device_repo/.git || -f $device_repo/.git ]]; then
  git -C "$device_repo" show HEAD:device.mk | grep -Eq '^[[:space:]]*Flicky([[:space:]]*\\)?$'
fi

echo "documentation tests passed"
