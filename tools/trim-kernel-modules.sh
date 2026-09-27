#!/usr/bin/env bash
set -euo pipefail

# Retain built-in board features while limiting optional modules to hardware
# this TV can use. Run after defconfig and before compiling Image/modules;
# olddefconfig removes orphaned options and resolves retained dependencies.
KERNEL_ROOT=${1:?Usage: trim-kernel-modules.sh KERNEL_ROOT KERNEL_OUT}
KERNEL_OUT=${2:?Usage: trim-kernel-modules.sh KERNEL_ROOT KERNEL_OUT}
CONFIG="$KERNEL_OUT/.config"
[[ -f $CONFIG ]] || { echo "Missing kernel configuration: $CONFIG" >&2; exit 2; }

awk '
  /^CONFIG_[A-Za-z0-9_]+=m$/ {
    split($0, fields, "=")
    symbol = fields[1]
    # USB Wi-Fi drivers supported by the pinned firmware bundle, their shared
    # driver libraries, and the USB families that need no separate firmware.
    if (symbol ~ /^CONFIG_(ATH_COMMON|ATH9K_HW|ATH9K_COMMON|ATH9K_HTC|CARL9170|AR5523|MT7601U|MT76.*|MT792.*|RT2X00.*|RT2500USB|RT73USB|RT2800USB|RT2800_LIB|RTL8187|RTL_CARDS|RTL8192CU|RTL8192C_COMMON|RTLWIFI.*|RTL8XXXU|RTW88.*|RTW89.*)$/ ||
        # Android Bluetooth, USB HID keyboards/mice/gamepads, standard USB
        # audio, UVC webcams, and the board hardware observed on the device.
        symbol ~ /^CONFIG_(BT_RFCOMM|BT_BNEP|BT_HIDP|BT_MTK|BT_ATH3K|HID_.*|SND_USB_.*|USB_VIDEO_CLASS|INPUT_JOYDEV|SPI_ROCKCHIP_SFC|DRM_DISPLAY_CONNECTOR|KEYBOARD_ADC|APPLE_MFI_FASTCHARGE|LEDS_PWM)$/ ||
        # Android networking and socket diagnostics used by the board.
        symbol ~ /^CONFIG_(NF_TABLES|PACKET_DIAG|NETLINK_DIAG|INET_RAW_DIAG)$/) {
      print
    } else {
      print "# " symbol " is not set"
    }
    next
  }
  { print }
' "$CONFIG" > "$CONFIG.opi5-trimmed"
mv "$CONFIG.opi5-trimmed" "$CONFIG"

make -C "$KERNEL_ROOT" O="$KERNEL_OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

for symbol in CONFIG_MODVERSIONS CONFIG_BT_HCIBTUSB CONFIG_SND_USB_AUDIO \
    CONFIG_USB_HID CONFIG_HID_GENERIC CONFIG_JOYSTICK_XPAD CONFIG_USB_VIDEO_CLASS \
    CONFIG_ATH9K_HTC CONFIG_CARL9170 CONFIG_MT7601U CONFIG_MT7921U \
    CONFIG_MT7925U CONFIG_RT2800USB CONFIG_RTL8192CU CONFIG_RTL8XXXU \
    CONFIG_RTW88_8812AU CONFIG_RTW89_8852BU CONFIG_HID_APPLE \
    CONFIG_HID_NINTENDO CONFIG_INPUT_JOYDEV CONFIG_KEYBOARD_ADC \
    CONFIG_DRM_DISPLAY_CONNECTOR CONFIG_SPI_ROCKCHIP_SFC \
    CONFIG_INET_RAW_DIAG CONFIG_NETLINK_DIAG; do
  grep -Eq "^${symbol}=(y|m)$" "$CONFIG" || {
    echo "Required Orange Pi 5 kernel feature disappeared: $symbol" >&2
    exit 2
  }
done

module_count=$(grep -c '^CONFIG_[A-Za-z0-9_]*=m$' "$CONFIG" || true)
(( module_count > 0 && module_count < 300 )) || {
  echo "Unexpected modular kernel configuration: $module_count modules" >&2
  exit 2
}
printf 'Orange Pi 5 kernel configuration retains %s modular options\n' "$module_count"
