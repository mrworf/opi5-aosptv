# Slice 03: Accurate OSS project presentation

## Goal and outcome

Public documentation accurately presents an open-source AOSP TV build without
proprietary Google apps and describes Flicky as an F-Droid Android TV store
client.

## Scope

Update the controller README and customization guidance only. Preserve Flicky
license, pinned artifact, signature, source, and update details. Do not discuss
certification, private repositories, or availability of custom builds.

## Dependencies and behavior

Follows the identity slice so wording matches generated product identity. This
is documentation-only; authorization and runtime state do not apply.

## Validation and recovery

Run documentation checks and inspect links/diff. Revert only slice-owned
wording if validation fails.

## Acceptance and commit boundary

One controller documentation commit, with this slice plan. No push.
