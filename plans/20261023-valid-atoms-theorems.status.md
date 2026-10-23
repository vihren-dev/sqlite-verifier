# Status: the theorems of the other Valid atoms (ADR 0022, slice 3)

Created 2026-10-23. Status: DONE (2026-10-23); the owner decided on 2026-10-23 (below).
Task: [task file](20261023-valid-atoms-theorems.task.md).
Specification: [ADR 0022](../docs/adr-0022-database-validity.md), D1, D3 and D4 (slice 3).
Needed by: [ADR 0017](../docs/adr-0017-user-surface.md), S4.
Depends on: [slice 2](20261023-keys-unique.task.md); part 1 is in this line of changes, part 2
is in progress in another workspace.

## Relevant files

- The atoms: `packages/belay-sqlite-model/Belay/Sqlite/Model/DatabaseConstraints.lean`
  (`Table.NotNull`, `Table.ChecksHold`, `Table.TypesFit` and their database forms),
  `DatabaseConstraintChecks.lean` (`Table.constraints_iff` and the three `_iff` lemmas),
  `LiteralData.lean` (`checkHolds`, `checksHold`, `typesFit`, `notNullRows`, `constraints`).
- The statement step: `StatementStep.lean`, `StatementRun.lean` (`checkedWrite`),
  `Execution.lean` (`step`: ADD COLUMN, CREATE, DROP), `Upsert.lean`, `UpsertRun.lean`,
  `SqlState.lean`.
- The row engine: `ForeignKeyWrites.lean`, `RowEngine.lean`, `ForeignKeyRows.lean`,
  `RowInsert.lean`, `TriggerRun.lean`, `ForeignKeyPhases.lean`.
- ADD COLUMN: `Database.lean` (`Database.addColumn`), `Resolution/ReadDefaults.lean`
  (`readDefaultValue`), `Resolution/ReadDefaultLaws.lean` (`readDefaultValue_stored`),
  `Resolution/AddColumn.lean` (`strictDefaultFits`), `Resolution/ExprAny.lean`
  (`Resolved.Expr.readsBelow`), `Resolution/StrictTypes.lean` (`StrictType.fits`).
- The runs: `StatementStep.lean` (`runSqlFrom`, `runSql`), `ScriptRun.lean` (`runScriptFrom`).
- Slice 2 to reuse: `KeysUniqueFrame`, `KeysUniqueWrites`, `KeysUniqueUpsert`,
  `KeysUniqueCreate`, `KeysUniqueAddColumn`, `KeysUniqueDrop`, `DropPositionLaws`,
  `ExprAppendLaws`, `KeysUniqueExamples`; from part 2 (other workspace): `RowEngineKeyState`,
  `RowEngineKeySteps`, `RowEngineTriggers`, `RowEngineDelete`, `RowEngineUpdate`,
  `RowEngineInsert`, `KeysUniqueRowEngine`, `KeysUniqueStatement`.
- Tests: `tests/shared_table_shape_test.py` (`compile_checks`), `tests/test_model_package.py`.

## Size estimate

Measured on 2026-10-23. Slice 2 part 1 is 1279 Lean lines in 10 modules (with its examples);
part 2, at its commit `pvmyqwkoowor` (before its run theorems), is 824 lines in 8 modules.
Slice 3 has three atoms, but they read one row at a time, so one argument can serve the three
(task file, "Key points").

| Work | Lines |
| --- | --- |
| Frame lemmas and the laws of `setRows`, append, DROP and a sublist for the three atoms | 120–170 |
| Plain INSERT, UPDATE and DELETE, upsert, the forms that keep the database | 150–220 |
| CREATE TABLE, CREATE INDEX, CREATE TRIGGER and DROP (no condition) | 80–120 |
| ADD COLUMN with the three conditions | 150–220 |
| Examples of part 1 (the five counterexamples) | 60–90 |
| **Part 1** | **560–820** |
| Row engine with decision 1 a) (part 2's proofs with a parameter, and three instances) | 260–450 |
| The statement theorems over all of `runStatement` | 80–120 |
| Run theorems for `runSqlFrom` and `runScriptFrom`, and the corollary of the four atoms | 100–180 |
| Examples of part 2 (SET NULL, the concrete run) | 30–60 |
| **Part 2** | **470–810** |

Total: about 1000–1600 lines in 8 to 13 new modules. With decision 1 b), the row engine is a copy
of part 2's proofs for a new invariant: about 600–800 lines instead of 260–450. The pragma forms
of ADR 0019 slice 2 add about 20–60 lines when they land.

