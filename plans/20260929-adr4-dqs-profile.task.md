# Library-default DQS profile

Created 2026-09-29. Status: DONE.
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Required outcomes

Both 3.51.0 and 3.46.0 use and verify library-default DQS. The frontend either models string fallback or rejects ambiguous expression uses as UNSUPPORTED. Native and model/profile behavior switch together; identifier quoting remains usable.

## Observable validation

Live tests on both pinned libraries distinguish identifiers, DQS fallback, and frontend rejection; existing profile/native/parser tests pass.

## Constraints and relevant code

migration_check translation/admission, conformance/native_connection.py, native fixture shell configuration and execution-profile docs; prefer conservative rejection over expanding expression semantics.

Work stays in the dedicated adr4 workspace. No merge to main or adr3 rebase before user approval.
