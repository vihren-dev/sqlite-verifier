# Model structure refactor after ADR 0012: status

Created 2026-10-17. Status: open.
Task: [20261017-model-structure-refactor.task.md](20261017-model-structure-refactor.task.md).
Decisions: [ADR 0012 amendment 6](../docs/adr-0012-query-semantics.md) (proposed).

## Baseline (2026-10-17, after slice 6g, #156)

- `packages/belay-sqlite`: 159 files, 16,199 lines, 871 `def`, 218 `theorem`; core
  module count 127; clean build 33 s wall; `tests.model` 334 s.
- Verdict counts: v1 13/164, v2 19/164, v3 62/308, v4 302/962, v5 926/3450, v6 38/3,
  v7 to v28 all agree, synthetic-workload 0/2 (AGREE/MODEL_UNSUPPORTED).

## Relevant files

- Resolution: `Resolution/Context.lean`, `Writes.lean`, `Updates.lean`, `Deletes.lean`,
  `Sources.lean`, `Queries.lean`, `Resolve.lean`, `Resolved.lean`, `Values.lean`,
  `Messages.lean`, `ErrorKinds.lean`, `IssueLemmas.lean`, `OperandIssues.lean`,
  `PrepareRules.lean`, `UpdateRules.lean`, `UpsertRules.lean`, `ClockRowRules.lean`,
  `PrepareSpec.lean`.
- Execution: `Execution.lean`, `StatementStep.lean`, `LiteralData.lean`, `UpsertRun.lean`,
  `JsonReady.lean`, `Laws.lean`, `SqlProofs.lean`, `StatementClock.lean`,
  `Resolution/SchemaScript.lean`, `Resolution/TransactionSpec.lean`.
- Anchors and inputs: `conformance/*_mutants.py`, `conformance/instrument_model.py`,
  `conformance/mutation_check.py`, `build-support/tests.nix`, `tests/test_model_package.py`.

## Progress

- 2026-10-17: task and status files, and the amendment 6 proposal, stacked on #157.

## Remaining

- Items 1 to 7 of the task, each as reviewed commits; pull request.
