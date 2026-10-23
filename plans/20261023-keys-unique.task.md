# The theorem of "keys unique" (ADR 0022, slice 2)

Created 2026-10-23. Status: DONE (2026-10-23). The owner decisions are in the status file; decision 1 d) was
replaced on 2026-10-23 after finding 1.
Status file: [status](20261023-keys-unique.status.md).
Specification: [ADR 0022](../docs/adr-0022-database-validity.md), D3 and D4 (slice 2).
Needed by: S4 of the user surface ([ADR 0017](../docs/adr-0017-user-surface.md)): a lookup by a
unique key gives at most one row.

## Scope

The model gets theorems that its statement step (`runStatement`) and its runs keep the atom
"keys unique" (`Database.KeysUnique`, `DatabaseConstraints.lean`), a frame lemma, and a lookup
lemma for S4. Nothing that a statement does changes, so the predictions, the claims and the judge
lock do not change.

Out of scope: the other atoms (slices 3 to 5); the resolver facts that give the conditions of
ADD COLUMN and DROP for a database in general (slice 4, see "Conditions"); the surface and its
check `Run.checked` (`packages/belay/Belay/Sqlite/ProgramRun.lean`), which the theorems of D3
replace before S4 (ADR 0022, D5).

## Outcome

1. **The statement theorem.** For every clock, parameter list, resolved statement and database:
   if the database satisfies `Database.KeysUnique`, and the statement meets its condition (see
   "Conditions"), then the database of the effect of `runStatement` satisfies
   `Database.KeysUnique`. This applies to the `ok` database and to the database that an `error`
   with the reason `constraintFail` carries, which keeps the rows that a FAIL write stored before
   it. These are the effect databases that a run keeps (`SqlState.publish`); for every other
   error, the run keeps the input database. The theorem
   has no condition on the connection: foreign keys on or off, in or out of a transaction. It
   also has no `ready` hypothesis: a statement that the model does not describe gives an effect,
   and the theorem holds for that effect.
2. **The statement forms.** The theorem covers each constructor of `Resolved.Statement`:
   - plain INSERT and UPDATE (`checkedWrite`, `StatementRun.lean`), and DELETE, which stores a
     sublist of the rows;
   - upsert: INSERT OR IGNORE, OR REPLACE, ON CONFLICT DO NOTHING and DO UPDATE
     (`UpsertRun.lean`);
   - the writes through the row engine: foreign keys on, or triggers on the written table
     (`RowEngine.lean`, `ForeignKeyRows.lean`, `RowInsert.lean`, `TriggerRun.lean`), with
     CASCADE, SET NULL and SET DEFAULT actions, trigger programs, `RAISE` and REPLACE;
   - CREATE TABLE, CREATE INDEX (a unique index is checked against the rows), CREATE TRIGGER,
     ADD COLUMN, DROP TABLE, DROP INDEX and DROP TRIGGER;
   - queries, settings, `prepareError`, BEGIN, COMMIT and ROLLBACK, which keep the database.

   ADR 0019 slice 2 (`plans/20261023-pragmas.task.md`, in progress in another workspace) adds
   statement forms that this theorem must cover when they land: a pragma statement writes no
   table row, and `PRAGMA recursive_triggers` changes the paths of the row engine (when it is
   on, a trigger fires again while it runs, and the rows that REPLACE deletes fire the DELETE
   triggers). The theorem covers each of them.
3. **The run theorems.** Both assume that the start state's database, and its snapshot when a
   transaction is open, satisfy `Database.KeysUnique`, and that each CREATE INDEX, ADD COLUMN
   and DROP that the run reaches meets its condition on the database at that point (owner
   decision of 2026-10-23, see "Conditions"). The `runScriptFrom` theorem states the hypothesis
   for the statement as the run resolves it.
   - `runSqlFrom` (and so `runSql`, the run that ADR 0022, D3 names) gives an `Outcome`: each
     database of it (`success`, `failure`, `pending` with its persisted and visible database)
     satisfies the atom.
   - `runScriptFrom` (`ScriptRun.lean`, the run of the surface) gives a `ScriptRun`: the database
     of its connection (`connection.state.database`), and the snapshot of that state when there
     is one, satisfy the atom.

   ROLLBACK and a constraint rollback restore the snapshot, so the snapshot is part of the
   invariant. The `runSqlFrom` theorem keeps the hypothesis: finding 1 (status file) shows that a
   resolved script can reach a CREATE INDEX of an unsupported index and an ADD COLUMN that breaks
   the atom. Slice 4 proves the resolver facts (see "Direction for slice 4") and removes the
   hypothesis from the `runScriptFrom` theorem.
