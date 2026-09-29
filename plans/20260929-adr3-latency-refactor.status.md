# ADR 0003 latency-first refactor status

Created 2026-09-29. Status: DONE.
Task: [ADR 0003 latency-first refactor](20260929-adr3-latency-refactor.task.md).
Sources: [ADR 0003](../docs/adr-0003-agent-proof-preparation.md),
[component research](../docs/0003-component-research.md),
ADR 0004 (draft, not yet published),
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
- 2026-09-29: Revised after review: the decision is now a bounded comparative
  experiment (data path versus tuning) with per-platform relative thresholds on
  acceptance and edit-to-result time; approved-contract reuse adopts ADR 0002's
  determinism/eligibility policy with a fresh-compile fallback; projections are
  shown with fresh and reused contracts; future trust is a separate benefit with
  its cost stated. Docs link check passes.
- 2026-09-29: Second review: made the P1 decision outcomes mutually exclusive
  (ordered: adopt, owner decision, ship tuning; mixed-platform results ship
  tuning; tuning itself must pass correctness and no-regression checks, else keep
  the current path) and clarified that P4 applies to whichever option ships.
