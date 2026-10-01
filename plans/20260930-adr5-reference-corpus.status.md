# ADR 0005 corpus status

Created 2026-09-30. Status: IN PROGRESS.
Task: [reference corpus](20260930-adr5-reference-corpus.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

Owner authorized implementation on 2026-09-30 after the document reviews.
Dedicated `adr5` workspace combines merged ADR 0004 (`main` at `3aae9b50`)
with ADR 0003's implemented shared structural codec (`96609b4c`). No conflicts;
resource checks pass. C0–C4 are done. C5–C7 and the private workload gate are open.
C8 follows the model semantics concerned, as the ADR specifies.

## Sources and package records

`StructuralCodec.lean`, `VerifierConformance/{Case,Trace,Json}.lean`,
`conformance/{native_connection,native_record,native_replay,corpus}.py`,
`build-support/tests.nix`, and the frozen v3 manifest are the initial sources.
C0: [outputs and parameters](20260930-adr5-c0-outputs.task.md),
[status](20260930-adr5-c0-outputs.status.md).
C1: [verified profiles](20261001-adr5-c1-profiles.task.md),
[status](20261001-adr5-c1-profiles.status.md).
C2: [exclusion narrowing](20261001-adr5-c2-exclusions.task.md),
[status](20261001-adr5-c2-exclusions.status.md).
C3: [bounded storage](20261001-adr5-c3-storage.task.md),
[status](20261001-adr5-c3-storage.status.md).
C4: [fidelity causes](20261001-adr5-c4-fidelity.task.md),
[status](20261001-adr5-c4-fidelity.status.md).
C5: [neutral authored cases](20261001-adr5-c5-authored.task.md),
[status](20261001-adr5-c5-authored.status.md).

## Progress

- 2026-09-30: Inspected current branches, reviewed ADR and product gates, created
  an isolated workspace, integrated the existing shared codec, and recorded
  outcome/verification requirements before implementation.
  Markdown link checks passed (2 tests); resource checks passed. ADR status now
  records the owner's authorization. No corpus artifact was modified.

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

- 2026-10-01: Final C0 audit tightened malformed group rejection in Lean and
  native decoding and excluded unresolved nested windows explicitly. Compiled
  and kernel output checks pass. Full pinned hermetic suite: 66 passed in
  149.38 seconds, including frozen replays and mutation checks. C1 task/status
  files now specify verified profiles and engine clock control before coding.
  C1–C7 and the actual workload gate remain open; no owner feedback is needed.

- 2026-10-01: C1 now has a native VFS clock primitive and optional explicit VFS
  selection on connections. Defaults, triggers and read-only probes read the
  supplied clock while the engine's default filesystem VFS remains unchanged.
  Clock/native recording/DQS regressions: 13 passed in 0.81 seconds. Integration
  into versioned profiles, recording/replay and manifests remains required.

- 2026-10-01: C1 profile primitive now measures complete native engine identity
  and establishes/readbacks foreign-key and recursive-trigger settings. Native
  tests verify cascading behavior within an immediate transaction and refuse
  incorrect source/version/compile options. Profile/clock/record/DQS checks:
  14 passed. Acquisition, replay and manifest integration remain open.

- 2026-10-01: Integrated explicit profile/clock evidence into native recording
  and replay (acquisition v4), with strict transport and refusal of profile,
  engine, setting and transaction-mode mismatches. Default/trigger reads,
  RETURNING and native ordered probes replay at a later wall time using stored
  clocks. Explicit-profile model capability remains unsupported; malformed
  evidence cannot become unsupported. Full pinned hermetic suite: 69 passed in
  128.14 seconds; documents: 2 passed. Driver measurement method documented.
  C1 remains open for manifest binding and final audit; later gates remain open.

- 2026-10-01: Manifests now declare complete execution profiles and corpus
  loading requires exact matching for every native v4 case. Tests refuse
  missing/conflicting declarations and duplicate identities; legacy frozen
  upstream replay passes. Profile/upstream/docs: 8 passed; final docs: 2 passed.
  Final C1 audit and all subsequent gates remain open.

- 2026-10-01: Closed C0/C1 after contract audit and the full hermetic run:
  70 passed in 129.13 seconds. Audit fixes control/restore UTC for localtime,
  reject unsupported setting PRAGMAs and select either existing pinned engine
  without relabelling its source identity. Package task/status files record
  completion evidence. C2 task/status now describe narrower extraction rules
  and rejecting tests before coding. C2–C7 and the private workload gate remain
  open; no frozen corpus membership changed and no owner feedback is needed.

- 2026-10-01: C2 selection now retains all applicable reasons, including cap
  labels, instead of replacing context/fidelity exclusions. Per-instance reports
  carry the full reason array. Upstream/frozen replay/docs checks: 7 passed.
  C2 remains open for helpers, context lifetimes and before/after yields.

- 2026-10-01: C2 now retains helper kinds and applies native SELECT-only
  acquisition plus Tcl onecolumn/exists result semantics. Native rows stay
  unmodified; writing helpers are refused. Upstream/record/profile/docs:
  26 passed. Pinned Tcl fixture built and actual helper semantics checked.
  Mixed helper sequences, row scripts, context lifetimes and yields remain open.

- 2026-10-01: C2 mixed helper calls preserve original call boundaries and apply
  each Tcl helper's semantics independently. Read-only spans refuse writing
  helpers. Real pinned Tcl extraction found/fixed a mechanical fidelity cause:
  newline-only joining merged semicolon-free calls. The mixed-helper harness
  test now records one case and passes fresh native replay. Focused regressions:
  27 passed. Row scripts, context recovery and before/after yields remain open.

- 2026-10-01: C2 supports verified pure Tcl row bodies with empty-result helper
  semantics, retaining ordinary native rows and RETURNING. The real pinned
  harness records three cases and excludes explicit mutation/read-trace side
  effects; fresh native replay passes. Focused regressions: 28 passed. Context
  recovery, profile-aware extraction and measured yields remain open.

- 2026-10-01: C2 supports verified recovery after read-only auxiliary connections
  close. Deletion traces capture actual close; same-file/generation, unchanged
  settings and committed-read conditions protect typed fidelity. Real Tcl tests
  recover one case and refuse live handles, uncommitted reads and writes; native
  replay passes. Focused checks: 32 passed. Attached contexts, profile-aware
  extraction and yield measurements remain open.

- 2026-10-01: C2 recovers detached in-memory attachment prefixes by replaying
  their complete SQL and checking Tcl outcomes. Native inventories distinguish
  successful from failed DETACH; live attachments and external file prefixes
  remain excluded. Two real Tcl recovery cases pass fresh native replay.
  Full hermetic suite: 84 passed; final context/document checks: 7 passed.
  Profile-aware extraction and yield measurements remain open.

- 2026-10-01: Prefix minimization preserves typed parameters, outputs and
  profile/clock evidence during trial acquisition. Output-only and clock-profile
  regression cases remove redundant setup with identical initial state and trace.
  Upstream/frozen replay/document checks: 17 passed. Tcl profile integration and
  C2 yield measurements remain open.

- 2026-10-01: C2 explicit-profile Tcl capture now establishes settings and a
  fixed native clock, retains profile/output evidence in the manifest and refuses
  clock changes. The new hermetic upstream target checks defaults, triggers,
  cascading deletes and immediate transactions through real Tcl capture and
  fresh native replay: 1 passed. Focused regressions: 27 passed; docs: 2 passed.
  Unsupported-setting accounting and measured extraction yields remain open.
  Full pinned hermetic model suite: 87 passed in 150.38 seconds.

- 2026-10-01: C2 reports profile-setting exclusions by canonical PRAGMA name.
  Real Tcl capture verifies separate foreign_keys and ignore_check_constraints
  refusals. Empty-script fixed clock inputs are validated. Pinned upstream check:
  1 passed; profile/context/document checks: 11 passed. C2 yields remain open.

- 2026-10-01: C2 acquisition treats integrity_check/quick_check as metadata reads.
  The hermetic upstream target now includes the existing real Tcl helper and
  connection/attachment recovery checks: 4 passed. Native profile/context/docs:
  11 passed. The first four-file extraction retained 32 cases; final before/after
  measurements and the C2 audit remain open.

- 2026-10-01: Closed C2 after contract audit and the four-file measurement:
  17,404 assertions, 32 cases before/after under cap 20, with no yield increase
  claimed. Both profiles finish all files; full exclusions and experimental
  records are retained in reports. Real Tcl tests verify scoped nondeterminism
  and recovery after clock reset; changed clocks across reopen stay excluded.
  Pinned upstream target: 5 passed; native/profile/context/docs: 21 passed.
  C3–C7 and the private workload gate remain open.

- 2026-10-01: Started C3 task/status records. Streaming measurement binds the
  giant e_blobbytes:e_blobbytes-1.0:0 record to frozen v3's digest and measures
  302,050,086 bytes. The new selection cap and shared storage remain to be added.

- 2026-10-01: Closed C3 after final storage audit. New records have a 1,000,000-byte
  cap before sharing, complete snapshots are stored by content digest, and load
  verifies/expands them before replay. Refresh preserves observations and profiles
  across repeated shared parents. Implemented size selection excludes the giant
  v3 record at 302,050,086 bytes without changing frozen evidence. Hermetic model:
  101 passed in 135.29 seconds; real Tcl upstream: 6 passed in 0.38 seconds;
  docs: 2 passed. C4–C7 and the private workload gate remain open. C4's parallel
  research has identified causes for all 143 historical fidelity mismatches;
  mechanical fixes and retained triage evidence follow.

- 2026-10-01: Prepared C4 task/status files. The historical denominator includes
  all 143 result/error mismatches, beyond the ADR's 123 prefix-result headline.
  The ledger must match that complete set and preserve each actual refusal cause.

- 2026-10-01: Closed C4 with a digest-bound ledger for all 143 historical fidelity
  refusals and retained Tcl/native evidence. Audit refined 18 preliminary BLOB
  labels into 14 missing implicit bindings plus 4 BLOB mutations; additional
  mutation causes remain explicit. Canonical Tcl method dispatch, callback/BLOB
  and nested-SQL guards prevent those contexts from becoming misleading evidence.
  Specific metadata/module diagnostics preserve actual native truth. Full pinned
  hermetic model: 112 passed in 131.86 seconds; upstream: 7 passed in 0.57 seconds;
  focused fidelity/ordering/upstream: 32 passed; docs: 2 passed. C5–C7 and the
  private workload gate remain open. Initial C5 research found 29 legacy authored
  cases without output/profile evidence; the broader boundary cases and stable
  requirement-coverage reporting remain to be added.

- 2026-10-01: Prepared C5 task/status files. Research identifies neutral feature
  and interaction cases and 29 legacy scenarios to record with outputs/profiles.
  Before/after requirement counts will retain the full 3,500-row inventory,
  including zero rows. Document checks: 2 passed. Authored implementation and
  verification remain open.
