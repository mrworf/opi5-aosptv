# Slice 04: Explicit development and hardened-user variants

## Goal and outcome

Builders can select `userdebug` or `user`; userdebug remains the default while
user builds fail closed unless hardened configuration and local signing inputs
are available.

## Scope

Add the CLI variant, deterministic source-derived build identity, generated
profile values, ignored signing configuration, complete target-files signing,
release metadata, documentation, and verifier policy. Keep OSS/custom content
profiles independent. Do not add AVB, rollback protection, hardware-backed
KeyMint, or invented security-patch properties.

## Dependencies and behavior

Requires canonical identity and documentation. Userdebug retains configured
Ethernet ADB and diagnostics. User is non-debuggable, enforcing, debugfs
restricted, without automatic persistent logging or default ADB. User builds
stop before compilation if signing material or enforcing policy is unavailable.
Signing secrets stay ignored and are never logged or committed.

## Validation and recovery

Add positive/negative parser and verifier tests. Validate both lunch products
with `m -j26 nothing`; build full OSS userdebug and signed OSS user images only
after focused checks pass. Failure must preserve prior usable artifacts and
produce no misleading release metadata.

## Interfaces and tests

`./build.sh --profile oss|custom --variant userdebug|user`. Positive: explicit
and default userdebug resolve correctly; a fully configured user build signs
target-files and passes verification. Negative: invalid variant, absent keys,
test keys, permissive SELinux, debugging, default ADB, persistent logger, or
workstation identity fail.

## Acceptance and commit boundary

Commit controller behavior/tests/docs and required device product conditionals
as separate repository commits after their respective validation. No push.
