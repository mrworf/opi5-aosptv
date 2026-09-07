#!/usr/bin/env bash

opi5_resolve_profile() {
  local root=$1
  shift
  OPI5_PROFILE=
  OPI5_WIDEVINE=
  local profile_explicit=false widevine_explicit=false
  local config="$root/local/customization/profile.conf"

  if [[ -f "$config" ]]; then
    while IFS='=' read -r key value; do
      [[ $key =~ ^[a-z_]+$ ]] || continue
      case "$key" in
        default_profile) [[ $value == oss || $value == custom ]] && OPI5_PROFILE=$value ;;
        widevine) [[ $value == enabled || $value == disabled ]] && OPI5_WIDEVINE=$value ;;
      esac
    done < "$config"
  fi

  [[ -n $OPI5_PROFILE ]] || OPI5_PROFILE=oss
  [[ -n $OPI5_WIDEVINE ]] || OPI5_WIDEVINE=disabled
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) OPI5_PROFILE=${2:-}; profile_explicit=true; shift 2 ;;
      --with-widevine) OPI5_WIDEVINE=enabled; widevine_explicit=true; shift ;;
      --without-widevine) OPI5_WIDEVINE=disabled; widevine_explicit=true; shift ;;
      *) echo "Unknown option: $1" >&2; return 2 ;;
    esac
  done
  [[ $OPI5_PROFILE == oss || $OPI5_PROFILE == custom ]] || {
    echo "Profile must be oss or custom" >&2; return 2;
  }
  if [[ $profile_explicit == true && $OPI5_PROFILE == oss && $widevine_explicit == false ]]; then
    OPI5_WIDEVINE=disabled
  fi
  if [[ $OPI5_PROFILE == oss && $OPI5_WIDEVINE == enabled ]]; then
    echo "OSS profile cannot enable Widevine" >&2
    return 2
  fi
  export OPI5_PROFILE OPI5_WIDEVINE
}

opi5_source_slot() {
  case "$OPI5_PROFILE:$OPI5_WIDEVINE" in
    oss:disabled) printf '%s\n' oss ;;
    custom:disabled) printf '%s\n' custom-gapps ;;
    custom:enabled) printf '%s\n' custom-widevine ;;
    *) echo "Invalid resolved profile: $OPI5_PROFILE/$OPI5_WIDEVINE" >&2; return 2 ;;
  esac
}

opi5_require_adb_key() {
  local root=$1 key="$1/config/adb/adbkey.pub"
  [[ -f "$key" ]] || {
    echo "Missing $key; run ./configure-adb-key --from PATH" >&2
    return 2
  }
  ! grep -q -- 'PRIVATE KEY' "$key" || {
    echo "Private-key material found at $key" >&2; return 2;
  }
  git -C "$root" check-ignore -q config/adb/adbkey.pub || {
    echo "$key must be ignored by Git" >&2; return 2;
  }
  local token decoded
  token=$(awk 'NR == 1 {print $1}' "$key")
  decoded="$root/.state/adb/preflight-decoded"
  mkdir -p "$(dirname "$decoded")"
  printf '%s' "$token" | base64 --decode >"$decoded" 2>/dev/null
  [[ $(stat -c %s "$decoded") -eq 524 ]] || {
    echo "$key is not an Android ADB public key" >&2; return 2;
  }
}
