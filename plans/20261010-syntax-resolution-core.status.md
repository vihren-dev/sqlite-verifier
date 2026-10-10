# Status: syntax and resolution core, step 1a of ADR 0008

Created 2026-10-10. Status: IN PROGRESS.
Task: [task](20261010-syntax-resolution-core.task.md).
Specification: [ADR 0008](../docs/adr-0008-syntax-and-resolution-in-lean.md).

Relevant files: `packages/belay-sqlite/Belay/Sqlite/`,
`packages/belay-sqlite/lakefile.toml`, `conformance/requirements-3.51.0.json`.

## Findings

- Dependents of the replaced model (survey, 2026-10-10): about 1,100 lines of
  theorem and example bodies use `Schema`, `Statement` or `runSql`; the gate
  names the generated declarations in `GateCore.expectedTarget`; the bundle
  checker builds `nextSchema`, `script` and `profile` from the structural
  record; Python computes `nextSchema` with `transition`; 8 approved files
  mention the replaced names, and their `baseline.json` hashes are written by
  hand.
- Baseline build times on `main` (`5a813d20`), forced rebuild with
  `nix-build --check` in the sandbox, Linux amd64: `modelPackage` 7 s,
  `leanRuntime` 13 s, `conformanceRuntime` 17 s, `publicDocumentation` 5 s.

## Progress

- 2026-10-10: PR #79 merged first (owner decision). Task and status files
  created in the jj workspace `adr8-step1`.

- 2026-10-10: the Lean core layers, all in `packages/belay-sqlite/Belay/Sqlite/`:
  `Profile`, `Syntax`, `Catalog` (affinity and rowid alias rules), `Resolved`
  (prepare errors with SQLite's message formats, model restrictions),
  `ResolveValues`, `ResolveDefinitions`, `ResolveWrites`, `Resolve`, and the
  specification modules `ResolveSpec` (column reference), `ResolveRowSpec`
  (row width), `ResolveCatalogSpec` and `ResolveNamesSpec` (unique names, per
  statement and per script), `ResolveErrorKinds`, `ResolvePrepareSpec`,
  `ResolvePrepareRules` and `ResolveDefinitionRules` (prepare errors for
  missing and used names, both directions, for every statement),
  `ResolveTransactionSpec` (catalog after ROLLBACK): 51 theorems. `ResolveExamples` has 30
  `#guard` checks. `LiteralData.lossless` takes an affinity, so the old model and
  `resolve` share it. The prepare checks follow the order of the 3.51.0
  functions `sqlite3StartTable`, `sqlite3AddColumn`, `sqlite3AddPrimaryKey`,
  `sqlite3CreateIndex`, `sqlite3AlterBeginAddColumn`,
  `sqlite3AlterFinishAddColumn`, `sqlite3MultiValues`, `sqlite3Insert` and
  `sqlite3Update`, read in the vendored `parser/upstream/sqlite3.c`.
- Findings from the SQLite source: the first error wins, because
  `sqlite3RunParser` stops at the first error; the rowid alias needs the
  declared type exactly `INTEGER` (`COLTYPE_INTEGER`, case-insensitive after
  dequoting) and no `DESC` in the column constraint, while a table
  `PRIMARY KEY (x DESC)` is still an alias; `DEFAULT name` stores the name as
  text; COMMIT and ROLLBACK without a transaction fail at step, not at prepare.

## Remaining

- Full checks, the review, the CI time comparison and the pull request.
