# ADR 0005 C3: bounded cases and shared snapshots

Created 2026-10-01. Status: IN PROGRESS.
Status: [progress](20261001-adr5-c3-storage.status.md).
Spec: [ADR 0005 §3.5](../docs/adr-0005-conformance-corpus-scale.md#35-case-size-storage-and-replay).

## Observable outcomes

New acquisition excludes a case whose uncompressed native evidence exceeds
1,000,000 UTF-8 bytes, with the reason "case size limit" and its measured size.
The limit applies before snapshot sharing, so references cannot admit a logically
oversized case. The 302 MB frozen case has a recorded size-limit exclusion in the
new selection evidence; its existing frozen artifact remains unchanged.

Each distinct snapshot within a retained case is stored once and referenced by
its content digest. Loading restores the exact observations, typed values,
outputs, parameters, profile and clock evidence. Shared storage has its own
version; it does not change the meaning of the native acquisition versions.
Malformed references, altered digests and unknown storage versions are refused.
Legacy unshared cases and frozen corpus v1–v3 remain readable and replayable.
Case selection reports keep size-limit reasons alongside other known reasons.

## Behavioral verification

Tests cover the exact size boundary, a case above the boundary, repeated initial
and trace snapshots, distinct snapshots, native replay after a storage round
trip, output/profile/clock preservation, tampered and missing snapshot references,
unknown storage versions, and unchanged legacy replay. A streaming measurement
identifies the giant frozen case and its uncompressed size without rewriting it.
Pinned upstream capture and relevant native/corpus regressions pass. Checks and
subprocesses have configured timeouts.

## Tricky points and sources

`native_record.py` creates translator-independent observations. `corpus.load`
binds the stored bytes to the manifest before model translation or native replay.
`upstream_pilot.py` retains every candidate's exclusion reasons. Existing native
format v4 adds profiles and clocks; storage must preserve those fields exactly.
Keep digest validation at the load boundary. Read existing frozen evidence without
applying a new selection cap retroactively. Preserve arrays and typed payloads;
only complete visible/persisted snapshots can be shared. C6 owns sharding, format
and profile binding for the final freeze; C7 owns replay tiers and their time cap.
