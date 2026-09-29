# ADR 0004 conformance prototype status

Created 2026-09-29. Status: ACTIVE.
Task: [outcomes and checks](20260929-adr4-conformance-prototype.task.md).
Specification: [ADR 0004](../docs/adr-0004-model-conformance-validation.md).

## Progress

- Created dedicated jj workspace `adr4` at `../sqlite-verifier-adr4`, based on
  `8c4e5ad4` (ADR revision `acadc4cc`). Original workspace unchanged.
- Read production model, execution, frontend emission, existing conformance
  assertions, and Nix build/test boundaries. Started baseline runtime build.
- Planning committed as `907a251a`; both Markdown checks passed.
- W1 trace foundation implemented in `SqliteVerifier/ConformanceTrace.lean`:
  initial and per-statement finite observations, sorted physical rows, both database
  views, transaction status, and modeled error positions. The fold calls production
  `advance` and stops at `.halt`. `trace_final` proves its final observation equals
  the observation of `runSql`, for every script and initial database.
- The pinned runtime builds. The focused kernel regression passes (0.82 seconds),
  checking pending writes, commit, rollback, constraint and nested-BEGIN failures,
  empty scripts, no-active-transaction errors, and forbidden proof axioms.
- The trace regression is included in the Nix model target and excluded from
  duplicate host execution by `just test`. Existing native/model comparisons remain.
- Sandboxed `tests.model` passed all seven cases in 32.54 seconds on aarch64-darwin
  (five native/model fixtures, lost-row rejection, and the trace regression).
  Both Markdown checks also pass. No Linux execution or native trace evidence is
  claimed by this slice.
- The stdlib merge sort did not reduce in concrete kernel checks. A structurally
  recursive insertion sort handles the small finite observation fixtures; its
  quadratic ceiling is documented. This does not alter production row storage.

## Remaining work

W1 is not complete: the versioned case/statement encoding, classifier/admission
boundary, native error normalization, five-case serialization, and compiled/kernel
comparison still remain. W2's persistent native runner and throughput evidence
have not been implemented. The current trace test is model evidence only.

## Relevant sources

- `SqliteVerifier/SqlExecution.lean`, `Execution.lean`, `Model.lean`
- `SqliteVerifier/ConformanceTrace.lean`, `tests/conformance_trace_test.py`
- `conformance/model_cases.py`, `model_check.py`, `model_assertions.py`
- `migration_check/sql_model.py`, `build-support/default.nix`, `tests.nix`
