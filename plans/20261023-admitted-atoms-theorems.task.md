# The theorems of the Admitted atoms (ADR 0022, slice 4)

Created 2026-10-23. Status: DONE (2026-10-24). On 2026-10-23 the owner accepted the recommendation of each
decision of the status file, except decision 5, where the owner first chose b) (a restriction) and
on 2026-10-24 chose a) (the model keeps a repeated key column, see the amendment below);
decision 3 repeats a decision of 2026-10-23 (slice 3, decision 3 a)).

Amendment of 2026-10-24 (decision 5 is a)). Option b) was wrong on one fact: the frozen corpora
corpus-v4 and corpus-v5 contain the authored cases `validity-repeated-primary-key` and
`validity-repeated-unique-key`, which are in `mustAgree` of `judge/claims.json`, so a restriction
of a repeated key column makes them `MODEL_UNSUPPORTED` and breaks the claims. The text "No corpus
case runs either" was wrong. Decision 5 is now a): the model resolves a repeated key column as
SQLite does, `supportedKey` allows it, and the facts of slice 2 must hold for such keys. Every
sentence below that names a restriction of a repeated key column is replaced by this decision.
Status file: [status](20261023-admitted-atoms-theorems.status.md).
Specification: [ADR 0022](../docs/adr-0022-database-validity.md), D1, D3 and D4 (slice 4).
Needed by: S4 of the user surface ([ADR 0017](../docs/adr-0017-user-surface.md)): a run of the
bundled database over every database (D5: the run keeps `Database.Valid`).
Follows: [slice 2](20261023-keys-unique.task.md) ("keys unique") and
[slice 3](20261023-valid-atoms-theorems.task.md) ("the other Valid atoms"). They proved the run
theorems with conditions on CREATE INDEX, ADD COLUMN and DROP, and left the resolver facts that
discharge the conditions to this slice.

## Scope

The model gets theorems that its statement step (`runStatement`) and its runs keep the seven atoms
of `Database.Admitted` (`DatabaseFacts.lean`): the catalog is supported (`Catalog.Valid`), rows
shaped, rowids distinct, rowids in range, rows wide, rows stored and rows aliased. It also gets the
resolver facts that discharge the run conditions of slices 2 and 3 for `runScriptFrom`, and
the corollary that a run keeps `Database.Valid`. The statement step does not change. The resolver
changes in one small way (owner decision 4): it refuses a CREATE INDEX with no terms, and a
`PRIMARY KEY` or `UNIQUE` with no column, with a prepare error (SQLite gives a syntax error for
`CREATE INDEX i ON t()`, `PRIMARY KEY()` and `UNIQUE()`). A repeated key column, such as
`PRIMARY KEY(a, a)`, stays modeled (decision 5 a)). No corpus case runs an empty key list, since
SQL text cannot give one, and the cases of repeated keys keep their predictions, so the
predictions, the claims and the judge lock do not change.

Out of scope: "foreign keys hold" (slice 5); the removal of the check `Run.checked`, and
the S4 claims over every database (ADR 0017, S4); an atom for the cells of generated columns
(ADR 0022, "Not decided here").

## Outcome

1. **The statement theorems.** One theorem for each of the seven atoms. For every clock, parameter
   list, resolved statement and database: if the database satisfies the atom (and the atoms that
   the theorem lists in its docstring, status file decision 2), the statement meets the condition
   of the theorem, and the run of `runStatement` is ready (`StatementRun.ready`, status file
   decision 1), then the databases that a run keeps from the effect satisfy the atom. These are
   the database of `ok` and the database of an `error` with the reason `constraintFail`, as in
   slices 2 and 3 (`Effect.Satisfies`). The theorems cover each constructor of
   `Resolved.Statement`, as slice 3 lists them, and the pragma forms of ADR 0019, slice 2: a
   pragma writes no row (`Resolved.Statement.setting`).
