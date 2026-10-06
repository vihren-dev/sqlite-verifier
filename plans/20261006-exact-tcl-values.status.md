# Exact Tcl values status

Status: IN PROGRESS. Created 2026-10-06.

Task: [exact Tcl values and date-family acquisition](20261006-exact-tcl-values.task.md).
Issue: [#35](https://github.com/vihren-dev/sqlite-verifier/issues/35).
Specifications: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md),
[native output and parameters](../docs/conformance-format-v2.md).

Relevant files: `conformance/upstream_result_values.py`,
`conformance/upstream_proxy.tcl`, `conformance/upstream_assertions.py`,
`conformance/upstream_selection.py`, `conformance/upstream_fidelity.py`,
`conformance/native_record.py`, `conformance/native_statements.py`,
`conformance/native_library.py`, `conformance/corpus.py`.

## Progress

- 2026-10-06: Created an isolated workspace on reviewed T16 tip `5de5cba90fbf`.
  T16 evidence and its pending journal entry remain intact in their workspace.
  Read issue #35 (no comments), existing comparator/binding guards, and pinned
  SQLite source. `date.test` and `date3.test` set precision 15. `date4.test` and
  `date5.test` use observed Tcl scalar bindings. The actual binder distinguishes
  Tcl integer/double objects from numeric-looking text and can force BLOBs with
  an `@` slot name.
- 2026-10-06: Specified exact round-trip acceptance and narrowly scoped typed
  setup/call binding evidence before coding. Investigation and short checks may
  run now; long acquisition/full-model runs wait for host coordination.
- 2026-10-06: Added precision policy v2. Captured precision 0–17 can accompany
  exact REAL comparison; all successful REAL displays must still round-trip to
  the native bits. Historical policy v1 retains its precision-zero guarantee.
  The pinned Tcl 8.6.16 runtime independently confirmed the accepted precision
  range and big-endian double encoding used by later binding observation.
- 2026-10-06: Actual Tcl regression covers precision 15, date arithmetic, signed
  zero, adjacent REAL values with identical rounded text, changed per-call
  precision, and one-bit evidence corruption. The focused precision/value,
  acquisition and freeze checks passed 93 tests in 3.78 seconds (90-second
  bound). A separate retained-policy load/replay check passed in 0.54 seconds
  (30-second bound). Bindings remain unimplemented at this checkpoint.
- Automatic approval review timed out before the first short test command
  started. The permitted single retry ran successfully; no test was bypassed.
- The sandboxed upstream target passed all 69 tests in 2.81 seconds, with no
  skips. JUnit: `/nix/store/09an84cnqr6hxahvgdddd6gc1x47p0xw-sqlite-verifier-test-upstream-1/junit.xml`.
  The new precision module is owned by this target. All frozen artifacts remain
  unchanged, and the retained-policy regression explicitly rejects precision
  15 when relabeled as historical policy v1.
