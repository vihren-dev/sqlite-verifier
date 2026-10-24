# Status: the theorems of the Admitted atoms (ADR 0022, slice 4)

Created 2026-10-23. Status: DONE (2026-10-24). The owner decided on 2026-10-23 (below); decision 3 repeats the
decision of 2026-10-23 for slice 3.
Task: [task file](20261023-admitted-atoms-theorems.task.md).
Specification: [ADR 0022](../docs/adr-0022-database-validity.md), D1, D3 and D4 (slice 4).
Needed by: [ADR 0017](../docs/adr-0017-user-surface.md), S4.
Depends on: [slice 2](20261023-keys-unique.task.md) and
[slice 3](20261023-valid-atoms-theorems.task.md), which are in this line of changes.

## Relevant files

All paths below are in `packages/belay-sqlite-model/Belay/Sqlite/Model/` unless they start with
`packages/` or `tests/`.

- The atoms: `DatabaseFacts.lean` (the Admitted atoms, `Database.Admitted` at line 111,
  `Table.Admitted`), `DatabaseFactChecks.lean` (the checks and their `_iff` lemmas),
  `DatabaseConstraints.lean` (`Database.Valid`), `Database.lean` (`supportedKey` at line 64,
  `CatalogTable.supported`, `CatalogObject.supported`, `Catalog.supported`, `Database.drop`,
  `Database.setRows`, `Database.addColumn`), `Resolution/Keys.lean` (`CatalogIndex.supported`,
  line 80).
- The statement step: `StatementStep.lean` (`runStatement`, `advanceWith`, `runSqlFrom`,
  `supportedSqlFrom` at line 189), `StatementRun.lean` (`StatementRun`, `checkedWrite`),
  `StatementClock.lean` (`Cell.valueAt`, `rowsAt`), `Execution.lean` (`step`), `LiteralData.lean`
  (`insertReady` at line 185, `nextRowid`, `boundedInteger`), `RowUpdate.lean` (`updateReady`),
  `UpsertRun.lean` (`upsertReady`), `Upsert.lean` (`checkedRow`), `ForeignKeyWrites.lean`
  (`keyReady`), `RowInsert.lean` (`insertRow`, line 58), `TriggerRun.lean` (`runStep`,
  `runProgram`).
- Existing lemmas of the Admitted atoms: `DatabaseWriteLaws.lean` (`Conforms.setRows`),
  `SchemaExtensionLaws.lean` (`Table.Admitted.appendColumns`, `Conforms.addColumn`,
  `Conforms.createTable`), `LiteralPreservationLaws.lean` (`LiteralData.rowid_lt_next`).
- The resolver: `Resolution/Resolve.lean` (`resolveStatement`), `Resolution/Definitions.lean`
  (`resolveCreateTable`, `resolveCreateIndex` at line 177), `Resolution/TriggerDefinitions.lean`,
  `Resolution/AddColumn.lean` (`strictDefaultFits` at line 48), `Resolution/Drops.lean`,
  `Resolution/CatalogDrop.lean` (`Catalog.drop`, `tableObjects`, `keptBelow`),
  `Resolution/IndexTerms.lean` (`indexKeys`, line 70), `Resolution/TableChecks.lean`,
  `Resolution/KeyMerge.lean`, `Resolution/QueryExprs.lean` (`resolveOperand`),
  `Resolution/Scope.lean`, `Resolution/ExprAny.lean` (`Resolved.Expr.readsBelow`, line 99),
  `Resolution/InsertCells.lean` (`fullCells`, `omittedCell`, `constantCell`),
  `Resolution/PrepareErrors.lean` (the prepare errors), `Resolution/Messages.lean`.
- The generic layer of slices 2 and 3: `RowEngineFacts.lean`, `RunHolds.lean`,
  `RunHoldsStep.lean`, `ScriptRunHolds.lean`, `RowLocalAtoms.lean`, `RowLocalFrame.lean`,
  `RowLocalStatement.lean`, `RowLocalAddColumn.lean` (`RowsWideAt`, `ChecksReadBelowAt`,
  `StrictDefaultFitsAt`), `KeysUniqueRunStep.lean` (`Resolved.Statement.RunCondition`),
  `KeysUniqueDrop.lean` (`Catalog.DropCondition` at line 19),
  `KeysUniqueAddColumn.lean` (`AddColumnCondition`), `ValidAtomsTogether.lean`
  (`Database.ConstraintAtoms`), `ValidAtomsExamples.lean`.
- The run theorems of slice 4 (part 3): `RunHoldsReady.lean`, `ScriptRunDerived.lean`,
  `ResolveStatementForms.lean`, `ResolveStatementLink.lean`, `ResolveStatementFacts.lean`,
  `ResolveStatementApplied.lean`, `AdmittedStatementKeeps.lean`, `AdmittedSqlRunsCatalog.lean`,
  `AdmittedSqlRunsRows.lean`, `ScriptRunApplied.lean`, `ScriptRunAdmittedCatalog.lean`,
  `ScriptRunAdmittedRows.lean`, `AtomsConditionsOfLink.lean`, `ScriptRunConstraints.lean`,
  `ScriptRunValid.lean`, `AdmittedRunsExamples.lean`, `AdmittedRunsConditionExamples.lean`;
  `tests/admitted_atoms_run_theorems_test.py`.
- The run: `ScriptRun.lean` (`runScriptStepWith` at line 108, `runScriptFrom`).
- The surface: `packages/belay/Belay/Sqlite/ProgramRun.lean` (`Sql.runFrom`, `Run.checked`),
  `packages/belay/Belay/Sqlite/Run.lean` (`runContext`, line 20), `RunLaws.lean`, `ProgramLaws.lean`.
- The text translation: `packages/belay-sqlite-text/Belay/Sqlite/Translation/Schema.lean`
  (`createIndex`, line 26).
- Tests: `tests/valid_atoms_theorems_test.py` (the model for the new test),
  `tests/shared_table_shape_test.py` (`compile_checks`), `tests/test_model_package.py`.

## Size estimate

These are estimates from the size of slices 2 and 3 and from reading the code. No part has been
built yet. Slice 2 part 1 is 1279 Lean lines in 10 modules; slice 3 is estimated at 1000 to 1600
lines. The last row group is the least certain: the proof of `rowsStored` and `rowidsInRange`
through the row engine with `ready` has no model in slices 2 and 3.

