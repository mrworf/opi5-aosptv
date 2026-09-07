#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$ROOT/lib/profile.sh"
opi5_resolve_profile "$ROOT" "$@"
opi5_require_adb_key "$ROOT"

command -v repo >/dev/null || { echo "Android repo launcher is required" >&2; exit 2; }
PUBLIC_BASE=${OPI5_PUBLIC_GIT_BASE:-https://github.com/mrworf/}
SOURCE_SLOT=$(opi5_source_slot)
SOURCE="$ROOT/sources/$SOURCE_SLOT"
MANIFEST_DIR="$SOURCE/.repo/local_manifests"
mkdir -p "$SOURCE" "$ROOT/.state/manifests"

if [[ ! -f "$SOURCE/.repo/repo/main.py" ]]; then
  probe=$(dirname "$SOURCE")
  outer_repo=
  while [[ $probe != / ]]; do
    if [[ -f $probe/.repo/repo/main.py ]]; then
      outer_repo=$probe
      break
    fi
    probe=$(dirname "$probe")
  done
  if [[ -n $outer_repo ]]; then
    mkdir -p "$SOURCE/.repo"
    git clone --quiet --shared "$outer_repo/.repo/repo" "$SOURCE/.repo/repo"
  fi
  repo_init=(repo init --no-outer-manifest --this-manifest-only
    --depth=1 --no-clone-bundle
    -u https://android.googlesource.com/platform/manifest -b android-17.0.0_r1)
  (cd "$SOURCE" && "${repo_init[@]}")
fi
mkdir -p "$MANIFEST_DIR"
sed "s|@PUBLIC_GIT_BASE@|$PUBLIC_BASE|g" \
  "$ROOT/manifests/opi5-public.xml.in" > "$MANIFEST_DIR/opi5-public.xml"

if [[ $OPI5_PROFILE == custom ]]; then
  customization="$ROOT/local/customization"
  gapps="$customization/gapps.xml"
  [[ -f "$gapps" ]] || { echo "Custom profile requires $gapps" >&2; exit 2; }
  install -m 0644 "$gapps" "$MANIFEST_DIR/gapps.xml"
  if [[ $OPI5_WIDEVINE == enabled ]]; then
    widevine="$customization/widevine.xml"
    [[ -f "$widevine" ]] || { echo "Widevine enabled but $widevine is missing" >&2; exit 2; }
    install -m 0644 "$widevine" "$MANIFEST_DIR/widevine.xml"
  else
    rm -f "$MANIFEST_DIR/widevine.xml"
  fi
else
  rm -f "$MANIFEST_DIR/gapps.xml" "$MANIFEST_DIR/widevine.xml"
fi

SYNC_JOBS=${OPI5_SYNC_JOBS:-8}
[[ $SYNC_JOBS =~ ^[1-9][0-9]*$ ]] || { echo "OPI5_SYNC_JOBS must be a positive integer" >&2; exit 2; }
(cd "$SOURCE" && repo sync -c -j"$SYNC_JOBS" --retry-fetches=3)
printf 'Bootstrapped %s (Widevine %s) at %s\n' "$OPI5_PROFILE" "$OPI5_WIDEVINE" "$SOURCE"
