# Slice 02: Canonical Orange Pi 5 identity

## Goal and outcome

The current visible device, Bluetooth, and hotspot names derive from the single
canonical product model `Orange Pi 5`; generated properties identify the
software as a community `opi5-aosptv` build.

## Scope

Centralize the model in the common TV product, remove static Settings naming,
derive Bluetooth and Wi-Fi defaults from `Build.MODEL`, use community
brand/manufacturer fields, neutralize builder identity, and remove the
unsupported app-attestation feature. Retain internal `opi5_pro` paths and
target identifiers. Do not add a permanent assertion that the display name can
never change.

## Dependencies and behavior

Requires slice 01 only for clean sequencing. First-boot Settings, Bluetooth,
and newly generated hotspot defaults use the model; user-overridden persisted
names remain untouched. Existing installations therefore retain explicit user
choices. No additional privilege is introduced.

## Validation and recovery

Run affected unit/static tests, product configuration with `m -j26 nothing`,
and inspect generated properties/resources. Invalid or absent model values fall
back to existing platform defaults rather than an empty name.

## Surfaces and tests

Device product/property/overlay configuration and the Wi-Fi default AP-name
path. Positive: fresh defaults resolve to `Orange Pi 5`. Negative: an empty
model retains the normal `AndroidAP` fallback.

## Acceptance and commit boundary

Commit the device and Wi-Fi repository changes separately, each including any
repository-local tests. No push.
