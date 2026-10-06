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