2. **The resolver facts.** For each statement that `resolveStatement` makes over a connection whose
   catalog satisfies `Catalog.Valid`:
   - **CREATE TABLE, CREATE INDEX and CREATE TRIGGER** give a catalog that satisfies `Catalog.Valid`.
     For CREATE INDEX this includes `CatalogIndex.supported`, which the resolver does not check
     today (`resolveCreateIndex`, `Resolution/Definitions.lean`). A CREATE INDEX with no terms
     is the case that fails; the status file, decision 4, decides how it is handled. A CREATE
     TABLE with a repeated key column, such as `PRIMARY KEY(a, a)`, resolves to a table that
     satisfies `CatalogTable.supported` (decision 5 a)): `supportedKey` allows the repeat.
   - **DROP** gives a catalog that satisfies `Catalog.Valid`. This is stronger than
     `Catalog.DropCondition` (`KeysUniqueDrop.lean`), which covers only unique indexes: every
     index that the drop keeps keeps its table, and every trigger that it keeps keeps its table.
     `Catalog.DropCondition` follows from it.
   - **ADD COLUMN** gives a catalog that satisfies `Catalog.Valid`, meets
     `Database.AddColumnCondition` (the keys read below the width), and meets
     `Database.StrictDefaultFitsAt`. With `Database.Admitted.rowsWide` it meets
     `Database.RowsWideAt`.
   - **The alias schema** (status file, decision 8). If a table has a rowid alias, the alias column
     is not generated, has INTEGER affinity, and is the only primary key column, and the table is not
     `WITHOUT ROWID`. `Catalog.Valid` states it, and the CREATE TABLE that the resolver makes gives it.
     Without it, the generated alias is a counterexample (see "Conditions").
   - **Each CHECK reads only the columns of its table** (status file, decision 3, owner decision
     3 a) of slice 3). `CatalogTable.supported` states it, so `Catalog.Valid` carries it, and the
     resolver facts above include it: the CHECKs that CREATE TABLE and ADD COLUMN resolve read
     below the width of their table. With it, `Database.ChecksReadBelowAt` follows from
     `Catalog.Valid`.
3. **The run theorems.** For each atom, for `runSqlFrom` (so `runSql`) and for `runScriptFrom`,
   with the generic layer of slices 2 and 3 (`RunHolds`, `ScriptRunHolds`). The `runSqlFrom`
   theorems keep the hypotheses on the reached statements, because `runSqlFrom` takes resolved
   statements that the resolver did not make. They also assume `supportedSqlFrom`, or an
   equivalent statement of `ready`, at each reached statement (decision 1). The `runScriptFrom`
   theorems assume only that the start database and its snapshot satisfy the atom (and the atoms
   that the theorem lists), and that the resolution context uses the profile of the atom: they lose
   the conditions of CREATE INDEX, ADD COLUMN and DROP, and `ready` comes from the run itself
   (`runScriptStepWith` ends the run when the statement is not ready).
4. **The existing run theorems.** The `runScriptFrom` theorems of slices 2 and 3 lose their
   hypotheses on CREATE INDEX, ADD COLUMN, DROP and the CHECKs: they assume that the start database
   and its snapshot satisfy `Database.Admitted` and the atom. Their `runSqlFrom` forms keep the
   hypotheses. The scripts of the existing examples still run.
5. **The corollary.** For `runScriptFrom`, if the start database and its snapshot satisfy
   `Database.Valid` for a profile with the limits of the resolution context, the connection of the
   result satisfies it too (database and snapshot). A second form for the surface: the program run
   `Sql.runFrom` (`packages/belay/Belay/Sqlite/ProgramRun.lean`) keeps `Database.Valid` over every
   program of the surface (status file, decision 6).
6. **The frame lemmas.** A statement keeps the atom of a table when the effect leaves the table's
   rows and catalog entry unchanged, for the atoms of one table. A stronger form where the atoms
   allow it: each row of the table after is a row of the table before.
7. **Plain words.** Each new proposition has a plain-words docstring; each theorem that other
   proofs use, and each proof longer than about 20 lines, has a proof sketch.
8. **Findings.** A proof that fails for a statement form is a finding (ADR 0022, D3). The status
   file records it with a counterexample, and it goes to the owner. No hypothesis assumes it
   away. The status file lists the findings that the measurement found before the slice began.

## Conditions

The statement theorems of the table atoms need `ready`, unlike the theorems of slices 2 and 3.
`StatementRun.ready` is true when the statement stays inside what the model describes
(`insertReady`, `updateReady`, `upsertReady` and `keyReady`): the rowids of the rows written are
signed 64-bit integers, the values written are in stored form, an insert row has one value for
each column, and the rowid alias is ready. Expected counterexamples (the examples must show them;
a counterexample that cannot be built is a finding):

- **Rowids in range.** A table with a row of rowid 2^63-1: an INSERT without a rowid gives the
  rowid 2^63 (`nextRowid` is the maximum plus one) with the effect `ok`. The statement is not
  ready. SQLite chooses a random rowid there, which the model does not describe.
- **Rows stored.** A resolved INSERT whose `.value` cell is not in the stored form of its column
  (for example a TEXT value in an INTEGER column): `rowsAt` takes a `.value` cell as it is.
- **Rows wide.** A resolved INSERT whose row has fewer values than the table has columns. The
  resolver always fills the full width (`Resolved.Statement.insert`), so this is a statement of
  `runSqlFrom` only.
- **Rows aliased.** A resolved INSERT into a table with a rowid alias whose alias cell is not the
  rowid (`aliasReady`).

