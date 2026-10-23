# Status: the theorem of "keys unique" (ADR 0022, slice 2)

Created 2026-10-23. Status: DONE (2026-10-23). The owner decided the three
decisions on 2026-10-23 (below), and replaced decision 1 after finding 1.
Task: [task file](20261023-keys-unique.task.md).
Specification: [ADR 0022](../docs/adr-0022-database-validity.md), D3 and D4 (slice 2).
Needed by: [ADR 0017](../docs/adr-0017-user-surface.md), S4.

## Relevant files

- The atom: `packages/belay-sqlite-model/Belay/Sqlite/Model/DatabaseConstraints.lean`
  (`Table.KeysUnique`, `Database.KeysUnique`), `DatabaseConstraintChecks.lean`
  (`uniqueRows_iff`, `Table.keysUnique_iff`), `LiteralData.lean` (`keyEqual`, `uniqueRows`,
  `constraints`), `Resolution/Catalog.lean` (`Catalog.uniqueKeys`).
- The statement step: `StatementStep.lean` (`runStatement`, `runSqlFrom`, `runSql`),
  `StatementRun.lean` (`checkedWrite`), `Execution.lean` (`step`), `Upsert.lean`,
  `UpsertRun.lean`, `SqlState.lean`.
- The row engine: `ForeignKeyWrites.lean`, `RowEngine.lean`, `ForeignKeyRows.lean`,
  `RowInsert.lean`, `TriggerRun.lean`, `ForeignKeyPhases.lean`.
- Schema changes: `Database.lean` (`Database.drop`, `Database.addColumn`),
  `Resolution/CatalogDrop.lean`, `Resolution/Keys.lean`, `Resolution/ExprAny.lean`,
  `ExprEval.lean`.
- The runs: `ScriptRun.lean` (`runScriptFrom`); the surface run in
  `packages/belay/Belay/Sqlite/ProgramRun.lean` (`Run.checked`), which this slice does not change.
- Laws to reuse: `DatabaseLaws.lean`, `StepCatalogLaws.lean`, `SqlStateLaws.lean`,
  `QueryPlainLaws.lean` (the pattern of a mutual induction over `Expr`), `Comparison.lean`.
- Tests: `tests/shared_table_shape_test.py` (`compile_checks`), `tests/test_model_package.py`.

## Size estimate

Measured from the definitions on 2026-10-23, in Lean lines with docstrings:

| Work | Lines |
| --- | --- |
| Frame lemma and the frame facts of `setRows`, `addColumn`, append and drop | 120–160 |
| Lookup lemma (symmetry and transitivity of `keyEqual`) | 60–90 |
| Plain INSERT, UPDATE and DELETE | 60–90 |
| Upsert (an invariant over the steps of `upsertSteps`) | 100–140 |
| CREATE TABLE, CREATE INDEX, CREATE TRIGGER | 100–140 |
| ADD COLUMN (with the lemma that an expression that reads below a width ignores appended cells) | 150–220 |
| DROP (with the renumbering of `afterDrop`) | 120–180 |
| Examples of part 1 | 40–60 |
| **Part 1** | **750–1080** |
| Row engine (an invariant over `KeyState`, by induction on fuel, through CASCADE, SET NULL, SET DEFAULT, triggers, `RAISE` and REPLACE) | 300–420 |
| The statement theorem over all of `runStatement` | 60–90 |
| Run theorems for `runSqlFrom` and `runScriptFrom` | 120–180 |
| **Part 2** | **480–690** |

Total: about 1200–1800 lines in 9 to 13 new modules. The row engine is the largest single form
and the largest risk. The pragma forms of ADR 0019 slice 2 add an estimated 40–120 lines when
they land, mostly in the row engine for `recursive_triggers`.

## Owner decisions

On 2026-10-23 the owner chose 1 d), 2 a) and 3 a). After finding 1, the owner replaced 1 d)
on 2026-10-23 with option A: both run theorems (`runSqlFrom` and `runScriptFrom`) assume that each
CREATE INDEX, ADD COLUMN and DROP that the run reaches meets its condition (CREATE INDEX: the index
is supported over the catalog; ADD COLUMN: `Database.AddColumnCondition`; DROP:
`Catalog.DropCondition`). Slice 4 proves the resolver facts and removes the hypothesis from the
`runScriptFrom` theorem; the `runSqlFrom` theorem keeps it, as finding 1 shows that it is needed.


1. **How the run theorems state the conditions of ADD COLUMN and DROP** (task file,
   "Conditions"). A run can reach an ADD COLUMN or a DROP that needs a fact which this slice does
   not prove for the runs.
   - a) A hypothesis: each ADD COLUMN and DROP that the run reaches meets its condition, on the
     database at that point. Slice 4 then removes the hypothesis with its theorems.
   - b) The run theorems cover only scripts without ADD COLUMN and DROP.
   - c) No run theorem in this slice; slice 4 adds them.
   - d) This slice also proves that the runs keep `Table.RowsWide` and `Catalog.Valid`, and the
     resolver closure of DROP (work of slice 4, about 300 more lines).

   Recommendation: a). The theorem is true as stated, S4 can use it at once for the guide's
   programs, and slice 4 removes the hypothesis without a change to the statement theorem.