| Work | Lines |
| --- | --- |
| `CatalogTable.supported` with the CHECK condition and the alias schema (decision 8), repair of the proofs and examples that use `Catalog.Valid` | 120–240 |
| The resolver fact that CREATE TABLE gives the alias schema | 60–120 |
| The lemma that `resolveOperand` over one table reads below its width (`resolveArguments`, `resolveCase`, calls, names) | 250–400 |
| Decisions 4 and 5: the index with no terms, the repeated key column | 40–100 |
| `Catalog.Valid` after CREATE TABLE, CREATE INDEX, CREATE TRIGGER and ADD COLUMN | 250–400 |
| `Catalog.Valid` after DROP (the closure of the drop), `Catalog.DropCondition` from it | 100–160 |
| The conditions of ADD COLUMN from the resolver (`strictDefaultFits`, `RowsWideAt`, `AddColumnCondition`) | 100–160 |
| **Part 1** | **920–1580** |
| Frame lemmas, `setRows`, append and sublist laws for the seven atoms | 100–160 |
| Schema statements for the seven atoms (CREATE, DROP, ADD COLUMN) | 150–250 |
| Plain INSERT, UPDATE, DELETE and upsert with `ready` | 200–320 |
| Row engine instance with `ready`, trigger programs, and the lemma that resolved INSERT rows are wide and stored | 250–450 |
| Statement theorems over all of `runStatement` | 80–120 |
| **Part 2** | **780–1300** |
| An extension of the generic layer for the condition that sees `ready` | 60–120 |
| Run theorems for `runSqlFrom` and `runScriptFrom` for the seven atoms, and the bundle | 150–250 |
| The corollary for `Database.Valid`, and the surface form | 80–160 |
| Examples (counterexamples, the concrete run) and the test file | 120–200 |
| **Part 3** | **410–730** |

Total: about 2100–3600 lines in 20 to 30 new modules, each below 200 lines. This is larger than slice 3
because the resolver facts are new work. They need the CHECK lemma, which is the largest single
proof. Slice 3 is estimated at 1000 to 1600 lines. The task file proposes three parts (decision 7).

## Owner decisions

Decided on 2026-10-23: the owner accepted the recommendation of decisions 1 to 4 and 6 to 8, and
chose b) for decision 5: a repeated key column is a restriction. Superseded on 2026-10-24: the
owner chose a) (the model keeps a repeated key column, `supportedKey` allows it). Reason: the
frozen corpora corpus-v4 and corpus-v5 contain the cases `validity-repeated-primary-key` and
`validity-repeated-unique-key` in `mustAgree`, and a restriction breaks those claims. Checked natively
(3.51.0, the dev shell's `sqlite3`): `CREATE INDEX i ON t()` is a syntax error;
`CREATE TABLE t(a, b, PRIMARY KEY(a,a))` succeeds, `PRAGMA index_info` of its index gives the
column twice, and a duplicate key fails with `UNIQUE constraint failed: t.a, t.a`.

1. **How the statement theorems of the table atoms handle `ready`.** `runStatement` returns a
   `StatementRun` with `effect`, `ready` and `keyRows`. A write that is not ready is a write that
   the model does not describe (`insertReady`, `updateReady`, `upsertReady`, `keyReady`).
   `runScriptFrom` ends the run when `ready` is false (`ScriptRun.lean:118`), so every
   continued step is ready. The Admitted atoms cannot drop `ready`, unlike the atoms of slices 2
   and 3: an INSERT into a table with the rowid 2^63-1 gives the rowid 2^63 with the effect `ok`,
   which breaks "rowids in range". A resolved INSERT with a `.value` cell that is not in stored
   form breaks "rows stored" (`Cell.valueAt` takes a `.value` as it is). A resolved INSERT row
   with fewer values than columns breaks "rows wide".
   - a) The statement theorems and the `runSqlFrom` theorems assume `ready` (for `runSqlFrom`,
     `supportedSqlFrom`, which says it at each reached statement). The `runScriptFrom` theorems
     assume nothing: the run gives `ready`. The generic layer gets a variant whose condition sees
     the clock and the parameters.
   - b) The theorems assume explicit conditions on the statement (rowids, stored values, width).
     They cannot state the 2^63 case without describing `nextRowid`, which would copy the model.

   Recommendation: a). It uses the check the model already makes, it is the form of
   `supportedSqlFrom`, and `ready` is the model's own statement of "described". Option b) repeats
   `ready` in a second form and must keep both in step.
2. **Which atoms each statement theorem assumes.** ADR 0022, D3 asks for a theorem for each atom.
   Slice 3 proved each constraint atom from its own atom alone. The Admitted atoms interact: a
   write checks the distinct rowids together with the constraints (`checkedRow`), and "rowids
   distinct" for a table with an alias also follows from "keys unique" and "rows aliased".
   - a) One theorem for each atom. A theorem assumes its own atom and the other atoms that its
     docstring lists (the least that the proof needs, for example `catalogSupported` for the
     schema statements). The run invariant is the whole bundle `Database.Admitted`, so the
     corollary for `Database.Valid` is direct.
   - b) Every theorem assumes the whole bundle `Database.Admitted`.

   Recommendation: a). It keeps D3 ("a theorem for each atom") and the claims of S4 can state only
   the atoms they need. The cost is a list of assumptions for each theorem, which part 2 measures
   and records in "Findings". If a list grows to the whole bundle for most atoms, part 2 falls back to
   b) and records it.
3. **The CHECK condition for `runScriptFrom`.** Decided by the owner on 2026-10-23 as decision 3 a)
   of slice 3, and carried over here unchanged: slice 4 adds "each CHECK reads only the columns
   of its table" to `CatalogTable.supported` (so to `Database.Admitted`), proves that the runs keep it
   (the resolver fact, the lemma on `resolveOperand`), and removes the hypothesis `ChecksReadBelowAt`
   from the `runScriptFrom` theorem of "checks hold". The alternative stays recorded:
   - b) The `runScriptFrom` theorem of "checks hold" keeps the hypothesis.

   Recommendation: a), as decided. SQLite does not open a database whose CHECK names a missing
   column (the message of slice 3 for this case is `malformed database schema (t) - no such column:
   zz`), so the fact holds for each database SQLite reaches (ADR 0012, decision 5). A guard in the resolver instead (a
   branch that refuses a CHECK that reads past the width) would be dead code that hides an error
   of the model, and is not recommended.
4. **CREATE INDEX with no terms.** `resolveCreateIndex` accepts a syntax with an empty term list
   (`indexKeys` returns `.ok []`), makes a ready statement, and gives an index that
   `CatalogIndex.supported` refuses (it needs a nonempty key list). From the source (finding 15 says how it is
   confirmed): `supported` is false and the statement is not a restriction. SQL text cannot make it: the
   grammar needs at least one term (`sortlist`, translated at
   `packages/belay-sqlite-text/Belay/Sqlite/Translation/Schema.lean:26`), and SQLite's parser rejects
   `CREATE INDEX i ON t()` as a syntax error near the closing parenthesis (to be confirmed by a
   conformance case or an example of part 1, finding 15). A Lean user can
   build the `Syntax.Statement` directly, so a hypothesis on the syntax cannot be discharged for
   the programs of the surface.
   - a) The resolver refuses a CREATE INDEX with no terms with a prepare error (the error
     SQLite gives is a syntax error), as the other refusals of `resolveCreateIndex` do. The
     theorem has no hypothesis on the syntax.
   - b) The resolver refuses it with a restriction (a new kind in the restriction registry and its
     text).
   - c) The theorem assumes at least one term in the syntax of each CREATE INDEX, and the
     `runScriptFrom` theorem keeps that hypothesis.

   Recommendation: a). It does what SQLite does, it adds one prepare error and no
   restriction, and it removes the hypothesis. Option b) says "the model does not describe it",
   which is untrue, because SQLite describes it as an error. Option c) leaves a hypothesis that no
   caller can check, because it is a fact about the program text.