The size is near that of slice 2, so the task file proposes the same split into two parts
(decision 2).

## Owner decisions

Decided by the owner on 2026-10-23: the recommendation of each of the three decisions below was
accepted. 1 a): after slice 2 part 2 lands, slice 3 makes the atom a parameter of the row-engine
proofs in `refactor:` commits. 2 a): two parts in one task file, each with `just test-full` and
`just verdict`. 3 a): slice 4 adds "each CHECK reads only the columns of its table" to
`CatalogTable.supported`, proves that the runs keep it, and removes the hypothesis from the
`runScriptFrom` theorem. The text of the decisions is kept as asked.

1. **The invariant of the row engine.** Slice 2 part 2 proves the row engine with an invariant
   that is fixed to `Database.KeysUnique` (`KeyState.KeysUnique`, `NestedRun.KeepsKeys`). Its
   proofs rest mainly on two facts of the atom: a table that passes `LiteralData.constraints`
   satisfies it, and a table with a sublist of the rows and the same entry satisfies it. The
   three atoms of this slice have the same two facts.
   - a) Slice 3 makes the atom a parameter of part 2's proofs, in `refactor:` commits after
     part 2 lands, and gets the four atoms as instances.
   - b) Slice 3 copies the structure of part 2's proofs for one invariant of the three atoms,
     and part 2 stays as it is.
   - c) Part 2 makes the atom a parameter before it lands.

   Recommendation: a). It removes about 300 lines of copy (a measured cost, R18), and part 2
   lands without a change. Option c) changes work that is in progress in another workspace.
2. **The split.**
   - a) One task file in two parts (task file, "Parts"), each with `just test-full` and
     `just verdict`, as slice 2 (its decision 2 a)).
   - b) One part.

   Recommendation: a). Part 1 can start now, on slice 2 part 1; part 2 needs slice 2 part 2.

The conditions of ADD COLUMN in the run theorems follow slice 2's decision 1, option A: a
hypothesis on each reached ADD COLUMN, and slice 4 proves the resolver facts. This adds to
slice 4: each resolved ADD COLUMN has `strictDefaultFits`, and each CHECK of a table reads only
its columns, which needs decision 3.

3. **The CHECK condition for `runScriptFrom`** (task file, "Conditions"). The start database of
   `runScriptFrom` is any database. A database that satisfies `Database.Valid` can have a CHECK
   that reads past the width of its table, and then an ADD COLUMN that the resolver accepts
   breaks "checks hold". No atom excludes such a CHECK today (`CatalogTable.supported` reads no
   CHECK).
   - a) Slice 4 adds to `CatalogTable.supported` (so to `Database.Admitted`) that each CHECK of
     a table reads only the columns of the table, proves that the runs keep it, and then removes
     the hypothesis.
   - b) The `runScriptFrom` theorem of "checks hold" keeps the hypothesis after slice 4.

   Recommendation: a). SQLite does not open such a database (task file, "Conditions"), so the
   fact holds for each database that SQLite can reach, as ADR 0012, decision 5 requires for an
   Admitted fact. This slice does not depend on the answer.

## Changes at the rebase onto the pragma and evidence-after-error stacks
- 2026-10-23: `Resolved.Statement.setting` now has a second field, the value of the setting. The
  hypothesis `writesNone` of the theorems `runStatement_writesNone_rowLocal`, and of the three
  theorems of not null, types fit and checks hold for the statements that write no row, therefore
  reads `∃ setting on, statement = .setting setting on`. It still means "the statement is a
  setting"; the statements do not change.
- 2026-10-23: the generalized row engine proofs follow the base of ADR 0019, slice 2
  (`recursive_triggers`): `enterProgram_holds` is new (the entry of the frame of a program runs a
  nested DELETE of no rows and drops its state; it was `enterProgram_keysUnique` in the commit of
  the keys-unique slice), `runProgram_holds` uses it, and the rows that REPLACE deletes are
  deleted in the frame with the algorithm REPLACE and the setting `recursive` as `fire`. No
  statement of a theorem changes.
