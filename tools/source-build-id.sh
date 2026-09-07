#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE=${1:?Usage: source-build-id.sh SOURCE PROFILE WIDEVINE VARIANT}
PROFILE=${2:?}
WIDEVINE=${3:?}
VARIANT=${4:?}
[[ -x $SOURCE/.repo/repo/repo ]] || { echo "Missing repo client: $SOURCE" >&2; exit 2; }

{
  printf 'controller\0'
  git -C "$ROOT" rev-parse HEAD
  printf 'profile=%s\0widevine=%s\0variant=%s\0' "$PROFILE" "$WIDEVINE" "$VARIANT"
  cd "$SOURCE"
  .repo/repo/repo forall -j1 -c 'printf "%s\0" "$REPO_PATH"; git rev-parse HEAD'
} | sha256sum | awk '{print substr($1, 1, 16)}'
