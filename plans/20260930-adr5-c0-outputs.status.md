# ADR 0005 C0 status

Created 2026-09-30. Status: IN PROGRESS.
Task: [outputs and parameters](20260930-adr5-c0-outputs.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C0 is open. Existing native evidence already records typed result rows, but not
parameter bindings, empty-result shape, direct counts or ordering evidence.
The structural adapter emits only v1 state observations; the Lean comparator
has no output observations. C1 owns deterministic clocks and profile setup.

## Progress

- 2026-09-30: Read native connection/recording, corpus replay, structural codecs,
  test harness and Nix boundaries. Recorded full package outcomes and its
  behavioral verification before editing source.

- 2026-09-30: Added the pure Lean output comparator using the shared typed value
  domain. It checks empty-result shape, direct counts, occurrence-consuming bags,
  ordered groups and partial boundary groups, and rejects malformed evidence.
  Added kernel-checked positive and negative examples to the existing trace suite.
  Pinned Nix conformance build passed; trace/output and document tests: 4 passed.
  C0 remains open: recording, versioned decoding and classifier integration follow.

- 2026-09-30: Native connections now expose empty-result column shape, validate
  complete positional/named parameter-slot binding, and reject statements SQLite
  marks as writing before stepping a requested read-only probe. The existing
  row-only API delegates to this executor. C signatures moved into a small
  source-pinned library module to keep the connection below 200 lines; Nix inputs
  include it and the output comparator. Native record/DQS, kernel trace/output,
  and Nix target checks passed: 32 tests in 49.70 seconds. Script recording and
  SELECT-only supplementary probing still need integration into version-two cases.

- 2026-10-01: Opt-in native acquisition version 3 records each statement's typed
  parameter slots, column names/count, rows and direct DML change count. Native
  authorizer events distinguish DML from DDL (including CTAS) and EXPLAIN; the
  counter is captured before snapshots and excludes trigger/cascade side effects.
  Tail splitting moved to native_statements.py; old acquisition remains unchanged.
  Fresh native replay binds recorded values and rejects corrupted output counts.
  Native/model/upstream regression tests passed; combined run: 38 passed and one
  infrastructure check failed on sandbox DNS. That check passed when rerun outside
  the sandbox (1 test). Final record/document checks: 12 passed. Version 3 remains
  refused by the model adapter until case-format-v2 integration; ordered-group
  recording, classifier integration and execution profiles are still open.
