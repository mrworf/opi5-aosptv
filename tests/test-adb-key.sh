#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/lib/profile.sh"
grep -q 'ADB_KEY_STAGE="$SOURCE/.opi5-config/adbkey.pub"' "$ROOT/build.sh"
grep -q 'export OPI5_ADB_KEYS=".opi5-config/adbkey.pub"' "$ROOT/build.sh"
! grep -q 'export OPI5_ADB_KEYS="$ROOT/config/adb/adbkey.pub"' "$ROOT/build.sh"
mkdir -p "$ROOT/.state"
TEST_ROOT=$(mktemp -d "$ROOT/.state/adb-key-test.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT

git -C "$TEST_ROOT" init -q
mkdir -p "$TEST_ROOT/config/adb"
printf '/config/adb/adbkey.pub\n' > "$TEST_ROOT/.gitignore"

if opi5_require_adb_key "$TEST_ROOT" 2>/dev/null; then
  echo "Missing ADB key was accepted" >&2
  exit 1
fi

printf '%s\n' '-----BEGIN PRIVATE KEY-----' > "$TEST_ROOT/config/adb/adbkey.pub"
if opi5_require_adb_key "$TEST_ROOT" 2>/dev/null; then
  echo "Private-key material was accepted" >&2
  exit 1
fi

printf '%s\n' 'bm90LWFuLWFuZHJvaWQta2V5' > "$TEST_ROOT/config/adb/adbkey.pub"
if opi5_require_adb_key "$TEST_ROOT" 2>/dev/null; then
  echo "Malformed ADB key was accepted" >&2
  exit 1
fi

head -c 524 /dev/zero | base64 -w0 > "$TEST_ROOT/config/adb/adbkey.pub"
opi5_require_adb_key "$TEST_ROOT"

printf '%s\n' '!/config/adb/adbkey.pub' >> "$TEST_ROOT/.gitignore"
if opi5_require_adb_key "$TEST_ROOT" 2>/dev/null; then
  echo "Unignored ADB key was accepted" >&2
  exit 1
fi

echo "ADB key tests passed"