5. **Repeated key columns.** `PRIMARY KEY(a, a)` and `UNIQUE(a, a)` are accepted by SQLite 3.51.0, which
   keeps both columns in the index (to be confirmed by a conformance case, finding 15). The model resolves `CREATE TABLE t(a, b, PRIMARY KEY(a, a))` to a
   table with the key `[0, 0]`, and `supportedKey` refuses it (`Database.lean:64`: no repeated
   column). The statement is not a restriction. So `Catalog.Valid` is stricter than the databases
   that SQLite reaches (ADR 0012, decision 5), and a CREATE TABLE that the resolver accepts gives
   a catalog that is not `Catalog.Valid`.
   - a) `supportedKey` allows repeated columns, as `CatalogIndex.supported` does
     (`Resolution/Keys.lean:79`). The key facts of slice 2 (`KeysUnique`) must hold for a key with a
     repeated column. The atom `KeysUnique` compares the cells of each key position, so the
     expected change is small; the proof has to confirm it.
   - b) The resolver refuses a repeated key column with a restriction.

   Recommendation: a). It keeps ADR 0012, decision 5 ("the Admitted set is the databases SQLite
   reaches") and removes a refusal that SQLite does not make. Option b) turns a working SQLite
   statement into an unmodeled one without need. `supportedKey` is used in
   `CatalogTable.supported` only, and in one docstring (`KeysUniqueAddColumn.lean:34`), so a)
   is a small change.
6. **The surface.** The task requires the corollary for `runScriptFrom` (the model). The
   program run `Sql.runFrom` is a free-monad run with `runScriptStep` at each step, and
   `Run.checked` decides `Database.Valid Profile.pinned` at the end.
   - a) Slice 4 proves the corollary for the model and also a short induction over `Sql α` for
     `Sql.runFrom` (in the surface package): the database after the run is `Valid` when the start
     database is. S4 then can drop the check of `Run.checked` or turn it into a lemma.
   - b) Slice 4 proves the model corollary only. S4 proves the induction when it needs it.

   Recommendation: a). The induction is small (an estimated 60–120 lines) and the model
   facts are in hand; S4 needs exactly this theorem (ADR 0022, D5). The removal of the check
   `Run.checked` stays in S4, because it changes the surface.
7. **The split.**
   - a) One task file in three parts (task file, "Parts"), each with `just test-full` and `just
     verdict`: resolver facts, statement theorems, run theorems with the corollary.
   - b) Two parts, as slices 2 and 3 (the resolver facts and the statement theorems in part 1).

   Recommendation: a). The estimate of part 1 plus part 2 is about 1700–2900 lines, twice a part of
   slice 3. Part 1 changes `CatalogTable.supported`, which every later proof uses, so it should land
   and be checked alone.
8. **The alias schema** (finding 14). A table that a Lean user builds can have a rowid alias that
   no SQLite table has: a generated column, a column that is not the only primary key column, or a
   `WITHOUT ROWID` table. Of these, the generated alias breaks "rows aliased" with a ready write.
   - a) `CatalogTable.supported` states the alias schema: if the table has an alias at a position,
     the position is below the width, the column is not generated, it has INTEGER affinity, the
     primary key is exactly that position, and the table is not `WITHOUT ROWID`. The resolver fact
     of part 1 shows that CREATE TABLE gives it. The check `aliasReady` stays.
   - b) `aliasReady` also refuses a generated alias column. `Catalog.Valid` states nothing more.
     `ready` then stops the run at a write to such a table, as unmodeled.
   - c) Both.

   Recommendation: a). It follows decision 3 (a fact of every database SQLite reaches goes into
   `Catalog.Valid`, ADR 0012 decision 5) and it also covers the other forms. Option b) fixes only the
   generated column and leaves the other forms to `ready`. The cost of a) is one more conjunct in
   `CatalogTable.supported`; the estimate is in the first row of part 1. Part 1 checks each form
   against the resolver before a proof relies on a).

## Findings

Observed on 2026-10-23, before the slice began, by reading the source and by hand-run probes of
the model and of SQLite 3.51.0. A local result is not evidence (`CLAUDE.md`), so each observation is
a claim to confirm: part 1 makes each SQLite claim a case of the conformance evidence before a
proof relies on it (finding 15).

1. **CREATE INDEX with no terms is resolved and ready, and not supported** (decision 4). The resolver
   does not check `CatalogIndex.supported` and the statement is not a restriction. The grammar is
   in decision 4.
2. **`PRIMARY KEY(a, a)` and `UNIQUE(a, a)` are resolved, not restricted, and not supported**
   (decision 5, now a): `supportedKey` will allow them). The resolver emits the key `[0, 0]`. `PRIMARY KEY()` and
   `UNIQUE()` with an empty list cannot come from SQL text; they resolve to a supported table
   because the empty key merges with an empty primary key. `CREATE TABLE t()` gives the prepare
   error `onlyGeneratedColumns`.
3. **`Catalog.DropCondition` is too weak for `Catalog.Valid` after a DROP.** It covers only unique
   indexes (`KeysUniqueDrop.lean:19`). `Catalog.Valid` after a DROP needs more: every kept index
   keeps its table, and every kept trigger keeps its table (`CatalogObject.supported`, the
   `catalog.tableAt index.table` and `findTable trigger.table` cases). The resolver's
   `tableObjects` (`Resolution/CatalogDrop.lean`) removes the table, the indexes of the table
   (`found.table == position`) and the triggers of the table (`sameName`), so the closure holds;
   a lemma must state it. `Catalog.DropCondition` follows from the closure and from
   `Catalog.Valid` (`index.table` is a table position). DROP INDEX and DROP TRIGGER remove one
   object that nothing else names.
4. **`ready` is needed for three Admitted atoms.** "Rowids in range": `nextRowid` is the maximum plus
   one and can be 2^63; the model says "SQLite's random-search branch at the maximum rowid requires
   separate admission" (`LiteralData.lean:119`), and `insertRow` throws `undescribed` when
   `!boundedInteger proposed.rowid` (`RowInsert.lean:58`). "Rows stored": a `.value` cell is not stored
   by `rowsAt`; `insertReady` checks `storedForm`. "Rows wide": `insertReady` checks
   `values.length == width`. Decision 1. The expected counterexample for the examples: a table with a row of
   rowid 2^63-1 and an INSERT, with `effect = ok` and `ready = false`.