- **Rows aliased, from the schema.** A table that a Lean user builds with a generated INTEGER column
  as its rowid alias (`rowidAlias := some 0`, the column `generated`): an INSERT into it is ready
  (`aliasReady` checks only the affinity), and `newCells` computes the generated cell after it sets the
  alias cell, so the alias cell is not the rowid. No resolved statement makes such a table
  (`generatedInPrimaryKey`). The condition is a fact of the catalog, not of `ready`.

Each of the first four is a hypothesis of `ready` for `runStatement` and `runSqlFrom`, and no hypothesis for
`runScriptFrom`. The statements of the schema (CREATE, DROP, ADD COLUMN) have conditions that
the resolver facts discharge, as in "Outcome".

## Parts

The status file proposes three parts, each with its own `just test-full` and `just verdict`
(owner decision 7):

- **Part 1:** the model changes and the resolver facts: the CHECK condition and the alias schema in
  `CatalogTable.supported`, `supportedKey` that allows a repeated key column (decision 5 a)) with the
  facts of slice 2 for such keys, the refusal of an index with no terms (decision 4), and the facts
  for CREATE TABLE, CREATE INDEX, CREATE TRIGGER, ADD COLUMN and DROP. It starts on top of slices 2
  and 3.
- **Part 2:** the statement theorems for the seven atoms: the frame lemmas, the schema statements,
  the plain writes and upsert, and the row engine (an instance of `RowEngineFacts`).
- **Part 3:** the run theorems, the loss of the hypotheses of `runScriptFrom`, the corollary, the
  surface form, and the examples of the run.

## Tests

- **The theorems compile without `sorry`.** A test compiles a check file against the model with
  `compile_checks` (`tests/shared_table_shape_test.py`), as `tests/valid_atoms_theorems_test.py`
  does: it restates the formulas of the statement theorems, the run theorems and the corollary of
  this slice, and refuses `sorryAx`, `ofReduceBool` and `_native` in the `#print axioms` output
  (only `propext`, `Classical.choice` and `Quot.sound` are allowed).
- **Kernel examples** in a compiled examples module of the model (in the package globs, not in
  the root import, as `ValidAtomsExamples.lean`), checked by `decide +kernel`:
  - the counterexamples of "Conditions", each shown with the atom before and after;
  - the counterexamples of the conditions that stay in the `runSqlFrom` theorems;
  - a `runScriptFrom` theorem applied to a script that CREATE INDEX, ADD COLUMN, DROP TABLE (with
    an index and a trigger), a write that cascades, and a ROLLBACK, with no hypothesis on the
    statements;
  - the resolver facts on concrete statements: `PRIMARY KEY(a, a)` and `UNIQUE(a, a)` resolve to a
    catalog that satisfies `Catalog.Valid`, the prepare error of a CREATE INDEX with no terms, and
    a CHECK that names a column of the table.
- **No new conformance evidence.** The prepare error of decision 4 describes a syntax error that SQL
  text cannot reach (SQLite and the frontend refuse the text), so only a syntax built in Lean
  reaches it. The model already described a repeated key column; the native evidence for it is in
  the frozen corpora, the authored cases `validity-repeated-primary-key` and
  `validity-repeated-unique-key` (finding 15). The kernel examples check the model and the proofs
  only. The usual restriction tests do not change, since decision 5 adds no restriction.
- **The predictions are byte-identical** to the baseline (`nix-build integrity/judge.nix -A
  predictions`, then `diff -r`, as slices 1 to 3 did).
- **The usual suites**: `tests/test_model_package.py` (each new module is in the package globs and
  in the root import `Model.lean`), `just documentation-inventory`, and `just test-full` and
  `just verdict` at the end of each part.

## Key points

- **The atoms are not all row-local.** `Catalog.Valid` and "rows shaped" are facts of the catalog
  and the list of tables; they change with a CREATE and a DROP, and not with a row write. The
  five other atoms read one row of one table with its catalog entry, so they use the generic row
  engine proofs of slices 2 and 3 (`RowEngineFacts`, `TableFacts`, `Database.Every`,
  `Effect.Satisfies`, `RowLocalAtom`) when a fact of a table holds for a table with a sublist of
  the rows and for a table that a write stores. The "stored" form of a written table is
  where `ready` enters; the proof needs an extension of the generic layer, because the condition of
  `StatementKeeps` does not see the clock or the parameters on which `ready` depends (status file,
  "Findings").
- **Rowids distinct needs the key.** For a table with a rowid alias, the alias is the primary
  key, and the row engine checks the constraints and the distinct rowids of the result together
  (`checkedRow`, `Upsert.lean`). A proof may need another atom of the bundle. Where it does, the
  theorem lists it in its docstring (decision 2), and the run invariant is the whole bundle.
