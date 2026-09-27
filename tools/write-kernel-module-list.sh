#!/usr/bin/env bash
set -euo pipefail

KERNEL_OUT=${1:?Usage: write-kernel-module-list.sh KERNEL_OUT}
ORDER="$KERNEL_OUT/modules.order"
OUTPUT="$KERNEL_OUT/opi5-modules.list"
[[ -s $ORDER ]] || { echo "Missing kernel modules.order: $ORDER" >&2; exit 2; }

# modules.order belongs to the current Kconfig build. A directory-wide find
# would also pick up .ko files left by older configurations in this output tree.
awk '/\.o$/ { sub(/\.o$/, ".ko"); print }' "$ORDER" | sort -u > "$OUTPUT.pending"
[[ -s $OUTPUT.pending ]] || { echo "Current build has no modules" >&2; exit 2; }
while IFS= read -r module; do
  [[ -f "$KERNEL_OUT/$module" ]] || {
    echo "Current build is missing $module from modules.order" >&2
    exit 2
  }
done < "$OUTPUT.pending"
sed "s|^|$KERNEL_OUT/|" "$OUTPUT.pending" > "$OUTPUT"
rm "$OUTPUT.pending"
printf 'Selected %s current kernel modules\n' "$(wc -l < "$OUTPUT")"