- 2026-10-23: `Connection.afterStep` takes the whole resolution state (`after : ResolveState`) instead of
  the setting `foreignKeys`, and `runScriptStep` is `runScriptStepWith` and `ranScriptStep`.
  `Connection.afterStep_holds` takes the resolution state as its second argument; its statement
  and the statements of the run theorems do not change otherwise.
- 2026-10-23: the conditions of the statement theorems of not null, types fit and checks hold match
  `.setting _ _` (a setting has two fields). The conditions and the statements do not change: a
  setting requires nothing and changes no database.

## Findings

A proof that fails is recorded here with a counterexample (ADR 0022, D3). None yet.

## Progress log

- 2026-10-23: the task file and this status file. Review round 1: one R19 must (the CHECK
  condition cannot go from the `runScriptFrom` theorem with resolver facts alone; now
  decision 3) and one R19 should (a local probe cited here), fixed. Round 2 (the refactor): no
  findings.
- 2026-10-23: part 1, commit 1: `RowLocalAtoms` (the frame lemmas of the three atoms and
  `RowLocalAtom`, the three facts that one argument uses for the three atoms) and `RowLocalFrame`
  (`Effect.Satisfies`, `Database.EachTable.setRows` and `.append`). Owner decisions recorded.
- 2026-10-23: part 1, commit 2: `RowLocalWrites` and `RowLocalUpsert` (the theorems for every
  `RowLocalAtom` of plain INSERT, UPDATE, DELETE, the forms that write no row, and upsert) and
  `RowLocalWriteTheorems` (the three instances of each, 15 theorems). Review of commit 1: no findings.
- 2026-10-23: part 1, commit 3 (`refactor:`): `Database.table_drop_cases` extracted from
  `Database.KeysUnique.drop` (`KeysUniqueDrop`), for the drop theorem of this slice.
- 2026-10-23: part 1, commit 4: `RowLocalSchema` (CREATE TABLE, CREATE INDEX, CREATE TRIGGER and
  DROP for every atom; DROP needs no `RowLocalAtom`) and `RowLocalSchemaTheorems` (the 12 instances).
- 2026-10-23: part 1, commit 5 (`refactor:`): the docstrings of the theorems that conclude
  `Effect.Satisfies` name its error cases (review of commit 2, R2 must, fixed; its R19 must on the
  progress entry of commit 3 rejected: the entry was one commit ahead). Reviews of commits 3 and 4
  pending.
- 2026-10-23: part 1, commit 6: `RowLocalAddColumn` (the conditions `Database.RowsWideAt`,
  `ChecksReadBelowAt`, `StrictDefaultFitsAt`, `AddedCell`, `step_addColumn_cases`,
  `Table.appendColumns_cases`, `Database.EachTable.addColumn`) and `RowLocalAddColumnTheorems` (the
  table laws and the statement theorems of ADD COLUMN for the three atoms), and `RowLocalExamples`
  (the five counterexamples, each condition necessary).
- 2026-10-23: part 1, commit 7 (`refactor:`): the statement theorems of all three files say once
  which databases `Effect.Satisfies` covers (reviews of commits 4, 5 and 6: one R2 must each for 4 and
  6, two R9 should for 5, fixed). Tests: `just documentation-inventory`; the predictions
  against the baseline (below).
- 2026-10-23: part 1 review outcomes: commits 1, 3 and 7: no findings; the findings of commits 2, 4,
  5 and 6 recorded and resolved. Tests: predictions rebuilt at the end of part 1, `diff -r` against the
  baseline. Part 1 waits for `just test-full` and `just verdict` by the lead.
