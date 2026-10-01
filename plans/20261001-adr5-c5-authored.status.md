# ADR 0005 C5 status

Created 2026-10-01. Status: DONE.
Task: [neutral authored cases](20261001-adr5-c5-authored.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C5 is done. The [retained native evidence](../reports/20261001-adr5-c5-authored-records.jsonl.gz)
contains 29 legacy scenarios recorded with outputs/profiles and 14 new neutral
cases covering the ADR's feature, boundary and interaction categories. Fresh
native replay passes for all 43. C6 freezes their final corpus membership.

The [coverage report](../reports/20261001-adr5-c5-authored.md) uses the complete
3,500-row inventory as a fixed denominator: rows with a case increase from 60 to
98, with 38 newly represented rows and no lost rows. Alias tags count once per
case and requirement. The after membership replaces 29 old scenarios and adds
14 cases (370 to 384); C6 selects final upstream membership.
JSON has no row in this inventory and is tracked by feature metadata. Existing
comparator rejection and probe safety tests remain the evidence for invalid
outputs and refused probes; invalid records do not become corpus members.

All 43 explicit-profile cases remain MODEL_UNSUPPORTED. No SQL semantic extension
or actual-workload completion is claimed. C6, C7 and the private workload gate
remain open; no owner feedback is needed.

## Sources

`conformance/{requirement_cases,native_record,execution_profile,corpus,progress}.py`,
`conformance/requirements-3.51.0.json`, and
`tests/conformance_{ordering,clock,profile,coverage}_test.py`.
New inputs: `conformance/authored_cases{,_queries}.py`.
Reporting: `conformance/{authored_report,requirement_coverage,progress}.py`.
Behavior checks: `tests/conformance_authored{,_queries}_test.py` and
`tests/conformance_requirement_coverage_test.py`.

## Progress

- 2026-10-01: Recorded C5 outcomes, verification and scope before implementation.
  Document checks passed: 2 tests. The case catalog and stable before/after
  requirement reporting remain open.

- 2026-10-01: Added the 43-case catalog, retained shared native output/profile
  evidence, and fixed requirement aggregation to retain all rows and deduplicate
  aliases per case. Tests check storage classes, defaults, direct counts,
  trigger/cascade effects, transaction rollback, UPSERT branches, aggregates,
  joins, casts, REAL arithmetic, DISTINCT, windows, clock inputs and JSON shape.
  The shared-boundary window cuts both ends of a genuine three-row tie.
  Legacy recording still matches all 29 frozen v3 scenarios exactly.
  Focused checks: 22 passed in 7.31 seconds. Full pinned hermetic model suite:
  132 passed in 201.98 seconds; result:
  `/nix/store/vz2jkz0ncywwn7bfx7pn667dnql7xd6f-sqlite-verifier-test-model-1/junit.xml`.
  Final documents: 2 passed in 0.59 seconds. Independent contract audit found
  no actionable findings. C5 is DONE; C6–C7 and the private workload gate are open.