2. **The split.**
   - a) One task file in two parts (task file, "Parts"), each with `just test-full` and
     `just verdict`.
   - b) Two task files, one for each part.
   - c) One part.
   - d) Part 1 only; the row engine goes to a later slice, and the statement theorem covers the
     writes through the row engine only when no rules apply.

   Recommendation: a). Part 1 is useful alone (the lookup lemma and most forms), part 2 has one
   subject (the row engine), and one task file keeps the conditions and the tests in one place.
   Option d) leaves out the writes with foreign keys on, which the guide's programs use.
3. **The surface run.** ADR 0022, D3 names `runSql`. The surface runs `runScriptFrom`: `db.run`
   is `Run.checked` of it (`packages/belay/Belay/Sqlite/ProgramLaws.lean`).
   - a) Prove the run theorem for both.
   - b) Prove it for `runSqlFrom` only; S4 proves the step to `runScriptFrom`.

   Recommendation: a). S4 needs the theorem for the run of the surface, and `runScriptFrom`
   uses the same statement step (`runScriptStep`), so the added work is small (about 60 lines,
   in the estimate above).

## Changes at the rebase onto the pragma and evidence-after-error stacks

- 2026-10-23: `Resolved.Statement.setting` now has a second field, the value of the setting
  (`setting setting on`). The hypothesis `writesNone` of `runStatement_keeps_database` and
  `runStatement_writesNone_keysUnique` therefore reads `∃ setting on, statement = .setting
  setting on`. It still means "the statement is a setting"; the statements do not change.
- 2026-10-23: the proofs of the row engine follow the base of ADR 0019, slice 2
  (`recursive_triggers`): `enterProgram_keysUnique` is new (the entry of the frame of a program
  runs a nested DELETE of no rows and drops its state), `runProgram_keysUnique` uses it, and the
  rows that REPLACE deletes are deleted in the frame with the algorithm REPLACE and the setting
  `recursive` as `fire`. No statement of a theorem changes.
- 2026-10-23: `Connection.afterStep` takes the whole resolution state (`after : ResolveState`) instead of
  the setting `foreignKeys`, and `runScriptStep` is `runScriptStepWith` and `ranScriptStep`.
  `Connection.afterStep_keysUnique` takes the resolution state as its second argument; its
  statement and the statements of the run theorems do not change otherwise.

## Findings

A proof that fails is recorded here with a counterexample (ADR 0022, D3).

1. **Decision 1 d) does not hold for `runSqlFrom` over every resolved statement** (2026-10-23).
   `runSqlFrom` takes resolved statements, and the step does not check that a resolved
   statement keeps `Catalog.Valid`: `runStatement` runs `.createIndex` as ready
   (`ready := true`) for an index that `CatalogIndex.supported` rejects. Counterexample, checked
   by the kernel in `KeysUniqueExamples`: the table `t(a)` with the rows `[1]` and `[1]`; the
   resolved CREATE INDEX of a unique index on `a` with the filter `column1 = 5` (column 1 is past
   the width) is ready and keeps the keys unique; ADD COLUMN with the default 5 is ready, and
   after it the rows conflict on the index. So a run theorem for `runSqlFrom` without an
   assumption on its statements is false. A short resolved INSERT row is not a second
   counterexample: `runStatement` marks it not ready.
   - For `runScriptFrom`, which resolves syntax, the claim is plausible, but its proof needs
     facts of the resolver (each resolved CREATE INDEX is supported over the catalog, each
     resolved DROP is closed), which are more than the 300 lines of option d).
   - Possible ways: the `runSqlFrom` theorem with the hypothesis of option a) and the
     `runScriptFrom` theorem without it (with the resolver facts); or option a) for both.
   - Part 1 does not depend on the answer: its theorems state the conditions as hypotheses.
     The owner answered on 2026-10-23 (option A, see "Owner decisions"); the task file was
     amended in the spec commit after the answer.

## Progress log

- 2026-10-23: the task file and this status file. Review round 1: two R19 musts (the filters
  of partial indexes in the ADD COLUMN condition; the result type of `runScriptFrom`), fixed.
  Round 2: no findings.
- 2026-10-23: part 1, first commit: `Effect.KeysUnique`, the frame lemma, the lookup lemma, and
  the theorems for plain INSERT, UPDATE, DELETE, upsert, CREATE TABLE, CREATE INDEX, CREATE
  TRIGGER and the statements that write no row (`KeysUniqueFrame`, `KeysUniqueLookup`,
  `KeysUniqueWrites`, `KeysUniqueUpsert`, `KeysUniqueCreate`).