5. **`ready` includes the tables that triggers write.** `keyReady` (`ForeignKeyWrites.lean:28`)
   bounds the rowids of the target and of every acted table, and `acted` includes the tables that
   trigger programs write (`KeyState.afterStep`, `TriggerRun.lean`). It also checks `tableReady`
   for each acted table. A CASCADE can write an unbounded `Value.integer` (the type is `Int`) to an
   alias cell; the proof of "rows aliased" must show that `keyReady` excludes it. A finding if it does not.
6. **Nested INSERT rows of trigger programs have no `ready` check.** `runStep` (`TriggerRun.lean`)
   builds the rows with `rowsWith`, and `RowWork.insert` has no width or stored check. They rely on the
   resolver: the body is resolved at the time of the write against the current catalog, and
   `fullCells` (`Resolution/InsertCells.lean`) gives one cell for each column and stores the written
   cells (`Resolved.Cell.stored`) and the defaults (`omittedCell`). `constantCell` itself does not
   store. A lemma for "resolved INSERT rows are wide and stored" is required; if it fails, it is a
   finding.
7. **The generic layer's `condition` does not see the clock or the parameters.** `StatementKeeps`
   takes a condition of the statement and the database. `ready` depends on the run, so the
   generic layer needs a variant (the size estimate has a row for it).
8. **`runScriptFrom` gets `ready` for free.** `runScriptStepWith` ends the run with `unmodeledHere`
   when `!run.ready` (`ScriptRun.lean:118`). For `runSqlFrom`, `supportedSqlFrom` is the predicate.
9. **Other statements seemed fine** (supported, CHECKs below the width): a CHECK on a
   column and a table CHECK, ADD COLUMN with a CHECK, a duplicate column in a different case (a prepare
   error), an expression unique index with a filter, a trigger, DROP TABLE with a trigger, and a
   `WITHOUT ROWID` table with a primary key.
10. **ADD COLUMN.** The resolver checks the column limit, duplicate names, the name `rowid`
    (a restriction), `strictDefaultFits` (the restriction `add-column-strict-type`), and the new
    CHECKs over the new width. `AddColumnCondition` follows from `Catalog.Valid`, `supportedKey`
    (positions below the width) and `CatalogIndex.supported`. `RowsWideAt` follows from
    `Admitted.rowsWide`. `StrictDefaultFitsAt` needs a lemma that the CHECKs and keys of the
    definition do not change `strictDefaultFits` or `readDefaultValue`.
11. **The CHECK lemma.** `readsBelow` checks `.column` nodes only (`isColumnFrom`) and ignores
    subquery bodies, so the lemma is about the expressions that `resolveOperand` makes over
    `Scope.single`. The CREATE TABLE path is `resolveTableChecks` and `resolveCheck`; the ADD COLUMN
    path is `columnChecks` over `table.columns ++ [column]`. The estimate is 250–400 lines.
12. **The record of slice 3 in ADR 0022, D4 is out of date.** It says "The pragma forms of
    ADR 0019, slice 2 are not in this line of changes". They are in the base now
    (`Resolved.Statement.setting` has two fields; `RowLocalStatement` has the case). The commit that
    adds these plan files amends that sentence with a dated note (2026-10-23). The slice-4
    implementer need not do it.
13. **The class of slice 2's finding.** Slice 2 found
    that a resolved CREATE INDEX of an index that `CatalogIndex.supported` refuses breaks "keys unique"
    at a later ADD COLUMN. Findings 1 and 2 are the two known inputs of that class. The resolver fact
    of part 1 is stated for every CREATE INDEX, so it finds any other input; one that fails is a
    finding.

14. **The alias schema is not in `Catalog.Valid`** (review of the task file, R19). `rowidAlias` is
    a field of `CatalogTable`, and `CatalogTable.supported` states nothing about it ("A rowid alias is
    admitted", `Database.lean`). `aliasReady` (`LiteralData.lean:177`) checks only that the alias column
    has INTEGER affinity. `newCells` (`LiteralData.lean:146`) sets the alias cell to the rowid and then
    computes the generated columns (`generatedCells`). So a table that a Lean user builds with a
    generated INTEGER column as its alias passes `Catalog.Valid`, `aliasReady` and `ready`, and an
    INSERT into it (an empty table, the rowid 1) stores an alias cell that is not the rowid: it breaks
    "rows aliased" (expected counterexample for the examples). The resolver refuses a generated column
    in the primary key (`generatedInPrimaryKey`, `Resolution/Definitions.lean:40`), so no statement
    makes such a table. It is the same class as findings 1 and 2: the catalog atom is looser than the
    databases SQLite reaches. Decision 8.
15. **Confirmation of the observations.** Findings 1, 2 and 9 and the claims of decisions 3 to 5
    about SQLite are hand-run observations. The task file requires an authored case of the
    conformance evidence (native SQLite against the model) for each SQLite claim before a proof relies
    on it; a kernel example checks only the model. Amended 2026-10-23, after the owner decisions: no
    proof of the slice relies on these claims. Decision 4 refuses a syntax that SQL text cannot
    give, and decision 5 b) refused a repeated key column, so neither described SQLite behavior;
    the facts of decisions 3 and 8 are facts of the model's resolver. So the task file required no
    new conformance case. Amended 2026-10-24: decision 5 is a) and the repeated key column stays
    modeled; its native evidence is the two authored cases of the frozen corpora v4 and v5, so the
    task file still requires no new case.
