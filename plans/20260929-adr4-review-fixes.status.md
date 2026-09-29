# ADR 0004 review correction status

Created 2026-09-29. Status: ACTIVE.
Task: [review outcomes](20260929-adr4-review-fixes.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Review confirmed the connection-profile, independent metadata, streaming, and
proof-term gaps. Corrections will be committed as individually checked changes.
Original W2 report remains historical evidence until a replacement is measured.

Connection profile corrected: removed the global DQS build override; both writer
and reader explicitly disable and independently read back DQS_DML/DQS_DDL.
Live pinned-library test passed (1 test), including DML and DDL rejection.

Independent metadata validation added in `conformance/native_metadata.py`. Native
column fields, affinity, keys and indexes are cross-checked; ten translator faults
are rejected. Live pipeline and original fixture suites passed (17 tests).

Schema declarations are parsed once per distinct schema in a case; visible and
committed views share the content-keyed cache. Benchmark cases share one runner
process and report acquisition/classification separately. Six transaction/cache/
batch tests passed, including rollback followed by different DDL and malformed
input between valid cases. A fresh final benchmark is still pending.

Generated proofs now guard the elaborated term’s re-encoding against the original
case JSON. All five frozen cases pass; a changed provenance payload fails the
guard even though the semantic theorem still passes (metadata test verified).

Conformance now lives in the separate `VerifierConformance` Lean library. The
production import closure and Nix source set exclude it and the runner. The
rebuilt conformance suite passed 21 tests; 54 Nix identity/target tests passed,
including explicit isolation of conformance edits from the production Lean source.

Fixture setup now binds typed parameters instead of rendering SQL literals.
Infinity signs and bits survive; SQLite converts NaN to NULL, which is reported
as an initial-state disagreement against a requested NaN REAL. The storage test
and five frozen-case replays passed (6 tests), including kernel round-trip guards.

Final metadata audit corrected ASCII identifier folding without importing the
production translator helper. Mixed-case table/column/index names and mutation
checks pass (2 focused tests).

Final timing isolates classification from optional proof-term emission as well as
kernel checks. The real pipeline run passed all 15 cases and all five proofs;
0.75476 s native acquisition + 0.28403 s compiled batch = 14.44 cases/s.
The timed batch uses one process; proof terms use one separate untimed batch.
