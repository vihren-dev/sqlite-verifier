# The theorems of the other Valid atoms (ADR 0022, slice 3)

Created 2026-10-23. Status: DONE (2026-10-23). The owner decided the decisions of the status file on 2026-10-23.
Status file: [status](20261023-valid-atoms-theorems.status.md).
Specification: [ADR 0022](../docs/adr-0022-database-validity.md), D1, D3 and D4 (slice 3).
Needed by: S4 of the user surface ([ADR 0017](../docs/adr-0017-user-surface.md)): a run of the
bundled database over every database.
Follows: [slice 2](20261023-keys-unique.task.md) ("keys unique"), whose structure and owner
decisions this slice uses.

## Scope

The model gets theorems that its statement step (`runStatement`) and its runs keep the three
atoms "not null" (`Database.NotNull`), "checks hold" (`Database.ChecksHold`) and "types fit"
(`Database.TypesFit`, `DatabaseConstraints.lean`), and a frame lemma for each. Nothing that a
statement does changes, so the predictions, the claims and the judge lock do not change.

Out of scope: "keys unique" (slice 2); the Admitted atoms and the resolver facts that give the
conditions of ADD COLUMN for a database in general (slice 4, see "Conditions"); "foreign keys
hold" (slice 5); an atom for the cells of generated columns (ADR 0022, "Not decided here");
the surface check `Run.checked` (`packages/belay/Belay/Sqlite/ProgramRun.lean`).

## Outcome

1. **The statement theorems.** One theorem for each of the three atoms. For every clock,
   parameter list, resolved statement and database: if the database satisfies the atom, and
   the statement meets the condition of that atom (see "Conditions"), then the databases that a
   run keeps from the effect of `runStatement` satisfy the atom. These are the database of `ok`
   and the database of an `error` with the reason `constraintFail`, as for slice 2
   (`Effect.KeysUnique`, `KeysUniqueFrame.lean`). Each theorem assumes only its own atom, not
   the other atoms. It has no condition on the connection (foreign keys on or off, in or out of
   a transaction), no `ready` hypothesis, and no condition on the clock.
2. **The statement forms.** Each theorem covers each constructor of `Resolved.Statement`, as
   slice 2 lists them: plain INSERT, UPDATE and DELETE; upsert; the writes through the row
   engine, with CASCADE, SET NULL and SET DEFAULT actions, trigger programs, `RAISE` and
   REPLACE; CREATE TABLE, CREATE INDEX, CREATE TRIGGER, ADD COLUMN, DROP TABLE, DROP INDEX and
   DROP TRIGGER; and the forms that keep the database. When the pragma forms of ADR 0019
   slice 2 land (in progress in another workspace), the theorems cover them: a pragma writes no
   row, and `PRAGMA recursive_triggers` changes the paths of the row engine.
3. **The run theorems.** For each atom, for `runSqlFrom` (and so `runSql`) and for
   `runScriptFrom` (slice 2, owner decision 3 a)). Each assumes that the database of the start
   state, and its snapshot when a transaction is open, satisfy the atom, and that each ADD
   COLUMN that the run reaches meets the condition of the atom on the database at that point
   (slice 2, owner decision 1, option A). The result is as in slice 2: each database of the
   `Outcome` of `runSqlFrom`, and the database and snapshot of the connection of the
   `ScriptRun` of `runScriptFrom`, satisfy the atom.
4. **Together.** A corollary for each run: when the start satisfies the four constraint atoms of
   `Database.Valid` (these three and `Database.KeysUnique`) and each reached statement meets
   all their conditions, the result satisfies the four. S4 uses this form.
5. **The frame lemmas.** A statement keeps the atom of a table when the effect leaves the
   table's rows and its catalog entry unchanged. A stronger form: each row of the table after
   is a row of the table before, and the columns (for "not null" and "types fit") or the CHECK
   constraints (`CatalogTable.allChecks`, for "checks hold") are the same.
6. **Plain words.** Each new proposition has a plain-words docstring; each theorem that other
   proofs use, and each proof longer than about 20 lines, has a proof sketch.
7. **Findings.** A proof that fails for a statement form is a finding (ADR 0022, D3). The status
   file records it with a counterexample, and it goes to the owner. No hypothesis assumes it
   away.

## Conditions