4. **The frame lemma.** A statement keeps `Table.KeysUnique` of the table at a position when the
   effect leaves the table's rows, its catalog entry and the unique indexes on it unchanged.
5. **The lookup lemma.** For a table that satisfies `Table.KeysUnique` for a list of keys, a key
   in that list, and a probe row: at most one row of the table conflicts with the probe on the
   key (`LiteralData.keyEqual`). With the database form, this is the fact that S4 needs.
6. **Plain words.** Each new proposition has a plain-words docstring, and each theorem that other
   proofs use, or each proof longer than about 20 lines, has a proof sketch.
7. **Findings.** A proof that fails for a statement form is a finding (ADR 0022, D3). The status
   file records it with a counterexample, and it goes to the owner. No hypothesis assumes it
   away.

## Conditions

Two statement forms do not keep the atom for every database. The condition of ADD COLUMN is a
fact of `Database.Admitted`, which slice 4 proves the runs keep. The condition of DROP is a fact
of the resolver over a valid catalog.

- **ADD COLUMN** needs the rows of the target to be wide (`Table.RowsWide`), and each key term and
  each filter of a partial unique index on the target to read only columns below the old
  width. Without the first: a table `(a, b)` with
  `UNIQUE(b)` and two rows `[1]` and `[1]` has no conflict (a missing cell never conflicts);
  ADD COLUMN with the default 5 appends the cell at the position of `b` in both rows, and the
  rows then conflict on `b`. Without the second: a table `(a)` with two rows `[1]` and `[1]` and a
  unique index on `a` whose filter reads column 1 has no conflict, because the filter reads a
  missing cell as NULL, which is not true; after ADD COLUMN with the default 5 the filter is true
  for both rows, and they conflict on `a`. The second follows from `Catalog.Valid`
  (`CatalogIndex.supported`, `Resolution/Keys.lean`), and needs a lemma that an expression that
  reads below a width (`Expr.readsBelow`, `Resolution/ExprAny.lean`) has the same value on a row
  with cells appended.
- **DROP** needs closure: no unique index that the drop keeps is on a table that it drops.
  Without it: the catalog `[t0, t1, i]` with the unique index `i` on `t0`, and `DROP [0]`, gives
  `i` on `t1` (`afterDrop`, `Resolution/CatalogDrop.lean`), whose rows can conflict on it. The
  resolver drops the indexes of a dropped table (`tableObjects`), so the condition holds for each
  resolved DROP over a valid catalog; that resolver fact is out of scope.

- **CREATE INDEX** keeps the atom for every database: a unique index is checked against the
  rows. Its condition is that the index is supported over the catalog: the table of the index
  exists and `CatalogIndex.supported` holds for its width, as `Catalog.supported`
  (`Database.lean`) checks it for each index. The run theorems assume it because it gives the
  second condition of a later ADD COLUMN in slice 4.

Finding 1: `runSqlFrom` takes any list of resolved statements, also statements that the resolver
does not give. A resolved CREATE INDEX whose filter reads past the width of its table is ready,
and a later ADD COLUMN with a default then makes two rows conflict. `KeysUniqueExamples.lean`
writes these resolved statements directly and runs them. So the `runSqlFrom` theorem cannot
derive the conditions from its script, and it takes them as a hypothesis.

## Direction for slice 4

Slice 4 removes the hypothesis from the `runScriptFrom` theorem. That theorem then assumes that
the start database, and the snapshot when there is one, satisfy `Database.Admitted` (with
`Catalog.Valid` and `Table.RowsWide`): without wide rows, the counterexample `shortRows` of
"Conditions" breaks the atom at an ADD COLUMN. Slice 4 must prove these resolver facts for the
statements that `runScriptFrom` resolves over such a connection:

- each resolved CREATE INDEX with at least one term is supported over the catalog, so the runs
  keep `Catalog.Valid`. The resolver accepts a CREATE INDEX syntax without terms
  (`resolveCreateIndex`, `Resolution/Definitions.lean`), which `CatalogIndex.supported`
  refuses; SQL text cannot write it, so the fact assumes at least one term in the syntax, or
  slice 4 makes the resolver refuse it;
- the runs keep `Table.RowsWide` (`Database.Admitted`);
- with these two facts, each resolved ADD COLUMN meets `Database.AddColumnCondition`;
- each resolved DROP over a valid catalog meets `Catalog.DropCondition` (the resolver drops the
  indexes of a dropped table, `tableObjects`).

## Parts

The task has two parts (owner decision 2), each with its own `just test-full` and `just verdict`.

- **Part 1:** the frame lemma, the lookup lemma, and the theorem for each form outside the row
  engine (plain writes, upsert, the schema statements, the forms that keep the database).
- **Part 2:** the row engine, the statement theorem over all of `runStatement`, and the run
  theorems.

