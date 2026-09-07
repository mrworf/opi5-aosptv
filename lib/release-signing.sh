#!/usr/bin/env bash

opi5_resolve_signing_dir() {
  local root=$1 config="$1/local/signing/release.conf"
  [[ -f $config ]] || {
    echo "User builds require $config; see local/README.md" >&2
    return 2
  }
  local key_dir=
  while IFS='=' read -r key value; do
    [[ $key == key_dir ]] && key_dir=$value
  done < "$config"
  [[ -n $key_dir ]] || { echo "Missing key_dir in $config" >&2; return 2; }
  [[ $key_dir == /* ]] || key_dir="$root/$key_dir"
  OPI5_SIGNING_DIR=$key_dir
  export OPI5_SIGNING_DIR
}

opi5_require_release_keys() {
  local root=$1 source=$2
  opi5_resolve_signing_dir "$root"
  command -v openssl >/dev/null || { echo "Missing host tool: openssl" >&2; return 2; }
  local name suffix candidate stock cert_public key_public
  for name in releasekey platform shared media networkstack sdk_sandbox bluetooth nfc cts_uicc_2021; do
    for suffix in pk8 x509.pem; do
      candidate="$OPI5_SIGNING_DIR/$name.$suffix"
      [[ -s $candidate ]] || { echo "Missing release signing input: $candidate" >&2; return 2; }
      stock="$source/build/make/target/product/security/${name/releasekey/testkey}.$suffix"
      if [[ -f $stock ]] && cmp -s "$candidate" "$stock"; then
        echo "Refusing AOSP development key for user build: $candidate" >&2
        return 2
      fi
    done
    openssl x509 -in "$OPI5_SIGNING_DIR/$name.x509.pem" -noout >/dev/null 2>&1 || {
      echo "Invalid X.509 certificate: $OPI5_SIGNING_DIR/$name.x509.pem" >&2; return 2;
    }
    openssl pkcs8 -inform DER -in "$OPI5_SIGNING_DIR/$name.pk8" -nocrypt -out /dev/null \
      >/dev/null 2>&1 || {
      echo "Invalid unencrypted PKCS#8 key: $OPI5_SIGNING_DIR/$name.pk8" >&2; return 2;
    }
    cert_public=$(openssl x509 -in "$OPI5_SIGNING_DIR/$name.x509.pem" -pubkey -noout |
      openssl pkey -pubin -outform DER 2>/dev/null | sha256sum)
    key_public=$(openssl pkcs8 -inform DER -in "$OPI5_SIGNING_DIR/$name.pk8" -nocrypt 2>/dev/null |
      openssl pkey -pubout -outform DER 2>/dev/null | sha256sum)
    [[ ${cert_public%% *} == "${key_public%% *}" ]] || {
      echo "Signing key does not match certificate: $name" >&2; return 2;
    }
  done
  [[ -s $OPI5_SIGNING_DIR/apex.pem ]] || {
    echo "Missing APEX payload key: $OPI5_SIGNING_DIR/apex.pem" >&2; return 2;
  }
  openssl pkey -in "$OPI5_SIGNING_DIR/apex.pem" -noout >/dev/null 2>&1 || {
    echo "Invalid APEX payload key: $OPI5_SIGNING_DIR/apex.pem" >&2; return 2;
  }
}

opi5_require_clean_release_sources() {
  local root=$1 source=$2 status_output
  status_output=$(git -C "$root" status --porcelain --untracked-files=normal) || return 2
  [[ -z $status_output ]] || {
    printf '%s\n' "$status_output" >&2
    echo "User builds require a clean controller checkout" >&2
    return 2
  }
  status_output=$(cd "$source" && .repo/repo/repo forall -j1 \
    -c 'git status --porcelain --untracked-files=normal') || return 2
  [[ -z $status_output ]] || {
    printf '%s\n' "$status_output" >&2
    echo "User builds require clean Android source projects" >&2
    return 2
  }
}