- 2026-10-23: refactor after review round 1 (five R3 musts: proof sketches of the helper
  theorems; one R19 should: no local check results in this file), fixed.
- 2026-10-23: review round 2 (the refactor): no findings. ADD COLUMN: `Database.AddColumnCondition`
  (rows wide, each key of the target reads below the old width), `Resolved.Expr.evaluate_append`
  (`ExprAppendLaws`) and `runStatement_addColumn_keysUnique` (`KeysUniqueAddColumn`).
- 2026-10-23: review round 3 (ADD COLUMN): two R2 musts (the plain words of `filterMap_set_none`
  and `Database.KeysUnique.addColumn` omitted the cases without an element or a table), fixed.
- 2026-10-23: review round 4 (the refactor): no findings. DROP: `Catalog.DropCondition` (a kept
  unique index is on a kept table), the laws of the kept positions (`DropPositionLaws`) and
  `runStatement_drop_keysUnique` (`KeysUniqueDrop`).
- 2026-10-23: review round 5 (DROP): no findings. The owner decisions recorded. The examples
  module `KeysUniqueExamples` (not in the root import): the lookup lemma for the guide's
  `accounts_live`, the counterexamples of "Conditions", and the counterexample of finding 1.
  Tests: `tests/test_model_package.py -m unit`.
- 2026-10-23: review round 6 (the examples): no findings. Part 2: the invariant of the row engine
  (`KeysUniqueKeyState`), the foreign-key steps keep the rows (`KeysUniqueKeySteps`), the trigger
  programs (`KeysUniqueTriggers`), `deleteRow`, `updateRow` and `insertRow`
  (`KeysUniqueRowDelete`, `KeysUniqueRowUpdate`, `KeysUniqueRowInsert`), `runRows` and the writes
  with rules (`KeysUniqueRowEngine`), and the statement theorem `runStatement_keysUnique`
  (`KeysUniqueStatement`). No proof of the row engine failed. Tests:
  `tests/test_model_package.py -m unit`.
- 2026-10-23: end of part 1 (xuotovnp). Tests: `just test-full` and `just verdict`, run by the
  lead; the status file cites only Nix check results, so none is cited here.
- 2026-10-23: review round 7 (the row engine): two R2 musts (the plain words of
  `ResultHolds.bind` omitted the stop property of the continuation; those of
  `KeyState.keysUnique_start` named every state with the rows instead of the constructed state),
  fixed.
- 2026-10-23: review round 8 (the refactor): no findings. The task file states the run
  hypothesis of the owner decision that replaced 1 d) (CREATE INDEX, ADD COLUMN and DROP),
  finding 1, and the direction for slice 4.
- 2026-10-23: review round 9 (the task amendment): three R19 musts (finding 1 named the resolver
  instead of resolved statements written directly; the CREATE INDEX fact of slice 4 is false for a
  syntax without terms; the slice-4 theorem must assume `Database.Admitted` at the start), fixed.
- 2026-10-23: review round 10 (the refactor of the task file): no findings. The run theorems:
  the invariant of a state and an outcome and the step `advance_keysUnique`
  (`KeysUniqueRunStep`), `runSqlFrom_keysUnique` and `runSql_keysUnique` over `RunConditions`
  (`KeysUniqueRuns`), `runScriptFrom_keysUnique` over `ScriptConditions`
  (`KeysUniqueScriptRun`), the kernel examples of a run with an INSERT, an upsert, a cascading
  DELETE and a ROLLBACK and of finding 1 as a run (`KeysUniqueRunExamples`, globs only), and the
  test of the formulas and the axioms `tests/keys_unique_theorems_test.py`. Tests:
  `tests/test_model_package.py -m unit`, `tests/keys_unique_theorems_test.py`.
- 2026-10-23: review round 11 (the run theorems): two R3 musts (no proof sketches for
  `keysCondition_of_runCondition` and `runCondition_of_unconditioned`), one R2 must (the plain
  words of `Connection.afterStep_keysUnique` named a hypothesis that the formula does not have)
  and one R1 should (the standard axioms of the test get a name), fixed.
- 2026-10-23: review round 12 (the refactor): no findings. The records of slice 2 in ADR 0022, D4
  and ADR 0012, decision 5. Tests: the predictions of `nix-build integrity/judge.nix -A predictions`
  against the baseline (`diff -r`). Next: `just test-full` and `just verdict` of part 2.
- 2026-10-23: on the tip of slices 2 and 3, on top of the evidence-after-error stack: `just
  test-full` passes, and `just verdict` passes (corpus-v4 AGREE 673, corpus-v5 AGREE 2945,
  corpus-v50 AGREE 17, corpus-v51 AGREE 21). `just test-nix` passes (67 tests), and
  `just test-scheduled-checks` passes (46 tests). The task is DONE.
