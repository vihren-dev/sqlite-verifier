# ADR 0005 C0 status

Created 2026-09-30. Status: DONE 2026-10-01.
Task: [outputs and parameters](20260930-adr5-c0-outputs.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C0 records typed parameters, empty-result shape, direct counts and native tie
groups, and compares outputs alongside state for the existing model subset.
The final audit fixes pass the full hermetic suite. C1 supplies deterministic
clocks and profile setup; C0 is done. The complete ADR and workload gates remain open.

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

- 2026-10-01: Integrated case-format-v2 outputs into the shared classifier. Native
  acquisition v3 validates shape/typed parameters before frontend admission and
  maps admitted literal writes into v2 cases. Output instrumentation follows
  production advance; UPDATE counts matched unchanged rows, and supported ABORT
  failures count zero. Missing output/parameter capability remains unsupported.
  V1 decoding explicitly supplies absent new fields and preserves old serialized
  records/verdicts. Both mutation copy paths include the output module and copy
  its typed data. Added compiled round-trip and positive/negative kernel checks,
  and documented the partial v2 interface. Pinned hermetic model suite: 60 passed
  in 156.89 seconds, including all frozen-corpus replays. Document checks: 2 passed.
  C0 remains open for faithful ordered-query/tie-window acquisition and SELECT-only
  probing; C1 profiles and all subsequent gates remain open.

- 2026-10-01: Supplementary probes now enforce SELECT-only authorization before
  SQLite preparation, since sqlite3_stmt_readonly alone permits some setting
  PRAGMAs. The guard preserves and delegates to the acquisition authorizer, and
  restores it on failures. Native read-only/EXPLAIN checks remain a second gate.
  Tests reject setting PRAGMAs, transactions, DDL, DML, EXPLAIN and random reads
  without changing rows/settings; recursive SELECT succeeds; previous authorizer
  rejection survives probing. Native/model checks: 17 passed; final native and
  document checks: 12 passed. C0's ordered-query/tie-window acquisition remains open.

- 2026-10-01: Added native grouping of engine-ordered rows using SQLite's own
  parameter-bound equality under resolved built-in collations. Tests cover
  INTEGER/REAL ties, NOCASE with DISTINCT, NULL, both window boundaries, one group
  spanning a cut window, and unordered selection. Complete boundary groups retain
  multiplicity; unresolved collations are refused. Native ordering/record checks:
  11 passed; ordering/document checks: 3 passed. SQL ordering resolution and uncut
  query acquisition remain to be integrated before C0 is complete.

- 2026-10-01: Integrated ordered-query/window evidence into native output recording.
  A small lexical boundary reader preserves parameter slots and quoted/commented
  SQL; SQLite remains the syntax/evaluation authority. Projected aliases, ordinals
  and unchanged qualified columns resolve to an outer native dense_rank probe.
  DISTINCT/GROUP BY/compound semantics stay inside the original uncut SELECT;
  inherited collations, numeric ties, direction and NULL placement stay native.
  Probes must reproduce original shape and rows, with complete window boundaries.
  Limited INSERT sources are checked before writing: partial groups are excluded,
  unique-key cuts run the write once. Hidden/ambiguous keys and unresolved limited
  write contexts retain named exclusions. Acquisition validates group membership
  before frontend admission, so unsupported queries cannot hide malformed groups.
  Identifier handling uses SQLite ASCII folding and exact quote unescaping.
  Pinned hermetic model suite: 64 passed in 168.02 seconds; focused ordering/doc
  checks: 6 passed. C0 remains active pending the final contract audit; C1's engine
  profiles and controlled clock are the next major package. No frozen corpus changed.

- 2026-10-01: Final audit rejects zero-sized groups and partial interior groups
  in the shared Lean comparator and native adapter. Compiled and kernel checks
  exercise the same positive/negative output contract. Nested LIMIT contexts
  are explicitly excluded rather than freezing arbitrary inner selection as a
  determined outer result. Native tests cover both reads and writes. Pinned
  hermetic model suite: 66 passed in 149.38 seconds, including legacy frozen
  replay and mutation checks; focused output/model/ordering/docs: 17 passed.
  Prepared the C1 task/status contract for verified profiles and native clocks.

- 2026-10-01: Completed cross-package audit after C1 integration. Native probes
  now preserve stored clock/timezone inputs as well as parameters/state.
  Native shape/parameter/RETURNING/direct-count boundaries are covered by
  conformance_record_test.py; SQLite sort ties and one/two window boundaries
  by conformance_ordering_test.py; compiled/kernel corruption rejection by
  conformance_trace_test.py and conformance_model_test.py. Missing query and
  parameter capabilities remain unsupported. Full hermetic regressions preserve
  v1 verdicts and frozen replays: 70 passed in 129.13 seconds. C0 DONE.
