# ADR 0004 conformance prototype

Created 2026-09-29. Status: DONE (W1–W2).
Status: [progress](20260929-adr4-conformance-prototype.status.md).
Specification: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Completed 2026-09-29; measured evidence and requirement mapping are in the status file.

## Observable outcome

W1 and W2 provide one Lean classification authority for versioned cases containing
an explicit starting schema, typed rows and rowids, migration statements, and a
native initial/per-statement trace. Compiled classification and kernel proofs use
the same comparison. Unsupported input never receives an agreement theorem.
Observation follows production admission and advance/runSql semantics, preserves
open-transaction visible and committed states, and stops on the first error.

A persistent native runner checks the pinned SQLite identity/configuration and
records exact typed observations. All five existing fixtures retain their values
and expectations. Old comparisons remain executable until W2 demonstrates parity.
W2 reports measured throughput including native snapshots. W3 and later packages
remain subject to owner review, not part of this implementation authorization.

## Verification

Kernel checks prove final observation agrees with runSql and unsupported verdicts
cannot satisfy checkCase. Tests exercise fixture serialization (including negative
rowids, NULL, UTF-8 and 2000 columns), every admitted structural constructor, native
parity for the five cases, a wrong trace and injected mutation, transactional writes
and errors, and unsupported data. Axiom audits reject sorryAx, ofReduceBool and
native proof axioms. Subprocesses and tests have explicit bounded timeouts.
Native integration runs through the pinned Nix environment; throughput measurements
state platform, input counts and elapsed time without claiming universal refinement.

## Constraints and existing code

Reuse packages/belay-sqlite/Belay/Sqlite/SqlExecution.lean admission and transitions; Execution.lean's
step is a legacy DDL helper. Database remains function-valued; observations use
finite names including fixture, statement and native schema names.
conformance/model_cases.py supplies existing fixtures; model_check.py and
model_assertions.py retain the baseline until native parity is established.
migration_check/sql_model.py and sql_inputs enforce production frontend admission.
The structural format is shared with ADR 0003 P3 without depending on its approval.
build-support sources and tests determine Nix cache inputs. Native library pinning,
transaction observation, error normalization and exact byte/REAL encoding must be
explicit; harness failures never count as agreement. Preserve the product API and
trust policy.