16. **Part 2: `keyReady` does not bound the table of a nested write that stops with FAIL**
    (found 2026-10-24 while the proof of "rows in range" through the row engine was planned; the
    kernel example is `AdmittedAtomsNestedExamples`: the run is ready, the effect is `constraintFail`,
    and the database that it keeps has the rowid 2^70). `keyReady` bounds the rowids of the target and of
    `state.acted`. The engine adds a table to `acted` only after its nested write returns
    (`KeyState.afterStep` in `runStep`, and `acted <$>` in `runAction`). Take an AFTER INSERT program
    whose step is an UPDATE of a table `u` with an alias, and a program on the UPDATE of `u` whose step is
    `RAISE(FAIL)`. The nested UPDATE writes its row (`updateRow` does not check the rowid of the new
    row, unlike `insertRow`, which throws `undescribed` when `!boundedInteger proposed.rowid`), the
    program of `u` stops with `.stopped .fail`, and `u` is not in `acted`. `keyRun` then gives
    `constraintFail` with the database of that state, and `ready` is true when the target is bounded and
    the programs are otherwise fine. A resolved statement whose UPDATE step assigns the integer
    2^70 (`Resolved.Expr` can hold it, although SQL text gives a real) gives a database with a rowid
    outside the range. So "rows in range" is false for a resolved statement with rules, with the
    hypotheses of the task file. SQL text may not reach it (an integer literal beyond 2^63 is a real,
    and arithmetic overflow gives a real in SQLite), but the model does not prove that.
    The same class: the model checks the written row of an INSERT row (`boundedInteger`), but not
    the new row of `updateRow`. Possible repairs, all changes of the model that the owner decides:
    (M-lite) `updateRow` throws `undescribed` when the rowid of the new row is not bounded, as
    `insertRow` does; (M) the engine checks the written row of `insertRow` and `updateRow`
    with one Boolean test (wide, stored, aliased, bounded), so the hypotheses on the programs and the
    resolver lemma of finding 6 are not needed; (R) the spec path: the theorems assume that the
    programs of the rules are described (`fullCells`), and "rows in range" stays open until M-lite.
    **Decided on 2026-10-24: M** (owner, through the coordinator). The row engine checks each row
    that `insertRow` and `updateRow` write with one Boolean test (wide, stored, aliased, rowid in
    range). A row that fails it ends the statement as not described (`undescribed`, as `insertRow` does
    today for the rowid). So the four atoms hold for every constructor, also with rules, and
    `Resolved.Statement.WithoutRules` and its uses are deleted (replaced code). The resolver lemma
    about described programs is not needed. The change touches files that mutants copy
    (`RowInsert.lean`, `TriggerRun.lean` and others): the mutant tests of the touched targets run by
    name, and `tests/mutant_guards_test.py`. No SQL text reaches such a row, so no prediction
    changes: the baseline is taken before the model change, and `just dev-verdict` for all claimed
    corpora must keep every count.

## Progress log

- 2026-10-23: the task file and this status file, and the dated amendment in ADR 0022, D4. No code
  yet.
- 2026-10-23: review round 1 of the task file: one R19 must (the alias schema is not in
  `Catalog.Valid`: finding 14, decision 8) and one R19 should (local probe results cited as
  evidence: finding 15), fixed. Round 2: one R19 must (a kernel example cannot confirm SQLite
  behavior; the task now requires conformance cases for decisions 4 and 5), fixed. Round 3: no
  findings.
- 2026-10-23: the owner decisions: the recommendations of decisions 1 to 4 and 6 to 8, and b) for
  decision 5. The task file follows: a repeated key column is a restriction, and the slice needs
  no new conformance case.
- 2026-10-23: part 1, commit "the CHECK lemma": five new modules in `Belay/Sqlite/Model/`
  (`ResolveNamesBelow`, `ResolveCallsBelow`, `ResolveReadsBelow`, `ResolveTermsBelow`,
  `ResolveIndexBelow`). `resolveOperand_below` (with `resolveArguments_below` and
  `resolveCase_below`) says that an operand resolved over a scope whose sources end below a width
  reads only columns below the width, for any subquery shapes and any `misuse`. Corollaries:
  `resolveCheck_below`, `columnChecks_below`, `resolveTableChecks_below` (needs that the columns
  beyond the definitions have no CHECK), `indexKeys_below` and `indexFilter_below`. No behavior
  change; no prediction can change. Tests: `tests/test_model_package.py`.
- 2026-10-23: review round 1 of the CHECK lemma commit: five R3 and R5 musts (proof sketches
  for the helper lemmas, named constructor splits), fixed in a `refactor:` commit. Tests:
  `tests/test_model_package.py`.
- 2026-10-23: review of the `refactor:` commit: no findings. Then a stop: the restriction of a
  repeated key column (decision 5 b) made `validity-repeated-primary-key` and
  `validity-repeated-unique-key` of corpus-v4 and corpus-v5 leave AGREE, and the judge claims
  require AGREE for them.
- 2026-10-24: the owner changed decision 5 to a): a repeated key column is modeled. The
  restriction `repeatedKeyColumn` is removed again, with its registry entry, documentation row,
  example and the guard of `WithoutRowidExamples`.
- 2026-10-24: the prepare error `ExprError.emptyKeyList` stays. Probes with the native
  `sqlite3` 3.51.0, one statement each: `CREATE INDEX i ON t();`, `CREATE TABLE t(a, PRIMARY KEY());`
  and `CREATE TABLE t(a, UNIQUE());` each give `near ")": syntax error`; `PRIMARY KEY(a, a)` and
  `UNIQUE(a, a)` are accepted. SQL text cannot give an empty list to the model (the parser refuses
  it), so the check serves syntax built in Lean, where an empty `UNIQUE` list gave
  `uniqueKeys = [[]]` on alias tables. Tests: three `#guard` lines in `Resolution/IndexExamples.lean`
  and `tests/test_model_package.py`.
- 2026-10-24: amendment of the task file and this file: decision 5 is a) (reason above).
  The next commits change `supportedKey` and prove the facts of slice 2 for repeated keys.
- 2026-10-24: part 1, commit "CatalogTable.supported": `supportedKey` allows a repeated column
  (decision 5 a)); `CatalogTable.supported` also requires `CatalogTable.aliasSupported` (decision 8)
  and `CatalogTable.checksReadBelow` (decision 3). `CatalogTable.supported_mono` is repaired; every
  other `Catalog.Valid` proof and example of the model, the conformance runner and the surface still
  builds, so no slice 2 or slice 3 proof used the refusal of a repeated key. Tests:
  `tests/test_model_package.py`.
