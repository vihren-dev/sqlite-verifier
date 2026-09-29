# ADR 0003 latency-first refactor status

Created 2026-09-29. Status: DONE.
Task: [ADR 0003 latency-first refactor](20260929-adr3-latency-refactor.task.md).
Sources: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md),
[component research](../docs/0003-component-research.md),
[ADR 0004](../docs/adr-0004-model-conformance-validation.md),
`migration_check/cli.py`, `migration_check/compile.py`, `ProofChecker.lean`.

## Progress log

- 2026-09-29: Reviewed ADR 0003 with the document refactoring process; owner
  chose latency first, trust later.
- 2026-09-29: Measured the current path and a lean4export-based data path on
  aarch64-darwin; added reproducible experiments under
  `experiments/adr-0003-latency/`.
- 2026-09-29: Rewrote ADR 0003 around the latency milestone; moved deferred
  adversarial design to `docs/adr-0003-trust-extension.md`; marked conflicts in
  the component research. Docs link check passes.