## Tests

- **The theorems compile without `sorry`.** A test compiles a check file against the model with
  `compile_checks` (`tests/shared_table_shape_test.py`), which refuses `sorryAx`,
  `ofReduceBool` and `_native` in the `#print axioms` output of the statement theorem, the run
  theorems and the lookup lemma.
- **Kernel examples** in a compiled examples module of the model (in the package globs, not in the
  root import, as `ValidityExamples.lean`), checked by `decide +kernel`:
  - the lookup lemma applied to the partial unique index `accounts_live` of the user guide
    ("Invariants");
  - the two counterexamples of "Conditions": the atom holds before and fails after, so each
    condition is necessary;
  - a run theorem applied to a concrete script with an INSERT, an upsert, a write that cascades
    and a ROLLBACK;
  - finding 1: a resolved script that reaches a CREATE INDEX of an unsupported index and then an
    ADD COLUMN, whose outcome breaks the atom, so the hypothesis of the `runSqlFrom` theorem is
    necessary.
- **The predictions are byte-identical** to the baseline (`nix-build integrity/judge.nix -A
  predictions`, then `diff -r`, as slice 1 did).
- **The usual suites**: `tests/test_model_package.py` (each new theorem module is in the package
  globs and in the root import `Model.lean`), the documentation inventory (`just documentation-inventory`), and
  `just test-full` and `just verdict` at the end of each part.

## Key points

- **Mutants must stay buildable.** `conformance/mutation_check.py` copies `Execution`,
  `LiteralData`, `StatementRun`, `StatementStep`, `SqlExecution`, `StatementOutput` and
  `PossibleOutput` into private namespaces and weakens checks (for example `unique_disabled`), and
  `conformance/resolve_mutants.py` builds `VerifierConformance.Case`. Put the theorems in new
  modules that none of these files and none of that closure imports, so that a mutant that
  weakens a check breaks no proof.
- **The error databases.** `SqlState.failed` restores the snapshot for a constraint rollback;
  `SqlState.publish` keeps the reached database only for `constraintFail`. Upsert carries the
  table before the failed row (`step.before`, `upsertSummary`), and the row engine carries the
  database of its stopped state. For `constraintFail`, each of them must satisfy the atom.
- **The keys of a write** are `Database.keys` of its target (`StatementRun.lean`), which is
  `Catalog.uniqueKeys` of the written position. Each check of the row engine must use the keys
  of the table that it writes; a path that checks other keys is a finding.
- **The row engine** recurses with fuel (`runRows`) through `KeyState` (`ForeignKeyPhases.lean`).
  The invariant is the atom of `KeyState.database` for the running and the stopped states.
  `checkedRow` (`Upsert.lean`) checks the whole next table, so each stored table passes
  `LiteralData.constraints`, and `Table.keysUnique_iff` and `uniqueRows_iff`
  (`DatabaseConstraintChecks.lean`) turn that check into the atom.
- **Positions move.** CREATE TABLE, CREATE INDEX and CREATE TRIGGER append one object;
  `Catalog.uniqueKeys` of a kept table then gains only the new unique index. DROP renumbers the
  kept objects and their `index.table`. `Database.table_setRows`, `table_setRows_other`,
  `table_addColumn` and `table_addColumn_other` (`DatabaseLaws.lean`) are the frame facts.
- **The run hypothesis** is a recursive proposition that follows the run: the condition of the
  first statement on the database of the state, and, when the statement continues, the
  hypothesis of the rest on the next state. A halt requires nothing more. For `runScriptFrom`,
  the condition is on the statement that `resolveStatement` gives over the connection; a
  statement that the run ends at requires nothing. The statement theorem needs only the
  conditions of ADD COLUMN and DROP (`Resolved.Statement.KeysCondition`).
- **The run step.** `advanceWith` publishes the effect (`SqlState.publish`), and BEGIN, COMMIT
  and ROLLBACK move the database to and from the snapshot. `SqlState.finish` and
  `SqlState.failed` put the snapshot into `pending` and `failure`, and `Connection.afterError`
  keeps the persisted database of `pending` as the snapshot.
- **The lookup lemma** needs symmetry and transitivity of `keyEqual`. They follow from the
  `Std.TransCmp` instances of `Value.compare` and `Collation.compare` (`Comparison.lean`).
- **Size.** Each new file stays below 200 lines. Part 1 has about 1,280 lines in ten modules
  (with the examples); part 2 so far has about 830 lines in eight modules. The run theorems add
  about 250 lines in two or three modules.
- **Documents.** ADR 0012 (amended 2026-10-22) says that no preservation theorem exists yet; it
  gets a dated note that names this theorem. ADR 0022, D4 gets the record of slice 2.
