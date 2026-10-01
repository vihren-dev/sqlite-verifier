# ADR 0005 C4 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [fidelity causes](20261001-adr5-c4-fidelity.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C0–C3 are complete. Read-only research has identified the causes of all 143
historical fidelity refusals. The retained ledger, shared capture fixes and
their behavioral checks are still required before C4 is DONE.

## Sources

`conformance/{upstream_proxy.tcl,upstream_assertions.py,upstream_fidelity.py}`,
`conformance/corpus-v3/extraction.json.gz`, pinned `src/tclsqlite.c`, and
`tests/conformance_capture_test.py`.

## Progress

- 2026-10-01: Defined C4's outcomes and verification before coding. Parallel
  research reproduced each historical refusal using current Tcl traces and
  fresh native execution. Primary causes: database paths 95, untraced BLOB
  mutations 18, lock metadata 12, missed function abbreviation 9, echo module 6,
  lost reopen 2, merged SQL calls 1. The last two capture bugs already have fixes
  and regression checks from C2. Canonical abbreviation handling and retained
  ledger evidence follow.
