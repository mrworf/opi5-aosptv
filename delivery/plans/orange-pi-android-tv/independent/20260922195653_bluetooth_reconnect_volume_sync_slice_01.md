# Slice 01: Preserve Bluetooth volume across transient reconnects

## Goal and observable outcome

When an active A2DP sink drops and reconnects, Android restores the remembered
media volume and does not let the sink's first reconnect-time AVRCP report
overwrite that value. Once the initial synchronization event is resolved,
normal remote and Android-side volume changes work and are persisted.

## Scope and non-scope

Change the AVRCP target volume manager and its unit tests. Clear reconnect
synchronization state on device removal or explicit local volume adjustment.
Do not change Bluetooth link supervision, add timing workarounds, special-case
the observed `D5` speaker, alter USB/HCI suspend policy, or mask later genuine
speaker-side volume changes.

## Dependencies and ordering

Build on Bluetooth commit `33d0f3fa6a58f7a9ed2f359f49afcce83b7f0c40`,
which retains the tested HID ACL suspend behavior. Commit the Bluetooth module
first, then update the public manifest pin and commit these plan artifacts in
the root repository.

## Entry point and end-to-end behavior

`AvrcpVolumeManager.switchVolumeDevice()` sends the stored volume when AVRCP
absolute-volume support becomes available. That sent value becomes the pending
initial synchronization value. If the first subsequent remote AVRCP report
differs, Android resends the pending local value without updating AudioService
or persistent storage. The guard is consumed by that event. A matching first
report also consumes the guard without redundant persistence. Subsequent remote
reports follow the existing path into AudioService and storage.

An explicit Android-side volume adjustment supersedes the pending reconnect
value and clears the guard before sending and persisting the new selection.
Disconnecting the device also clears its guard.

## Data and state transitions

- No active synchronization: remote volume reports behave normally.
- Active A2DP device with absolute volume: record `(device, restored volume)`
  while sending the restored value.
- First matching remote report: clear pending state; leave volume unchanged.
- First differing remote report: clear pending state, resend restored value,
  and do not update AudioService/storage.
- Local adjustment or disconnect: clear pending state immediately.

The pending state is in-memory connection state only. Durable volume remains
owned by the existing Bluetooth storage and AudioService shared-volume setting.

## Authorization and permissions

Not applicable. The change runs inside the existing privileged Bluetooth
service and adds no API, permission, property, or external input surface.

## Validation and recovery

Add positive tests for suppressing and correcting the first divergent remote
report and for accepting the following report. Add negative tests proving that
ordinary remote changes without pending synchronization and local changes still
work. Run the focused Bluetooth unit-test target with `-j26`; if the complete
host target is unavailable in this checkout, at minimum compile the affected
Bluetooth APEX/app target and report the limitation. A disconnect must always
discard pending state, preventing stale policy from leaking to a later session.

## Implementation surfaces

- `android/app/src/com/android/bluetooth/avrcp/AvrcpVolumeManager.java`
- `android/app/tests/unit/src/com/android/bluetooth/avrcp/AvrcpVolumeManagerTest.java`
- `manifests/opi5-public.xml.in` after the module commit

## Acceptance criteria

- A reconnect-time remote value cannot overwrite the locally restored value.
- The correction is sent immediately in response to the event, with no timer.
- Only the first reconnect synchronization report is guarded.
- Later remote volume changes and explicit local changes remain functional.
- Disconnecting removes pending synchronization state.
- Focused tests pass and the Bluetooth target compiles.

## Commit boundary

One Bluetooth module commit contains behavior and tests. One root repository
commit records this plan and advances the manifest pin to the tested module
commit. Nothing is pushed without explicit owner direction.

## Delivery record

- Bluetooth module commit: `158be25eabd02e74821ab6f94a1faf82bbe12e3e`
- `m -j26 BluetoothJavaUnitTests`: passed; the affected production library and
  test APK compiled successfully.
- Focused device test:
  `BluetoothJavaUnitTests:com.android.bluetooth.avrcp.AvrcpVolumeManagerTest`
  passed all 10 tests on the Orange Pi 5.
- The temporary test package was removed and SELinux was restored to enforcing
  after the device test.
