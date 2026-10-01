# Conformance case format v2 (implementation in progress)

ADR 0005 extends [v1](conformance-format-v1.md) with statement outputs and typed
parameters. The existing v1 serialization and verdicts are preserved. This is
currently the comparison interface for the existing literal-write subset;
ordered-query acquisition and execution profiles remain work in progress.

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
