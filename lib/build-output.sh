#!/usr/bin/env bash

opi5_configure_output_tree() {
  local source=$1 variant=$2
  [[ $variant == userdebug || $variant == user ]] || {
    echo "Invalid output variant: $variant" >&2
    return 2
  }
  # Android resolves this relative to the selected source checkout. Keep all
  # intermediates, host tools, kernel files and images isolated by variant.
  export OUT_DIR="out/$variant"
  export OPI5_ANDROID_OUT="$source/$OUT_DIR"
  export OPI5_PRODUCT_OUT="$OPI5_ANDROID_OUT/target/product/opi5_pro"
}