- 2026-10-23: part 2, commit 1 (`refactor:`, owner decision 1 a): the row-engine proofs of slice 2
  take the fact of a table as a parameter (`TableFacts`, `Database.Every`, `RowEngineFacts`). The modules
  `KeysUniqueKeyState`, `KeysUniqueKeySteps`, `KeysUniqueTriggers`, `KeysUniqueRowDelete`,
  `KeysUniqueRowUpdate` and `KeysUniqueRowInsert` are now `RowEngineKeyState`, `RowEngineKeySteps`,
  `RowEngineTriggers`, `RowEngineDelete`, `RowEngineUpdate` and `RowEngineInsert`; `RowEngineWrites` has
  `runRows_holds`, `keyRun_holds`, `rowsKeys_holds` and `dropKeys_holds`; `KeysUniqueRowEngine` is the
  instance (`keysUniqueFacts`, `rowsKeys_keysUnique`, `dropKeys_keysUnique`, same statements as before),
  and `RowLocalAtom.facts` is the instance of the three atoms. The slice-2 status file keeps the old names
  in its log.
- 2026-10-23: part 2, commit 2 (`refactor:`): the run theorems of slice 2 take the property of databases
  and the condition of statements as parameters (`RunHoldsStep`, `RunHolds`, `ScriptRunHolds`:
  `StatementKeeps`, `runSqlFrom_holds`, `runSql_holds`, `runScriptFrom_holds`); `KeysUniqueRunStep`,
  `KeysUniqueRuns` and `KeysUniqueScriptRun` are the instances with the statements of slice 2 unchanged
  (tests: `tests/keys_unique_theorems_test.py`). Review of commit 1: one R19 must (the task file said that
  the invariant is fixed), fixed here.
- 2026-10-23: part 2, commit 3 (`refactor:`): the docstrings of `StatementKeeps` and
  `keysUnique_statementKeeps` say the error cases (review of commit 2: two R2 musts, fixed).
- 2026-10-23: part 2, commit 4: the statement theorems of the three atoms over all of `runStatement`
  (`RowLocalStatement`: `runStatement_rowLocal` for every `RowLocalAtom`; `ValidAtomsStatement`:
  `Resolved.Statement.NotNullCondition`, `TypesFitCondition`, `ChecksHoldCondition`, `runStatement_notNull`,
  `runStatement_typesFit`, `runStatement_checksHold`), the run theorems (`ValidAtomsRuns`:
  `runSqlFrom_*`, `runSql_*`, `runScriptFrom_*` for each atom), the corollary of the four constraint
  atoms (`ValidAtomsTogether`: `Database.ConstraintAtoms`, `runSqlFrom_constraintAtoms`,
  `runSql_constraintAtoms`, `runScriptFrom_constraintAtoms`) and `tests/valid_atoms_theorems_test.py`. No
  proof failed. The pragma forms of ADR 0019 slice 2 are not in this line of changes; the statement
  theorems cover them when they land (`runStatement_rowLocal` has a case for each constructor).
  Tests: `tests/test_model_package.py -m unit`, `tests/keys_unique_theorems_test.py`,
  `tests/valid_atoms_theorems_test.py`.
- 2026-10-23: review of commit 4: five R2 musts (the plain words of the statement theorems, the
  run conditions and the script conditions omitted the cases that require nothing), fixed in a
  `refactor:` commit (review: no findings). Commit 6: `ValidAtomsExamples` (a run of the corollary
  over a script with a CHECK, a NOT NULL column, a STRICT table, an upsert, a cascading DELETE and
  a ROLLBACK; SET NULL into a NOT NULL column fails and keeps the database) and
  `Resolved.Statement.atomsCondition_of_unconditioned`.
- 2026-10-23: review of commits 5 and 6 (the refactor and the examples): no findings. The records of
  slice 3 in ADR 0022, D4 and ADR 0012, decision 5. Next: `just test-full` and `just verdict` of
  the slice (the lead runs them); the task is not marked DONE.
- 2026-10-23: `refactor:` after the second reviews of the stack that the rebase changed: the progress
  lines of both status files name tests and cite no local result; one docstring of `RowLocalWrites`
  is reflowed. The other findings of those reviews were fixed by later commits of the stacks.
  Tests: `tests/keys_unique_theorems_test.py`, `tests/valid_atoms_theorems_test.py`.
- 2026-10-23: on the tip of slices 2 and 3, on top of the evidence-after-error stack: `just
  test-full` passes, and `just verdict` passes (corpus-v4 AGREE 673, corpus-v5 AGREE 2945,
  corpus-v50 AGREE 17, corpus-v51 AGREE 21). `just test-nix` passes (67 tests), and
  `just test-scheduled-checks` passes (46 tests). The task is DONE.
