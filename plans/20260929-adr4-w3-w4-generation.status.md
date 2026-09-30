# Bounded generation and regression freezing: status

Created 2026-09-29. Status: DONE.
Task: [Bounded generation and regression freezing](20260929-adr4-w3-w4-generation.task.md).
Spec: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

Both state-machine modes, structural round-trips, boundary probes, native law checks,
signature-preserving deletion, and kernel-checked regression freezing are implemented.
No merge is authorized.

## Transaction/DML profiling (2026-09-29)

The fixed 40-case mix covers commit, rollback, open transaction and constraint
failure after INSERT/UPDATE. Parser startup dominated acquisition. A bounded
128-entry cache now reuses immutable parsed schemas across cases, keyed by exact
SQL and parser identity; native metadata/rows are always reobserved. Acquisition
fell from 0.703s to 0.367s; compiled batches took 0.034s/0.033s, respectively
(54.2 → 99.8 cases/s). These are local warm workload measurements, not model-only
throughput. Reports: 20260929-adr4-dml-{before,after}.json; reproducible with
`python3 -m conformance.profile_dml --output build/profile.json [--uncached]`.
Validation: Nix tests.model passed all 44 tests in 57.43s. The fixed CI seed
checked 40 well-scoped and 40 error-seeking cases. The optional long run completed
with 1,016 AGREE cases per mode and no disagreements or harness errors; exact
counts include Hypothesis's additional executions. Reports and case digests are
in reports/20260929-adr4-generated{,-long}.json.

The injected transport mismatch shrinks to one INSERT, survives deletion by its
exact disagreement signature, and is retained as a kernel-checked regression
with an explicit injected/harness-bug mismatch entry. No production disagreement
was discovered. Source: conformance/{generated_program,state_machine,regressions}.py;
usage and limits: docs/conformance-generation.md.
