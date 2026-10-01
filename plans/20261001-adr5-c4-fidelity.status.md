# ADR 0005 C4 status

Created 2026-10-01. Status: DONE.
Task: [fidelity causes](20261001-adr5-c4-fidelity.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C4 is complete. The [triage report](../reports/20261001-adr5-c4-fidelity.md)
binds all 143 historical fidelity refusals, original Tcl traces, and separate
mechanical/binding reproductions. Unique method abbreviations now use canonical
capture semantics; untraced callbacks, nested SQL, BLOB operations and implicit
Tcl bindings remain named exclusions. Proven path/build differences receive
specific diagnostics without changing native observations or frozen evidence.

## Sources

`conformance/{upstream_proxy.tcl,upstream_assertions.py,upstream_fidelity.py}`,
`conformance/corpus-v3/extraction.json.gz`, pinned `src/tclsqlite.c`, and
`tests/conformance_capture_test.py`.

## Progress

- 2026-10-01: Defined C4's outcomes and verification before coding. Parallel
  research reproduced each historical refusal using current Tcl traces and
  fresh native execution. Primary causes: database paths 95, untraced BLOB
  mutations 18, lock metadata 12, missed function abbreviation 9, echo module 6,
  lost reopen 2, merged SQL calls 1. These preliminary BLOB causes were refined
  by the binding audit below. The last two capture bugs already have fixes
  and regression checks from C2. Canonical abbreviation handling and retained
  ledger evidence follow.

- 2026-10-01: Audit distinguished 14 primary missing `$dots` bindings from
  4 primary BLOB mutations. Historical unbound execution stored NULL; a separate
  typed native experiment restores the pre-BLOB TEXT but still cannot reproduce
  the omitted BLOB write. Both causes remain in the ledger. All 143 historical
  file/id/occurrence keys match exactly, without omissions or duplicates.

- 2026-10-01: Fixed shared Tcl method dispatch against the pinned 42-method
  catalog, corrected collate/callback detection and excluded nested SQL before
  it could mispair results. Global BLOB calls exclude context even outside an
  assertion. Named SQL bindings are refused instead of silently becoming NULL.
  Lexical checks preserve SQLite EOF comments and complete named slots through
  ordering probes; punctuation, comments and quoted text are not bindings.
  Real Tcl checks cover 16 assertions and retain/replay 6 eligible cases.
  Mismatch diagnostics identify path-only database_list, test-only lock metadata
  and missing echo modules only after proven differences. No native truth edited.
  Final independent audit found no actionable findings. Full hermetic model:
  112 passed in 131.86 seconds; pinned upstream: 7 passed in 0.57 seconds;
  focused fidelity/ordering/upstream: 32 passed in 5.68 seconds; docs: 2 passed.
  C4 is DONE. C5–C7 and the private workload gate remain open; newly observed
  fidelity refusals must be triaged before C6's freeze.
