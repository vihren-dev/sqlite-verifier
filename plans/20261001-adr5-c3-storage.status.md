# ADR 0005 C3 status

Created 2026-10-01. Status: IN PROGRESS.
Task: [bounded storage](20261001-adr5-c3-storage.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C0–C2 are complete. Native records still repeat visible/persisted snapshots and
acquisition has no case-size limit. Frozen v1–v3 evidence remains unchanged.

## Sources

`conformance/native_record.py`, `conformance/corpus.py`,
`conformance/upstream_pilot.py`, `conformance/corpus-v3/cases.jsonl.gz`, and
`tests/conformance_capture_test.py`.

## Progress

- 2026-10-01: Recorded C3's observable outcomes, legacy compatibility and
  behavioral checks before implementation. Size is measured before sharing;
  selection must exclude the giant case without changing frozen evidence.

- 2026-10-01: Streaming measurement verified all 370 frozen v3 records against
  the manifest's uncompressed digest. The largest is
  e_blobbytes:e_blobbytes-1.0:0, line 184, at 302,050,086 UTF-8 JSON bytes.
  The [measurement](../reports/20261001-adr5-c3-size-baseline.json) retains the
  source, digest, exact size and method. Size-limit selection and shared snapshot
  storage remain unimplemented.