Only ADD COLUMN needs a condition. DROP keeps the three atoms for every database: a kept table
keeps its catalog entry (`CatalogEntry.afterDrop`) and its rows, and the atoms read nothing
else. CREATE TABLE, CREATE INDEX and CREATE TRIGGER append one object and keep each table.

ADD COLUMN appends the stored default (`readDefaultValue`, then `Value.store`) to each row of
its table (`Database.addColumn`). On a table with rows, the step fails for a NOT NULL column
with a NULL default and for a row that fails a CHECK of the new column (`step`,
`Execution.lean`), but it does not check the strict type of the default. The conditions on
the table at the target:

- **All three atoms: the rows are wide** (`Table.RowsWide`). Without it, the new cell goes to
  the position of an old column. "Not null": `t(a, b NOT NULL)` with the row `[1]`, then ADD
  COLUMN `c` without a default, gives `[1, NULL]`. "Types fit": a `STRICT` table
  `t(a INTEGER, b INTEGER)` with the row `[1]`, then ADD COLUMN `c TEXT DEFAULT 'x'`, gives
  `'x'` in `b`. "Checks hold": `t(a, b CHECK (b > 0))` with the row `[1]` (a missing cell reads
  as NULL, which passes), then ADD COLUMN `c DEFAULT -1`, gives `b = -1`.
- **"Checks hold": each CHECK of the table reads only columns below the old width**
  (`Resolved.Expr.readsBelow`, `Resolution/ExprAny.lean`). Without it: `t(a)` with the row `[1]`
  and a CHECK `column1 > 0` (column 1 is past the width, so it reads NULL and passes); after ADD
  COLUMN `b DEFAULT -1` the CHECK is false. `Catalog.Valid` does not give this fact
  (`CatalogTable.supported` reads no CHECK); the resolver resolves each CHECK over the columns
  of its table, so the fact is a resolver fact.
- **"Types fit": the stored default fits the strict type** (`strictDefaultFits`,
  `Resolution/AddColumn.lean`), or the table has no rows. Without it: a `STRICT` table
  `t(a INTEGER)` with the row `[1]` and a resolved ADD COLUMN `b INTEGER DEFAULT 'x'` gives a
  TEXT cell in an INTEGER column. The resolver refuses such a column (`add-column-strict-type`),
  so this is also a resolver fact.

The `runSqlFrom` theorems keep the hypothesis, because `runSqlFrom` takes resolved statements
that the resolver did not make. For `runScriptFrom`, slice 4 removes it, as for slice 2, but the
CHECK condition is not only a resolver fact: the start database is any database, and the
counterexample above with `column1 > 0` satisfies `Database.Valid`. The resolver of ADD COLUMN
does not look at the old CHECKs. So the hypothesis goes only with a fact of the start database
and its snapshot that no atom states today (status file, decision 3). SQLite does not open such
a database (checked natively with 3.51.0: a table whose CHECK names a missing column gives
`malformed database schema (t) - no such column: zz`).

## Parts

The status file proposes two parts, each with its own `just test-full` and `just verdict`
(owner decision 2):

- **Part 1:** the frame lemmas and the theorems for each form outside the row engine (plain
  writes, upsert, the schema statements with ADD COLUMN and DROP, the forms that keep the
  database). It can start on slice 2 part 1.
- **Part 2:** the row engine, the statement theorems over all of `runStatement`, the run
  theorems and the corollary. It starts on top of slice 2 part 2.

## Tests

- **The theorems compile without `sorry`.** A test compiles a check file against the model with
  `compile_checks` (`tests/shared_table_shape_test.py`), which refuses `sorryAx`,
  `ofReduceBool` and `_native` in the `#print axioms` output of the statement theorems, the run
  theorems and the corollary.
- **Kernel examples** in a compiled examples module of the model (in the package globs, not in
  the root import, as `KeysUniqueExamples.lean`), checked by `decide +kernel`:
  - the five counterexamples of "Conditions": the atom holds before and fails after, so each
    condition is necessary;
  - SET NULL on a NOT NULL child column fails and keeps the database (SQLite 3.51.0:
    `NOT NULL constraint failed: c.x`, and the parent row stays);
  - a run theorem applied to a concrete script with a CHECK, a NOT NULL column, a `STRICT`
    table, an upsert, a write that cascades and a ROLLBACK.
