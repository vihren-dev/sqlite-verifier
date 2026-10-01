# ADR 0005 C5 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [neutral authored cases](20261001-adr5-c5-authored.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C0–C4 are done. C5 research identified 29 legacy requirement scenarios without
output/profile evidence and a compact neutral catalog for the ADR's feature,
boundary and interaction categories. No new authored records are frozen yet.

The coverage report uses the complete 3,500-row inventory as a fixed denominator.
JSON has no row in this inventory and is tracked by feature metadata. Existing
comparator rejection and probe safety tests remain the evidence for invalid
outputs and refused probes; invalid records do not become corpus members.

## Sources

`conformance/{requirement_cases,native_record,execution_profile,corpus,progress}.py`,
`conformance/requirements-3.51.0.json`, and
`tests/conformance_{ordering,clock,profile,coverage}_test.py`.

## Progress

- 2026-10-01: Recorded C5 outcomes, verification and scope before implementation.
  Document checks passed: 2 tests. The case catalog and stable before/after
  requirement reporting remain open.
