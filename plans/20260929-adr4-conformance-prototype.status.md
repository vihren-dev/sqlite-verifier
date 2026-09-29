# ADR 0004 conformance prototype status

Created 2026-09-29. Status: ACTIVE.
Task: [outcomes and checks](20260929-adr4-conformance-prototype.task.md).
Specification: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Progress

- Created dedicated jj workspace `adr4` at `../sqlite-verifier-adr4`, based on
  `8c4e5ad4` (ADR revision `acadc4cc`). Original workspace unchanged.
- Read production model, execution, frontend emission, existing conformance
  assertions, and Nix build/test boundaries. Started baseline runtime build.
- No implementation or prototype evidence yet. W1/W2 remain outstanding.

## Relevant sources

- `SqliteVerifier/SqlExecution.lean`, `Execution.lean`, `Model.lean`
- `conformance/model_cases.py`, `model_check.py`, `model_assertions.py`
- `migration_check/sql_model.py`, `build-support/default.nix`, `tests.nix`
