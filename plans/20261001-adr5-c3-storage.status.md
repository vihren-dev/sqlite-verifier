# ADR 0005 C3 status

Created 2026-10-01. Status: DONE.
Task: [bounded storage](20261001-adr5-c3-storage.task.md).
Spec: [ADR 0005](../docs/adr-0005-conformance-corpus-scale.md).

## Current state

C3 is complete. New acquisition measures the final expanded evidence and stored
UTF-8 JSON using one serializer, excluding records above 1,000,000 bytes with
their measured size. Complete snapshots are stored once per digest and validated
before expansion at corpus load. Native versions 1–4 round-trip and replay.
Frozen v1–v3 evidence remains unchanged. Append refresh preserves inherited
observations, including legacy oversized records; C6 selects final membership.

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

- 2026-10-01: Implemented bounded acquisition and shared snapshot storage in
  native_storage.py, integrated the load boundary and repeat refresh, and retained
  profile declarations. The new [selection](../reports/20261001-adr5-c3-size-selection.json)
  applies the implemented policy to all 370 frozen v3 record sizes: only
  e_blobbytes:e_blobbytes-1.0:0 is excluded, at 302,050,086 bytes. No frozen
  artifact was rewritten. Typed BLOB parameters, outputs, groups, clocks and
  separate pending/committed states survive actual replay. Malformed digests,
  references and storage versions are refused. Exact-limit and logical-size
  checks prevent sharing from bypassing the cap. The real Tcl check retains
  size evidence and confirms a refusal does not consume selection quota.
  Final independent audit found no actionable gaps. Hermetic model suite:
  101 passed in 135.29 seconds; pinned upstream suite: 6 passed in 0.38 seconds;
  documentation checks: 2 passed. C3 is DONE; C4–C7 and the workload gate remain open.
