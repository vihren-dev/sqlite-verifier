# Literal defaults in the ADR 0012 stack, slice 6e1 of ADR 0012: status

Created 2026-10-17. Status: open.
Task: [20261017-defaults-integration.task.md](20261017-defaults-integration.task.md).
Specification: [ADR 0012](../docs/adr-0012-query-semantics.md), Amendment 5, owner
decisions 8 and 9.

## Relevant files

- #130: `tasks/constant-column-defaults` (head `ae14a73b02c3`), its task and status files.
- Conflicts of a trial merge: `docs/semantic-subset.md`, `Codec/Resolution.lean`,
  `Execution.lean`, `Resolution/Catalog.lean`, `Resolution/Context.lean`,
  `Resolution/Definitions.lean`, `Resolution/Syntax.lean`, `Resolution/Writes.lean`,
  `SchemaExtension.lean`, `SqlExecution.lean`, `VerifierConformance/Case.lean`,
  `Outputs.lean`, `Predict.lean`, `tests/conformance_pipeline_test.py`,
  `tests/syntax_mapping_test.py`, `tests/test_model_package.py`.

## Progress

- 2026-10-17: owner decisions 8 (clock domain and relation) and 9 (build on #130)
  recorded in ADR 0012; task and status files, stacked on #149.

- 2026-10-17: merge of `tasks/constant-column-defaults` (#130, head `ae14a73b02c3`). The
  conflicts were the column constraints, which #130 gave a source spelling
  (`Syntax.DefaultExpression`, `ColumnConstraint.default value sourceText`) and slice 5d
  conflict algorithms: both kept; #130's syntax change moved to `Resolution/SyntaxExpr.lean`,
  where the stack keeps `Expr` and `ColumnConstraint`. Interactions: #130's default code
  gains the stack's `Syntax.Expr.more`; `ExecutionError.nullColumnDefault` joins the
  stack's error mappings; ADD COLUMN `NOT NULL` keeps its `ON CONFLICT` algorithm as in
  CREATE TABLE. #130 made `Model.lean` import `StoreValueLaws` and kept two lemmas in
  `ReadDefaults.lean`, which put the laws of `storeValue` into the build of every mutant
  copy, so the mutant `real_column_keeps_integer` no longer compiled: `Model.lean` imports
  `StoreValue` again and the lemmas moved to `Resolution/ReadDefaultLaws.lean` (core
  modules 107). Authored cases `conformance/authored_default_writes.py` (8, all AGREE):
  omitted values with a rowid alias, affinity, `NOT NULL`, a unique conflict,
  `ON CONFLICT`, `INSERT OR`, `RETURNING`, and an added column; corpus writer
  `conformance/default_write_evidence.py` (corpus 25). `test-full`, `test-nix` and
  `test-scheduled` pass.

## Remaining

- Review, CI time, pull request A; then pull request B (corpus 25 and cases that newly
  agree). Then slice 6e2 (the clock).
