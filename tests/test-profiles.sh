#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/profile.sh"

mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/profile-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/local/customization"
printf '%s\n' 'default_profile=custom' 'widevine=enabled' \
  > "$TEST_ROOT/local/customization/profile.conf"

opi5_resolve_profile "$TEST_ROOT"
[[ $OPI5_PROFILE == custom && $OPI5_WIDEVINE == enabled ]]

opi5_resolve_profile "$ROOT" --profile oss
[[ $OPI5_PROFILE == oss && $OPI5_WIDEVINE == disabled ]]
[[ $(opi5_source_slot) == oss ]]
if opi5_resolve_profile "$ROOT" --profile oss --with-widevine 2>/dev/null; then
  echo "OSS incorrectly accepted Widevine" >&2; exit 1
fi
opi5_resolve_profile "$ROOT" --profile custom --without-widevine
[[ $OPI5_PROFILE == custom && $OPI5_WIDEVINE == disabled ]]
[[ $(opi5_source_slot) == custom-gapps ]]
opi5_resolve_profile "$ROOT" --profile custom --with-widevine
[[ $OPI5_PROFILE == custom && $OPI5_WIDEVINE == enabled ]]
[[ $(opi5_source_slot) == custom-widevine ]]
echo "profile tests passed"
