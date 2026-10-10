# Syntax and resolution core, step 1a of ADR 0008

Created 2026-10-10. Status: IN PROGRESS.
Specification: [ADR 0008](../docs/adr-0008-syntax-and-resolution-in-lean.md),
"Three layers", "Catalog", "Errors from resolution", "Specification of
resolution", "Execution profile" and "Scope of the first implementation".

## Plan of the ADR work (owner decisions of 2026-10-10)

The ADR has no step plan. The owner chose three steps; after a survey of the
dependents, step 1 is split in two pull requests:

- **Step 1a (this task):** the new Lean layers in the `Belay.Sqlite` core,
  added next to the current model. Nothing in the verifier, the gates, the
  generated inputs or the conformance harness uses them yet.
- **Step 1b:** the switch. The Python frontend maps the parser tree to
  `Syntax`; the execution semantics, `Conforms` and the verification target
  use the catalog and `Resolved`; the gate and the bundle checker run
  `resolve` and compare; the approved example files and their baselines
  change; Python resolution, `Schema`, `DeclaredType`, `maximumColumns`, the
  profile enumeration and the named `Statement` type are deleted. The survey
  counts about 1,100 lines of proofs and 8 approved files that change.
- **Step 2:** profile limits measured by the recorder, the error phase in the
  case format, the authored coverage shard and the mutants.
- **Step 3:** `Syntax` and `resolve` for the query and expression syntax of
  ADR 0005, section 1.3. Python keeps refusing that syntax until the model
  can execute it.

## Outcome

1. **`Syntax`.** Statements as written for the seven statements of the first
   scope, and the schema statements that describe a starting catalog:
   CREATE TABLE (column definitions with the declared type text, NOT NULL,
   PRIMARY KEY with its sort order, UNIQUE and DEFAULT; table PRIMARY KEY and
   UNIQUE constraints), CREATE INDEX, ALTER TABLE ADD COLUMN, BEGIN, COMMIT,
   ROLLBACK, INSERT with an optional column list and VALUES rows, and UPDATE
   with assignments and an optional WHERE. Names are text as written; omitted
   parts are `none`. Numeric literals keep their token text.
2. **Profile.** A structure with the release, the source id, the effective
   limits of the ADR's table and the double-quoted-string settings, and the
   documented defaults of a release. No limit is a constant elsewhere in the
   new code.
3. **Catalog.** One namespace of tables and indexes. Entries keep the name as
   written; lookup uses SQLite's ASCII folding. Columns keep the declared type
   text; the affinity function states SQLite's rules, and the rowid alias rule
   uses the type text and the sort order.
4. **`Resolved` and `resolve`.** `resolve` takes the profile, a catalog and a
   script, and gives for each statement a resolved statement or a SQLite
   prepare error at its position, or refuses the script with a model
   restriction that names the statement index and the node path. Resolved
   statements use catalog positions: table positions, column positions, full
   INSERT rows in table order with defaults, and converted literal values.
   BEGIN saves the catalog, ROLLBACK restores it, COMMIT drops the copy; a
   statement after a prepare error is resolved as if that statement had no
   effect. Each prepare error names the SQLite message format; each model
   restriction says that SQLite accepts the SQL. Numeric literal text is
   converted with SQLite's rules (a decimal integer outside the 64-bit range is
   REAL, which the first scope refuses as a model restriction).
5. **Specification and proofs.** Declarative rules with plain-words docstrings
   and documentation references, and theorems that `resolve` meets them:
   column reference, row width, unique names after each successful statement,
   prepare errors for missing and used names, and the catalog after ROLLBACK.

## Tests

- The Lean theorems above, checked when the package builds.
- Lean `#guard` examples of `resolve` for each statement and each prepare
  error, each limit at and above the profile value under a profile with a
  lowered limit, the affinity rules (including "CHARINT", "FLOATING POINT" and
  no type), the rowid alias with `DESC`, ASCII-only folding, a table and an
  index with one name, and ROLLBACK. They run in the compiled evaluator at
  build time, not in the kernel.
- The public documentation inventory covers the new declarations.

## Relevant source and constraints

- `packages/belay-sqlite/lakefile.toml` lists every module; the root package
  and `build-support/model-package.nix` build it. `docs/review-checklist.md`
  R2, R3, R5 and R7 apply to every new Lean definition.
- Existing names that stay until step 1b: `Belay.Sqlite.ExecutionProfile` (the
  enumeration), `Statement`, `Schema`, `normalizeIdentifier` and `Affinity`.
  The new layer reuses `Affinity`, `Value` and `normalizeIdentifier`, and uses
  new names where the old ones are still taken (for example `Profile`).
- SQLite's prepare errors in the first scope come from `sqlite3StartTable`,
  `sqlite3AddColumn`, `sqlite3AlterFinishAddColumn`, `sqlite3CreateIndex`,
  `sqlite3Insert` and `sqlite3Update`. COMMIT and ROLLBACK without a
  transaction and BEGIN in a transaction fail when the statement runs, not
  when it is prepared; they stay in the execution semantics.
- CI time: the new modules add Lean compile time to `modelPackage`,
  `leanRuntime`, `conformanceRuntime` and the API reference. Kernel-evaluated
  examples are slow (the ADR measured 116 s for 70 statements), so the tests
  use `#guard` and the proofs are about the definitions, not about large
  concrete scripts. Build times before and after are recorded in the status.
