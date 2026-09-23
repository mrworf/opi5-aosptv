# Bluetooth reconnect volume synchronization

Preserve the user-selected shared Bluetooth media volume when an A2DP sink
briefly loses its classic ACL and reconnects. The implementation is one
coherent slice because the synchronization policy, its state transitions, and
its tests must land together.

## Slice

1. `20260922195653_bluetooth_reconnect_volume_sync_slice_01.md` — make the
   locally remembered volume authoritative for the first remote absolute-volume
   report after an A2DP device becomes active, then resume normal bidirectional
   AVRCP volume handling.

The change must be event-driven. It must not add a delay, retry timer, or
device-specific address/name/port rule. It must preserve the existing Orange
Pi Bluetooth HID suspend behavior already present in the Bluetooth repository.