- **The predictions are byte-identical** to the baseline (`nix-build integrity/judge.nix -A
  predictions`, then `diff -r`, as slice 1 did).
- **The usual suites**: `tests/test_model_package.py` (each new theorem module is in the package
  globs and in the root import `Model.lean`), `just documentation-inventory`, and
  `just test-full` and `just verdict` at the end of each part.

## Key points

- **The atoms read rows one at a time.** Each of the three atoms says a fact of each row with
  the table's catalog entry. A table with fewer rows keeps it (DELETE and the CASCADE delete
  store a sublist), and each other table that a write stores passed
  `LiteralData.constraints`, which `Table.constraints_iff` (`DatabaseConstraintChecks.lean`)
  turns into the three atoms. So one argument can serve the three atoms; the theorems stay one
  for each atom (ADR 0022, D3).
- **Reuse of slice 2.** Part 1 follows `KeysUniqueWrites`, `KeysUniqueUpsert`,
  `KeysUniqueCreate` (`Database.table_append_cases`), `KeysUniqueAddColumn` and `KeysUniqueDrop`,
  and reuses `DropPositionLaws` (the kept positions of DROP) and `ExprAppendLaws`
  (`Resolved.Expr.eval_append`: an expression that reads below a width ignores appended cells).
  Part 2 reuses from slice 2 part 2: the laws of `ResultHolds` over the `Except` steps
  (`RowEngineKeyState`), `oldSteps_rows` and `newSteps_rows` (`RowEngineKeySteps`), the
  cases of `checkedUpdate`, `deleteRow`, `updateRow`, `insertRow`, the trigger programs and
  `runRows`, and its run theorems. Owner decision 1 a) is done (2026-10-23): the row-engine
  proofs take the fact of a table as a parameter (`TableFacts`, `RowEngineFacts`), and the run theorems
  take the property of databases as a parameter (`RunHoldsStep`, `RunHolds`, `ScriptRunHolds`), so the
  atoms of slice 2 and slice 3 are instances.
- **ADD COLUMN.** The step checks the new column's CHECK on `row.values ++ [value]`, and
  `Database.addColumn` stores `Value.store column.affinity value`; these are the same cell by
  `readDefaultValue_stored` (`Resolution/ReadDefaultLaws.lean`). A default that reads the clock
  succeeds only on a table without rows.
- **The clock.** `LiteralData.checkHolds` evaluates each CHECK at clock 0 (`.plain 0`), in the
  atom and in every write that checks it, so the atom does not depend on the statement's clock,
  and the theorems need no clock condition. The resolver refuses a CHECK with a time keyword or
  a date and time function (`check-function`), and `random()` is `unmodeled-function`
  everywhere today. A resolved statement given to `runSqlFrom` can hold a CHECK that reads the
  clock; it still evaluates at clock 0 on both sides. A proof that needs the clock is a finding.
- **Not modeled.** `PRAGMA ignore_check_constraints` and `writable_schema` are not modeled, and
  ADR 0019 slice 2 does not add them, so no statement has "no theorem" (ADR 0022, D3). REPLACE
  of a NULL in a NOT NULL column with a default is the restriction `replace-default`; the
  model's REPLACE of a NULL in a NOT NULL column is ABORT (`failedConstraint`,
  `UpsertRun.lean`). The model has no CREATE TABLE AS.
- **Foreign-key actions.** SET NULL and SET DEFAULT write the child rows as an update of the
  row engine (`runAction`, then `updateRow`), whose `checkedUpdate` checks the whole table, so
  a NULL in a NOT NULL child column fails as ABORT and the run keeps the input database
  (`keyRun`).
- **ADR 0024** (connection counters, accepted 2026-10-23, not yet in this line of changes) adds
  three counters to `SqlState` and the counts to the step's result, and makes the five
  functions in a CHECK a restriction. State the run invariants with the fields `database` and
  `snapshot`, so that new fields do not change them.
- **Mutants must stay buildable**, as in slice 2: put the theorems in new modules that
  `conformance/mutation_check.py` and `conformance/resolve_mutants.py` do not copy or import.
- **Size.** Each new file stays below 200 lines. The status file gives the estimate.
- **Documents.** ADR 0012 (amended 2026-10-22) says that no preservation theorem exists yet;
  its dated note (slice 2 adds one) names these theorems too. ADR 0022, D4 gets the record of
  slice 3.
