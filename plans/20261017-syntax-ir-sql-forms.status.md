# Syntax IR around SQL forms (ADR 0013, step 1): status

Created 2026-10-17. Status: open.
Task: [20261017-syntax-ir-sql-forms.task.md](20261017-syntax-ir-sql-forms.task.md).
Specification: [ADR 0013](../docs/adr-0013-model-structure.md), D3 and D7, step 1.

## Baseline (2026-10-17, after slice 6g, #156)

- `packages/belay-sqlite`: 159 files, 16,199 lines, 871 `def`, 218 `theorem`; core
  module count 127; clean build 33 s wall; `tests.model` 334 s.
- Verdict counts: v1 13/164, v2 19/164, v3 62/308, v4 302/962, v5 926/3450, v6 38/3,
  v7 to v28 all agree, synthetic-workload 0/2 (AGREE/MODEL_UNSUPPORTED).
- `expr2:expr2-1.4.1:5` (corpus v5) is `MODEL_UNSUPPORTED` by `boolean-name`.

## Relevant files

- Syntax: `Resolution/SyntaxExpr.lean`, `Syntax.lean`, `Codec/Resolution.lean`;
  frontend `belay/sqlite/syntax_queries.py`, `syntax_expressions.py`,
  `syntax_writes.py`, `syntax_definitions.py`, `syntax_sources.py`.
- Resolution: `Resolution/Calls.lean`, `QueryExprs.lean`, `Queries.lean`,
  `Returning.lean`, `Resolve.lean`, `Writes.lean`, `Updates.lean`, `Deletes.lean`,
  `Upserts.lean`, `Defaults.lean`, `ReadDefaults.lean`, `Context.lean`,
  `Definitions.lean`, `Catalog.lean`, `Sources.lean`, `SyntaxScope.lean`.
- Execution and proofs: `Execution.lean`, `StatementStep.lean`, `Laws.lean`,
  `SqlProofs.lean`, `StatementClock.lean`, `ClockSubstitution.lean`, `JsonFaults.lean`.
- Fixtures and anchors: `conformance/cases/*.json`, `conformance/regressions/`,
  `conformance/*_mutants.py`, `tests/syntax_*_test.py`, `tests/test_model_package.py`,
  `examples/*/Generated`.

## Progress

- 2026-10-17: ADR 0013 proposed (#158); task and status files.

## Remaining

- Items 1 to 10 of the task, as reviewed commits; pull request A; pull request B if the
  `boolean-name` case agrees.
