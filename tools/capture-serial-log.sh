#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/capture-serial-log.sh [SERIAL_DEVICE] [OUTPUT_LOG] [BAUD]

Capture the Orange Pi UART continuously until Ctrl-C. If SERIAL_DEVICE is
omitted, exactly one /dev/serial/by-id, /dev/ttyUSB, or /dev/ttyACM candidate
must be present. OUTPUT_LOG defaults below test-artifacts/ and BAUD defaults to
1500000.
EOF
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DEVICE=${1:-}
OUTPUT=${2:-}
BAUD=${3:-1500000}

if [[ -z $DEVICE ]]; then
  shopt -s nullglob
  candidates=(/dev/serial/by-id/*)
  if ((${#candidates[@]} == 0)); then
    candidates=(/dev/ttyUSB* /dev/ttyACM*)
  fi
  if ((${#candidates[@]} != 1)); then
    printf 'Expected exactly one serial device, found %d:\n' "${#candidates[@]}" >&2
    printf '  %s\n' "${candidates[@]:-none}" >&2
    echo 'Pass the desired device explicitly.' >&2
    exit 2
  fi
  DEVICE=${candidates[0]}
fi

[[ -c $DEVICE ]] || { echo "Not a character device: $DEVICE" >&2; exit 2; }
[[ -r $DEVICE ]] || {
  echo "Cannot read $DEVICE; add your user to the serial-device group." >&2
  exit 2
}
[[ $BAUD =~ ^[0-9]+$ ]] || { echo "Invalid baud rate: $BAUD" >&2; exit 2; }

if [[ -z $OUTPUT ]]; then
  OUTPUT="$ROOT/test-artifacts/selinux-audit-serial-$(date -u +%Y%m%dT%H%M%SZ).log"
elif [[ $OUTPUT != /* ]]; then
  OUTPUT="$PWD/$OUTPUT"
fi
mkdir -p -- "$(dirname -- "$OUTPUT")"

stty -F "$DEVICE" "$BAUD" raw -echo -crtscts cs8 -cstopb -parenb clocal cread

printf 'Capturing %s at %s baud to %s\n' "$DEVICE" "$BAUD" "$OUTPUT" >&2
echo 'Press Ctrl-C after the test matrix is complete.' >&2

# Keep the saved stream byte-for-byte identical to the UART input. Kernel and
# Android logs already carry their own timestamps; firmware markers retain
# their exact ordering relative to those messages.
exec stdbuf -o0 cat -- "$DEVICE" | stdbuf -o0 tee -- "$OUTPUT"
