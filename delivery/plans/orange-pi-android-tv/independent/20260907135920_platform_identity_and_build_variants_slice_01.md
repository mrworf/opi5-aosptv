# Slice 01: Disable the unavailable Cast receiver

## Goal and outcome

Customized images no longer package or advertise the unavailable Chromecast
receiver, and release verification rejects regressions.

## Scope

Remove MediaShell, Backdrop, their grants and sysconfig declarations from the
private GApps payload; select the AOSP Colors dream; add public release guards
and concise documentation. Do not alter unrelated Google packages or push.

## Dependencies and behavior

This is the first slice and uses the already generated private payload files.
The custom image continues to include its other configured packages. The
release verifier must reject MediaShell or Backdrop in a custom system image.
No authorization or runtime state transition applies.

## Validation and recovery

Run XML parsing, private payload regeneration/idempotence checks, the release
verifier tests, documentation tests, and `git diff --check`. A failed check
leaves both repositories uncommitted for correction.

## Surfaces and tests

Private GApps package lists/generated make and Blueprint files, permission and
sysconfig XML, dream overlay; controller README, verifier, and verifier tests.
Positive: a clean custom image passes. Negative: either removed APK is rejected.

## Acceptance and commit boundary

Create one private GApps commit and one controller commit containing this slice
plan and its public half. Do not update the remote-only manifest pin or push.
