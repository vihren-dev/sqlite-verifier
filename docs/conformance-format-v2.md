# Conformance case format v2

ADR 0005 extends [v1](conformance-format-v1.md) with statement outputs and typed
parameters. The existing v1 serialization and verdicts are preserved. This is
the comparison interface for the existing literal-write subset. Native acquisition
supports ordered queries and explicit profiles; missing model capabilities remain
unsupported.

A v2 case has all v1 fields, `version: 2`, and two additional arrays:

- `parameters`: one array of typed values per reached statement, using the shared
  value codec. Parameterized model execution is not implemented and remains
  `MODEL_UNSUPPORTED`.
- `outputs`: one object per reached statement, with `result` and `groups`.
  `result` has `columns` (ordered names), `rows` (arrays of typed values), and
  `changes` (a nonnegative direct DML count or null for other statements).
  Column shape is present even when `rows` is empty.

`groups: null` compares rows as a multiset. An array describes ordered native tie
groups: each has `rows` (the complete eligible multiset) and `count` (the number
selected by the window). Each row occurrence is consumed once; groups keep their
order. A boundary group may select fewer rows than it contains. The decoder
checks row widths, counts, and that native rows satisfy their own group evidence.
Stored groups select at least one row; only the first and last may be partial.
Both arrays have one fewer entry than `nativeTrace`, which includes initialization.

`classifyCase` compares stored state through the existing production trace, then
compares statement outputs. Output instrumentation follows production `advance`:
INSERT counts one on success; UPDATE counts matched rows, including unchanged
values; supported ABORT constraint failures count zero. Other DML failures have
no modeled output capability and stay unsupported. No query evaluator is added.

The acquisition format has a separate version: `nativeVersion: 3` records typed
parameters, `columns`, `columnCount`, `rows`, and `changes` beside each native
statement observation. Fresh native replay binds the recorded parameters and
checks outputs and state. The adapter validates acquisition fields before
frontend admission and maps admitted records to case version two. Ordered query
records cannot yet reach model comparison because query semantics are absent;
faithful tie-group acquisition is required before those cases can be frozen.

Supplementary probes use a native SELECT-only authorizer before preparation,
plus SQLite's read-only and EXPLAIN flags before stepping. They reject PRAGMAs,
transaction control, DDL, DML and nondeterministic random functions. The guard
delegates to the acquisition authorizer and restores it after success or failure.

[Native tie grouping](../conformance/native_ordering.py) accepts engine-ordered
full rows and resolved projected keys with built-in collations. The recorder
resolves projected names, ordinals and unchanged qualified columns, and ranks an
uncut query through an outer SELECT. DISTINCT, GROUP BY and compound results stay
inside the original query. SQLite supplies comparison semantics, including
inherited collations, numeric ties, direction and NULL placement. Window
intersection retains both complete boundary groups, including one group cut at
both ends. Probes preserve parameter slots and must reproduce the original rows
and shape. Hidden or ambiguous keys are excluded as "tie structure not observable".
Limited INSERT sources are probed before writing; a partial group is excluded as
"unspecified choice inside a write". A unique-key cut can execute, and the write
itself runs once. Nested windows and other unresolved limited-write contexts are
excluded as "tie structure not observable".

Explicit profiles use acquisition `nativeVersion: 4`, retaining v3 output fields
and adding a `profile` record and `setupClockUnixMilliseconds`. Controlled-clock
profiles add `clockUnixMilliseconds` to each reached statement. Native replay
validates the profile and supplies those clock values through a private native
VFS, including default/trigger reads and supplementary probes. Different profile
identities, engine builds, transaction modes and changes to established behavioral
settings during case SQL are refused. Setup can replay FK changes when it restores
the selected profile before case SQL. Transaction-local FK writes keep SQLite's
no-op behavior; readback still checks the fixed profile after each statement.
The model has no explicit-profile capability yet; valid v4
records remain `MODEL_UNSUPPORTED`, while malformed evidence is a harness error.
Manifests declare `executionProfiles`, an array of these complete profile records.
Every v4 record must match a declaration exactly; duplicate name/version identities
and missing or conflicting declarations are refused. Legacy corpora retain their
implicit profile. External workload commands remain work in progress.

New acquisition uses Tcl display policy version 2. It establishes precision zero
after `tester.tcl`, then retains source-owned precision changes observed at each
successful SQL call. A REAL display must parse to the exact independently
recorded IEEE bits, including signed zero. Rounded collisions and unobservable
precision stay refused. Policy version 1 retains its zero-only requirement when
historical evidence is read. Native REAL cells are never replaced with display text.

Native corpus storage has its own `snapshotStorageVersion: 1`, independent of
`nativeVersion`. A record's `snapshots` object maps SHA-256 digests to complete
`{schema, tables}` snapshots. Each initial/trace `visible` and `persisted` field
contains `{"snapshot": "DIGEST"}`. Digests use canonical UTF-8 JSON with sorted
keys, compact separators and unescaped non-ASCII characters. Corpus loading checks
the manifest's stored-byte digest, verifies every snapshot and reference, and
restores independent observations before replay or model translation. Unknown
storage versions, missing references, altered digests and unused pool entries
are refused. Legacy unshared records retain their original meaning and size policy.
