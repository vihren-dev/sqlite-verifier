# Library-default DQS profile: status

Created 2026-09-29. Status: DONE.
Task: [Library-default DQS profile](20260929-adr4-dqs-profile.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Both library defaults are verified without override; the shell enables and checks
the same settings. Ambiguous literal expressions reject while quoted identifiers
resolve normally. Both-version tests and five frozen native/kernel regressions
pass (8 tests); the legacy native and current pipeline suites also pass. Profile
documents and ADR implementation status changed together. No merge is authorized.