- 2026-10-24: review round of the commit "CatalogTable.supported": four musts (R9 `aliasSupported`
  accepted an alias past the columns of an empty table; R11 no examples; R2 an unchecked reference;
  R7 no statement that the new conditions are rules of the model's catalog). Fixed in the same
  commit: `Option.any`, the new examples module `AdmittedAtomsExamples.lean` (part 1: tables that
  meet and break each new condition, checked by the kernel), docstrings. Tests: `tests/test_model_package.py`.
- 2026-10-24: part 1, commit "the laws of Catalog.Valid": five new modules, no resolver proof yet.
  `CatalogValidLaws.lean`: `Catalog.supported_iff` (unique names and every object supported), the
  objects of a valid catalog, and `Catalog.Valid.append` (CREATE TABLE, INDEX, TRIGGER).
  `CatalogTableLaws.lean`: `CatalogTable.supported_iff`, the check as seven facts
  (`CatalogTable.SupportedFacts`). `CatalogValidAddColumn.lean` and `CatalogValidSet.lean`:
  `CatalogTable.supported_addColumn`, `CatalogIndex.supported_mono`, `Catalog.Valid.addColumn`.
  `CatalogValidDrop.lean`: `Catalog.DropClosed` (every kept index and trigger keeps its table; it gives
  `Catalog.DropCondition`) and `Catalog.Valid.drop`. Examples in `AdmittedAtomsExamples.lean`,
  including a drop of a table alone, which breaks the closure. Tests: `tests/test_model_package.py`.
- 2026-10-24: review round of the commit "the laws of Catalog.Valid": two musts (R2, the plain words of
  `Catalog.DropClosed` and `Catalog.findTable_isSome_drop` said more than the formulas). Fixed in
  a `refactor:` commit. Tests: `tests/test_model_package.py`.
- 2026-10-24: part 1, commit "CREATE TABLE gives a valid catalog": `resolveCreateTable_valid` (execution
  mode, valid catalog in, valid catalog out). The invariant of the table that CREATE TABLE builds is
  `CatalogTable.Shaped` (keys inside the columns, unique folded names, rowid alias is the whole key and
  an INTEGER column), `CatalogTable.Draft` (not WITHOUT ROWID, strict ANY columns are declared ANY) and
  `CatalogTable.Building` (the last column has the reported type of the definition). Nine new modules,
  each below 200 lines: `ResolveTableShaped`, `ResolveKeyCases`, `ResolveDraft`,
  `ResolveConstraintShaped` (`applyConstraint_step`), `ResolveDefinitionsShaped`
  (`addDefinitions_draft`), `ResolveTableConstraintsShaped` (`addTableConstraints_draft`),
  `ResolveFinishShaped` (the CHECK and generated-column stages keep layouts), `ResolveCreateTableValid`
  (`CatalogTable.supported_of_finished`) and `ResolveCreateTableCatalog` (`resolveCreateTable_valid`).
  Examples in the new module `AdmittedAtomsResolverExamples.lean`: `PRIMARY KEY(a, a)`, `UNIQUE(b, b)` and
  a CHECK that names a column give a valid catalog, and each invariant has a table that has it and one
  that has not. A statistics table of a catalog description is out of scope: the theorem needs
  `context.mode = .execution`. Tests: `tests/test_model_package.py`.
- 2026-10-24: review round of the commit "CREATE TABLE gives a valid catalog": seven musts (R2 six
  docstrings said more or less than their formulas; R3 missing proof sketches). Fixed in a `refactor:`
  commit. Tests: `tests/test_model_package.py`.
- 2026-10-24: second review round of the CREATE TABLE commit: one must (R3 sketches of the example
  theorems) and one should (R9 a long sentence). Fixed in a `refactor:` commit.
- 2026-10-24: the resolver facts of CREATE INDEX, CREATE TRIGGER, ADD COLUMN and DROP, and the
  statement-level theorem. New modules: `ResolveCreateIndexCatalog` (`resolveCreateIndex_valid`; the keys
  and the filter read below the width of the table, and a key list is not empty),
  `ResolveCreateTriggerCatalog` (`resolveCreateTrigger_valid`; a schema table name is reserved, so the
  trigger always has a table of the catalog), `ResolveDropCatalog` (`Catalog.DropClosed.table` and
  `Catalog.DropClosed.single`), `ResolveDropValid` (`resolveDropTable_valid`, `resolveDropIndex_valid`,
  `resolveDropTrigger_valid`, and the `_closed` forms, from which `Catalog.DropCondition` follows),
  `ResolveAddColumnCatalog` (`resolveAddColumn_valid`, `resolveAddColumn_strictDefaultFits`),
  `AddColumnFromValid` (`Database.addColumnCondition_of_admitted`, `Database.checksReadBelowAt_of_valid`,
  `Database.rowsWideAt_of_admitted`, `Database.strictDefaultFitsAt_of_fits`) and `ResolveStatementValid`
  (`ResolveState.Valid`, `resolveStatement_valid` with the saved catalog of ROLLBACK, `resolve_valid`).
  The docstring of `KeysUniqueAddColumn` now names the proof of its condition. Examples: the new module
  `AdmittedAtomsSchemaExamples` (a script that creates a table, an index, a trigger and a column and
  drops them; prepare errors that leave the catalog as it was) and a repeated key in
  `KeysUniqueExamples`. New test: `tests/admitted_atoms_resolver_facts_test.py`. Tests:
  `tests/test_model_package.py`, `tests/valid_atoms_theorems_test.py`,
  `tests/admitted_atoms_resolver_facts_test.py`.
- 2026-10-24: review round of the commit "CREATE INDEX, CREATE TRIGGER, ADD COLUMN and DROP give a valid
  catalog": one must (R2 the docstring of `Database.strictDefaultFitsAt_of_fits` lacked the vacuous cases;
  the sibling docstrings got the same repair) and one should (R5 a catch-all in an example, replaced by
  a decided equation of the statement). Fixed in a `refactor:` commit. Tests: `tests/test_model_package.py`.
- 2026-10-24: a record of part 1 in ADR 0022, D4: `Catalog.Valid` states the CHECK condition, the alias
  schema and the repeated key; the resolver facts; the CHECK condition of slice 3 is no longer a gap.
  Tests: `just documentation-inventory`.
- 2026-10-24: part 1 is complete. Local checks (not evidence): `just dev-verdict` on corpus-v4 (673
  AGREE, 591 MODEL_UNSUPPORTED), corpus-v5 (2946 AGREE, 1430 MODEL_UNSUPPORTED), corpus-v50 (17 AGREE)
  and corpus-v51 (21 AGREE); the predictions of the 53 claimed corpora are byte-identical to the baseline
  after the rebase (`diff -r`). The review of the ADR record had no findings. Open for part 2: the
  statement theorems of the seven atoms (they use `resolveStatement_valid`, the `_closed` forms of DROP,
  `Database.addColumnCondition_of_admitted` and `resolveAddColumn_strictDefaultFits`).
- 2026-10-24: the Nix checks of part 1 passed at wtppxrwo (reported by the coordinator): `just test-full`
  and `just verdict` pass; corpus-v4 AGREE 673, corpus-v5 AGREE 2946, corpus-v50 AGREE 17, corpus-v51
  AGREE 21, corpus-v52 AGREE 33.
- 2026-10-24: part 2 starts. The fresh baseline of the predictions is `build/predictions-s4p2-base` (53
  files, before any edit of part 2). Finding 16 is new.
- 2026-10-24: part 2, commit "frame lemmas and cell laws of the table atoms". New modules
  `AdmittedAtomFrames` (the frame lemmas of the five table atoms, `TableAtom`, `Database.EachTable.appendEmpty`)
  and `AdmittedCellLaws` (what `generatedCells` and `newCells` keep: width, stored form and the alias
  cell), and the examples module `AdmittedAtomsStatementExamples`. Tests: `tests/test_model_package.py`.