- **Trigger programs.** A nested INSERT of a trigger program has no `ready` check for width or
  stored cells. It relies on the resolver: `fullCells` of `Resolution/InsertCells.lean` gives one
  cell for each column of the current catalog and stores each cell. A trigger body is resolved at
  the time of the write, so the width is current. The resolver fact "a resolved INSERT row is wide
  and stored" is a lemma of part 2 (status file, "Findings"). Bounded rowids of the tables that
  triggers write are in `keyReady` (`ForeignKeyWrites.lean`).
- **The CHECK lemma is the big proof.** It says that `resolveOperand` over a single table
  (`Scope.single`) gives an expression that `Resolved.Expr.readsBelow` the width. It is a proof
  by mutual recursion with `resolveArguments`, `resolveCase`, the function calls and the name
  lookup (`Resolution/QueryExprs.lean`, `Scope.lean`). `readsBelow` checks only the column nodes
  and ignores the bodies of subqueries (`ExprAny.lean`); the proof must keep to that definition.
  The same lemma serves the CHECKs of CREATE TABLE and of ADD COLUMN, and the index terms and
  filters.
- **A change of `CatalogTable.supported` changes every `Catalog.Valid` proof**, including
  `Conforms.createTable`, `Conforms.addColumn` (`SchemaExtensionLaws.lean`) and the examples of
  slices 1 to 3. Part 1 repairs them.
- **`supportedKey`** (`Database.lean:64`) refuses a key with a repeated column, which SQLite
  accepts. Decision 5 a) changes it: it allows the repeat, as `CatalogIndex.supported` does. The
  proofs of slice 2 about keys (`KeysUnique*.lean`, `RowEngineKeyState.lean`) and any proof that
  uses the refusal must then hold for repeated keys. If a statement of slice 2 is false for a
  repeated key, stop and report. It is used in `CatalogTable.supported` only.
- **`runScriptFrom` and the profile.** `Database.Admitted` takes a profile and `Catalog.Valid`
  takes its limits. The theorem needs `context.profile.limits = profile.limits`; the surface uses
  `Profile.pinned` (`runContext`, `Run.lean`).
- **Not changed.** ADR 0022, D5 and the check `Run.checked` stay as they are: S4 of ADR 0017
  removes the check (or its use) when the corollary is in place.
- **Mutants must stay buildable**, as in slices 2 and 3: put the theorems in new modules that
  `conformance/mutation_check.py` and `conformance/resolve_mutants.py` do not copy or import. A
  change of `CatalogTable.supported` or of a resolver function is in a file that mutants copy;
  run the mutant tests that the change touches by name, not the whole suite.
- **Size.** Each new file stays below 200 lines. The status file gives the estimate.
- **Documents.** ADR 0012 (amended 2026-10-22) says that no preservation theorem exists yet; its
  dated note (slices 2 and 3 added one) names these theorems too. ADR 0022, D4 gets the record of
  slice 4. The one-line amendment of the record of slice 3 about the pragma forms is made by the
  commit that adds these plan files.

## Amendment of 2026-10-24 (finding 16, owner decision M)

Finding 16 of the status file shows that `keyReady` does not bound the rowid of a table that a nested
write changes and leaves out of `acted`, and that the engine checks no written row of a nested
INSERT or UPDATE for width, stored form or alias. The owner decided option M. This amendment
replaces the text above where it differs:

- **The row engine checks every row that it writes.** `insertRow` and `updateRow` test the written
  row with one Boolean test: the row has one cell for each column, each cell is in stored form, the
  rowid alias cell is the rowid (when the table has an alias), and the rowid is in range. A row that
  fails the test ends the statement as not described (`KeyStop.undescribed`, as for the rowid today),
  so the run is not ready.
- **Outcome 1 holds for every constructor, also with rules.** The theorems of "rowids in range",
  "rows wide", "rows stored" and "rows aliased" need the same hypotheses as before (the atom, the
  listed atoms and `ready`) and no restriction on the rules. The hypothesis
  `Resolved.Statement.WithoutRules` of the first commits of part 2 is deleted with its uses.
- **The key point "Trigger programs" is replaced.** The proofs do not rely on `fullCells` and need no
  resolver lemma about the programs; a nested write is checked where it writes. Bounded rowids of the
  tables that triggers write stay in `keyReady`, and the check of the written row adds to it.
- **The model change must not change a prediction.** No SQL text reaches a written row that fails the
  test, and the model must agree with the native results as before. The predictions are taken before
  the change, `just dev-verdict` for every claimed corpus keeps every count, and `diff -r` of the
  predictions is empty. If a prediction changes, stop and report.
- **Mutants.** The change touches files that mutants copy. Run `tests/mutant_guards_test.py` and the
  mutant tests of the touched targets by name; fix a mutant definition whose target text no longer
  matches in the same commit.
- **The counterexample of finding 16** becomes an example of a statement that is not ready (and ends as
  `unmodeled`), and the counterexamples of "Conditions" stay as they are.
