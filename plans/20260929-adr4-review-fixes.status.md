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