- 2026-10-24: part 2, commit "ADD COLUMN laws and CREATE statements of the table atoms". New modules
  `AdmittedAddColumnLaws` (one `appendColumns` law for each table atom; `Table.Admitted.appendColumns` is
  now the tuple of them), `AdmittedSchemaStatements` (`runStatement_create_tableAtom` for CREATE TABLE,
  CREATE INDEX and CREATE TRIGGER, for every `TableAtom`) and `DatabaseShapedLaws` (what `setRows`,
  appending an object, `Database.drop` and `Database.addColumn` keep of `Database.RowsShaped`;
  `Conforms.createTable` and `Conforms.addColumn` use them). `Catalog.drop_eq_keptAfterDrop` and
  `Database.drop_rows` moved to `DropPositionLaws`. The review of the first commit of part 2 had one
  should (R9: the module docstring of `AdmittedCellLaws` said that non-generated cells stay, but
  `newCells` replaces the alias cell), fixed. Tests: `tests/test_model_package.py`,
  `tests/valid_atoms_theorems_test.py`, `tests/admitted_atoms_resolver_facts_test.py`.
- 2026-10-24: part 2, commit "Plain writes and upserts of the table atoms". New modules for the rows of a
  write: `AdmittedInsertRows`, `AdmittedUpdateRows`, `AdmittedUpdatedTable` (what INSERT and UPDATE keep of
  "rows wide", "rows stored" and "rows aliased"), `AdmittedUpsertRows` (`UpsertOrigin`: where a row of an
  upsert comes from), `AdmittedUpsertOrigins`, `AdmittedUpsertSummary` (`upsertSummary_atom`, an induction
  over the reached rows with a queue test), `AdmittedPlainWrites` (`runStatement_insert_atom`,
  `runStatement_update_atom`, `runStatement_delete_tableAtom`), `AdmittedWriteReady` (what a ready plain
  write gives), and the statement theorems `AdmittedInsertAtoms`, `AdmittedUpdateAtoms`,
  `AdmittedUpsertStatement`, `AdmittedUpsertAtoms` (distinct, in range, wide, stored and aliased, for
  INSERT, UPDATE and upsert without rules). Examples: `AdmittedAtomsUpsertExamples`. Tests:
  `tests/test_model_package.py`, `tests/valid_atoms_theorems_test.py`,
  `tests/admitted_atoms_resolver_facts_test.py`.
- 2026-10-24: part 2, the review of "Plain writes and upserts of the table atoms" had two musts (R2: the
  docstrings of `runStatement_update_ready` and `assign_aliased` said more than the formulas), fixed in a
  refactor commit with no further findings. Commit "The row engine keeps a property of databases": the
  invariant of the row engine is now a property of databases with the laws of `WriteLaws` (a sublist of
  the rows at a position keeps it, and the write of a table that passed `constraints` and
  `rowidsDistinct` keeps it) in place of a fact of each table. `TableFacts.laws` gives the laws for
  "every table has the fact", so `keysUniqueFacts` and `RowLocalAtom.facts` are used with `.laws`.
  `TableFacts.constraints` now also reads `rowidsDistinct`; `checkedRow_passed` moved to
  `RowEngineFacts`. New module `AdmittedEngineLaws` has the laws of "rowids distinct", "rows shaped"
  and "catalog supported"; examples `AdmittedAtomsEngineExamples`. Tests: `tests/test_model_package.py`,
  `tests/valid_atoms_theorems_test.py`, `tests/admitted_atoms_resolver_facts_test.py`.
- 2026-10-24: part 2, the review of "The row engine keeps a property of databases" had one must (R2: the
  docstrings of the fields of `WriteLaws`), fixed in a refactor commit with no further findings. Commit
  "Statement theorems of the Admitted atoms": `runStatement_rowidsDistinct` (`AdmittedDistinctStatement`),
  `runStatement_rowsShaped` (`AdmittedShapedStatement`) and `runStatement_catalogSupported`
  (`AdmittedCatalogStatement`) cover every constructor of `Resolved.Statement`, with rules, through the
  laws of the row engine; the first two need no `ready`, the third needs the catalog after the statement
  (`applyCatalog`) to be valid. `AdmittedRowsOnly` (`Database.RowsOnlyAt`) says that a plain write only
  replaces the rows of its target. `runStatement_rowidsInRange`, `runStatement_rowsWide`,
  `runStatement_rowsStored` (lists `Database.RowsWide`) and `runStatement_rowsAliased` (lists a valid
  catalog) are in `AdmittedRangeWideStatements`, `AdmittedStoredAliasedStatements` over the skeleton
  `runStatement_tableAtom` (`AdmittedTableAtomStatement`). They take `Resolved.Statement.WithoutRules`
  as a hypothesis: the statements with foreign key rules or trigger programs are not covered (finding
  16). Examples: `AdmittedAtomsTheoremExamples`. Tests: `tests/test_model_package.py`,
  `tests/valid_atoms_theorems_test.py`, `tests/admitted_atoms_resolver_facts_test.py`.
- 2026-10-24: part 2, the review of "Statement theorems of the Admitted atoms" had one must (R2: the
  docstrings of the statement theorems referred to `StatementRun.ready` with `{lit}`), fixed in a refactor
  commit with no findings. Commit "Counterexamples of the statement theorems": `AdmittedAtomsCounterExamples`
  (an INSERT that breaks "rowids in range" with the rowid 2^63 and a run that is not ready, "rows stored"
  with a text cell for an INTEGER column and with a TEXT rowid alias, "rows wide" with a row of no
  cell, and "rows aliased" with a generated rowid alias, whose catalog `Catalog.Valid` refuses) and
  `AdmittedAtomsNestedExamples` (finding 16 as a kernel example). Tests:
  `tests/test_model_package.py`, `tests/valid_atoms_theorems_test.py`,
  `tests/admitted_atoms_resolver_facts_test.py`, and the new `tests/admitted_atoms_statement_theorems_test.py`.
- 2026-10-24: part 2, the review of "Counterexamples of the statement theorems" had no findings. Part 2 is
  done except for the row engine part of four atoms (finding 16, waiting for the owner's choice of M-lite,
  M or R). Local `just dev-verdict` for corpus-v4, v5, v50, v51 and v52 gives AGREE 673, 2946, 17, 21 and 33,
  as in part 1; the predictions of the 53 given files are identical to those before part 2. Open for
  part 3: the resolver link of a resolved `.createIndex` and `.addColumn`, the resolve state that matches
  the snapshot of the connection, and, if design R is chosen, the lemma that the resolver makes only
  described programs.
- 2026-10-24: the owner decided finding 16: option M (see finding 16). This commit records the decision
  and amends the task file ("Amendment of 2026-10-24"). The model change, the proofs for every
  constructor and the updated examples follow in later commits.
