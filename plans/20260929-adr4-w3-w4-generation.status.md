# Bounded generation and regression freezing: status

Created 2026-09-29. Status: ACTIVE.
Task: [Bounded generation and regression freezing](20260929-adr4-w3-w4-generation.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Outcomes and validation recorded; implementation pending. No merge is authorized.

## Transaction/DML profiling (2026-09-29)

The fixed 40-case mix covers commit, rollback, open transaction and constraint
failure after INSERT/UPDATE. Parser startup dominated acquisition. A bounded
128-entry cache now reuses immutable parsed schemas across cases, keyed by exact
SQL and parser identity; native metadata/rows are always reobserved. Acquisition
fell from 0.703s to 0.367s; compiled batches took 0.034s/0.033s, respectively
(54.2 → 99.8 cases/s). These are local warm workload measurements, not model-only
throughput. Reports: 20260929-adr4-dml-{before,after}.json; reproducible with
`python3 -m conformance.profile_dml --output build/profile.json [--uncached]`.
Native metadata/cache/batch checks pass. Generator and regression freezing remain.
