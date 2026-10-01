# ADR 0005 C5 authored evidence

Recorded 2026-10-01. Audience: implementation reviewers.

The [native evidence](20261001-adr5-c5-authored-records.jsonl.gz) contains 43
authored records: 29 existing requirement scenarios recorded again with outputs
and profiles, plus 14 new neutral boundary and interaction scenarios. Fresh
native replay passes for all 43. The [machine report](20261001-adr5-c5-authored.json)
binds the evidence, source files, requirement inventory and old corpus by digest.
This is C5 evidence; C6 freezes the final corpus membership.

## Measured change

| Measure | Before | After |
| --- | --- | --- |
| Logical cases for this comparison | 370 | 384 |
| Requirement inventory rows | 3,500 | 3,500 |
| Rows with a case | 60 | 98 |
| Rows with zero cases | 3,440 | 3,402 |

The after comparison replaces the 29 legacy authored records by case name and
adds 14 new scenarios. It retains v3's upstream membership for this measurement;
size selection and further upstream acquisition belong to C6. All inventory rows
remain visible, including requirements outside this ADR's SQL scope. One case
counts once per requirement row even when short and full tags name the same row.
Scenario counts do not prove an entire requirement.

## Scenarios and observations

The neutral catalog covers all SQL feature categories in ADR 0005 section 1.3:
schema defaults and additions, TEXT primary keys and indexes, triggers and
foreign-key cascades, transactions and constraint failures, UPSERT/RETURNING,
aggregates and grouping, joins, COALESCE, CAST and REAL arithmetic, ordering and
window cuts, time functions, and JSON functions. Cases include empty and single-row
tables, NULL, empty TEXT/BLOB, embedded NUL bytes and signed 64-bit limits.

The write sequence records four audit rows from a two-row insert, a matched
unchanged update with count one, a zero-match update, an empty SELECT with shape
and no carried change count, and one parent delete that cascades to two children.
CHECK failure rolls back the current multirow statement while preserving an
earlier write in the open transaction. Independent PK, NOT NULL and FK failures
retain unchanged tables and native constraint codes.

Query cases retain INTEGER/REAL and NOCASE tie groups, two distinct window
boundaries, both cuts inside one three-row group, and an unordered window.
DISTINCT retains its original shape. Clock defaults and triggers see the write's
controlled timestamp; the later query and its probe see the query's timestamp.
JSON preserves scalar types and empty-result shape. JSON has feature metadata
and no requirement tags because the inventory contains no relevant requirement.

Four profiles measure the running pinned 3.51.0 engine: deferred, immediate,
foreign keys with immediate transactions, and a controlled-clock variant.
The native build uses pinned Clang on both CI platforms. The
[Linux portability check](20261001-adr5-c5-portability.json) verifies identical
complete compile options, fresh recording and native replay for all 43 records
on x86_64-linux. The macOS authored/profile/DQS checks pass: 18 tests.
The workload-driver gap remains unmeasured here. Each record is below 1 MB;
the largest expanded record is 71,053 bytes. Shared snapshots reduce the retained
43-record payload to 227,680 bytes, compressed to 14,735 bytes.

The classifier reports `MODEL_UNSUPPORTED` for all 43 explicit-profile cases.
Production SQL semantics have not changed. The test suite checks concrete native
outputs and rejects corrupted replay evidence; it makes no agreement claim for
unsupported model behavior.

## Reproduction

Choose a new output prefix; existing evidence is not overwritten:

```sh
nix develop path:./nix --command timeout 90 python -m conformance.authored_report \
  --output-prefix reports/c5-recheck --runtime-root build/conformance
```

The focused behavioral and coverage checks passed: 22 tests, including two
document checks. The C5 task/status record contains the final hermetic result.