- 2026-10-24: part 2, decision M implemented. `LiteralData.rowAdmitted` (`LiteralAdmittedRow`, with
  `rowAdmitted_iff`) tests a row (rowid in range, one cell for each column, cells stored, alias cell is
  the rowid). `insertRow` tests the row before it writes it, and `checkedUpdate` tests the new row of an
  UPDATE; a row that fails ends the statement as `undescribed`. `WriteLaws.write` gained the hypothesis
  that each written row is a row of the old table or admitted (`insertWrite_holds`, `updateWrite_holds`
  and `KeyState.holds_write` carry it). `AdmittedRowLaws` gives `rowAtomLaws`, `rowidsInRangeLaws`,
  `rowsWideLaws`, `rowsStoredLaws` and `rowsAliasedLaws`. `Resolved.Statement.WithoutRules` and its uses
  are deleted: `runStatement_tableAtom` takes the laws and covers the writes with rules through
  `rowsKeys_satisfies` and `dropKeys_holds`, so the four statement theorems cover every constructor.
  The example of finding 16 (`AdmittedAtomsNestedExamples`) is now a statement that is not ready and
  ends as `unmodeled` with the input database. The change touches `RowInsert.lean` and `ForeignKeyRows.lean`,
  which mutants copy: `tests/mutant_guards_test.py` and the tests `test_every_counter_mutant_changes_a_verdict`,
  `test_every_foreign_key_mutant_changes_a_verdict` and `test_every_pragma_mutant_changes_a_verdict` are the
  tests of the touched mutants. The check that the change keeps every
  prediction (`just dev-verdict` for all claimed corpora and `diff -r` of the predictions of the given
  files) is a local check of this change; the Nix results are recorded when they are available. Tests:
  `tests/test_model_package.py`,
  `tests/valid_atoms_theorems_test.py`, `tests/admitted_atoms_resolver_facts_test.py`,
  `tests/admitted_atoms_statement_theorems_test.py` (new formulas without the hypothesis
  `withoutRules`, and the laws of the four atoms).
- 2026-10-24: part 2 is done. The review of "The row engine tests every row that it writes" had one
  should (R19, the status entry cited local results), fixed here. Open for part 3: the resolver link of a
  resolved `.createIndex` and `.addColumn`, and the resolve state that matches the snapshot of the
  connection; the lemma that the resolver makes only described programs is not needed under decision M.
- 2026-10-24: the Nix checks of part 2 passed at sruvpzpy (reported by the coordinator): `just test-full`
  and `just verdict` pass; corpus-v4 AGREE 673, corpus-v5 AGREE 2946, corpus-v50 AGREE 17, corpus-v51
  AGREE 21, corpus-v52 AGREE 33.
- 2026-10-24: part 3, commit "Run theorems of the Admitted atoms without hypotheses on the statements". The
  generic layer now sees `ready` (`RunHoldsReady.lean`: `StatementKeepsReady`, `runSqlFrom_holds_ready`,
  `runSql_holds_ready`; `ScriptRunDerived.lean`: `runScriptFrom_holds_derived`, whose condition comes from the
  invariant and the resolver instead of `ScriptConditionsWith`). The resolver facts that part 1 left open are
  `Resolved.Statement.SchemaLink` (ADD COLUMN: `strictDefaultFits`; DROP: `Catalog.DropClosed`), stated
  positively because CREATE TRIGGER IF NOT EXISTS of an existing trigger resolves to `.drop []`
  (`ResolveStatementForms/Link/Facts/Applied.lean`). The resolve state of a connection is defined from the
  connection state, so no link between them is needed. One theorem per atom for `runSqlFrom`, `runSql`
  (`AdmittedSqlRunsCatalog/Rows.lean`) and `runScriptFrom` (`ScriptRunAdmittedCatalog/Rows.lean`), and the
  bundle `Database.Admitted`; decision 2 a): "rows stored" lists "rows wide" (`Database.RowsStoredWide`), "rows
  aliased" lists "catalog supported" (`Database.RowsAliasedSupported`). The `runScriptFrom` theorems of the
  four constraint atoms (`ScriptRunConstraints.lean`) now assume `Database.AdmittedWith profile atom`, a
  context in execution mode with the limits of the profile, and no hypothesis on the statements;
  `KeysUniqueScriptRun.lean` and the `*ScriptConditions` definitions are removed. The corollary
  `runScriptFrom_valid` and `runScriptStep_valid` (`ScriptRunValid.lean`) with `Database.valid_empty`. The
  surface has `Sql.runFrom_valid` (induction over `Sql α`) and `Sql.runFrom_database_valid` in
  `ProgramRun.lean`; the removal of `Run.checked` stays in ADR 0017, S4. Examples:
  `AdmittedRunsExamples.lean` (the corollary applied to a script with CREATE INDEX, ADD COLUMN, DROP TABLE of a
  table with an index and a trigger, a cascade and ROLLBACK), `AdmittedRunsConditionExamples.lean` (resolver
  facts, the invariants, the conditions that stay, with runs that break the atom). Tests:
  `tests/admitted_atoms_run_theorems_test.py`, and the restated formulas of `valid_atoms_theorems_test.py` and
  `keys_unique_theorems_test.py` follow the new signatures.
- 2026-10-24: part 3, review of the first commit: three musts (R2 the plain words of `StatementKeepsReady` and
  of `mixedRun_rowsAliased`; R9 the module description and proof sketch of `resolveCreateTrigger_schemaLink`
  for `.drop []`) and two shoulds (R9 a docstring for `pastLargest`; R13 the dated amendments in ADR 0012
  and the record of slice 4 in ADR 0022), fixed in the `refactor:` commit that adds the records. The plans of
  the slice are marked READY (not DONE) in the first lines of both files.
- 2026-10-24: part 3, review of the `refactor:` commit: one must (R19, the record in ADR 0022 said that every
  successful resolution meets `SchemaLink`; the theorem needs a valid input catalog), fixed in the next commit.
- 2026-10-24: part 3 is done. The review of the second `refactor:` commit had no findings. Next: `just
  test-full` and `just verdict` of the whole task (the coordinator runs them); the task is not marked DONE.
  For ADR 0017, S4: `runScriptFrom_valid` (context in execution mode, `context.profile.limits =
  profile.limits`, start state `Database.valid_empty`) and `Sql.runFrom_valid` /
  `Sql.runFrom_database_valid` (`ProgramRun.lean`) give outcomes 7, 8 and 10; the check `Run.checked` is
  still there.
- 2026-10-24: the Nix checks of the whole task pass at the end of part 3. `just test-full` passes,
  and `just verdict` passes (corpus-v4 AGREE 673, corpus-v5 AGREE 2946, corpus-v50 AGREE 17,
  corpus-v51 AGREE 21, corpus-v52 AGREE 33). `just test-nix` passes (67 tests), and
  `just test-scheduled-checks` passes (47 tests). The task is DONE.
