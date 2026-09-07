#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MACHINE= RELEASE_JSON=
CLEAR_DATA=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --machine) MACHINE=${2:-}; shift 2 ;;
    --release-json) RELEASE_JSON=${2:-}; shift 2 ;;
    --clear-data) CLEAR_DATA=true; shift ;;
    --help|-h)
      echo "Usage: $0 --machine PATH --release-json PATH [--clear-data]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

for value in MACHINE RELEASE_JSON; do
  [[ -n ${!value} ]] || { echo "Missing required command-generation option" >&2; exit 2; }
done
for tool in jq realpath; do
  command -v "$tool" >/dev/null || { echo "Missing host tool: $tool" >&2; exit 2; }
done

MACHINE=$(realpath -e "$MACHINE")
RELEASE_JSON=$(realpath -e "$RELEASE_JSON")
TARGET=$(jq -er '.target // .target_by_id' "$MACHINE")
EXPECTED_SERIAL=$(jq -r '.expected_serial // empty' "$MACHINE")
EXPECTED_CAPACITY=$(jq -r '.expected_capacity_bytes // empty' "$MACHINE")
[[ $TARGET == /dev/* ]] || { echo "Machine target must be a device path under /dev" >&2; exit 2; }
[[ -z $EXPECTED_SERIAL || $EXPECTED_SERIAL =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Machine serial is invalid" >&2; exit 2; }
[[ -z $EXPECTED_CAPACITY || $EXPECTED_CAPACITY =~ ^[1-9][0-9]*$ ]] || { echo "Machine capacity is invalid" >&2; exit 2; }

command=(pkexec "$ROOT/tools/flash-partitions.sh"
  --target "$TARGET"
  --release-json "$RELEASE_JSON")
[[ -z $EXPECTED_SERIAL ]] || command+=(--expected-serial "$EXPECTED_SERIAL")
[[ -z $EXPECTED_CAPACITY ]] || command+=(--expected-capacity "$EXPECTED_CAPACITY")
[[ $CLEAR_DATA == false ]] || command+=(--clear-data)
printf '%q ' "${command[@]}"
printf '\n'
