# Status: the connection counters (ADR 0024, slice 1)

Created 2026-10-23. Status: IN PROGRESS (the owner accepted the decisions; commits 1 to 6 are done; the judge-change commits (PR B) are next).
Task file: [task](20261023-connection-counters.task.md).
Specification: [ADR 0024](../docs/adr-0024-connection-state-and-random-values.md) (ACCEPTED
2026-10-23), D1 to D3, D5, D6 slice 1.

## Relevant files

- Model: `Model/SqlState.lean`, `Model/ScriptRun.lean`, `Model/StatementStep.lean`,
  `Model/StatementRun.lean`, `Model/StatementOutput.lean`, `Model/Output.lean`,
  `Model/ExprFault.lean`, `Model/StatementClock.lean`, `Model/SqlExecution.lean`,
  `Model/ForeignKeyPhases.lean`, `Model/ForeignKeyRows.lean`, `Model/ForeignKeyWrites.lean`,
  `Model/TriggerRun.lean`,
  `Model/LiteralData.lean`; resolution: `FunctionCatalog.lean`, `FunctionCalls.lean`,
  `GeneratedColumns.lean`, `IndexTerms.lean`, `TableChecks.lean`, `ParameterOrder.lean`,
  `TriggerBodies.lean` (all under `packages/belay-sqlite-model/Belay/Sqlite/`).
- Surface: `packages/belay/Belay/Sqlite/Env.lean`, `Run.lean`, `ProgramRun.lean`,
  `ProgramLaws.lean`, `RunLaws.lean`.
- Conformance: `packages/verifier-conformance/VerifierConformance/Pass.lean`, `Case.lean`,
  `Predict.lean`; `conformance/predict.py`, `record_versions.py`, `native_replay.py`.
- Recorder and judge (PR B): `conformance/native_record.py`, `native_statements.py`,
  `native_library.py`, `judge/records.py`, `judge/claims.json`.

## Progress

- 2026-10-23: the task file, from the code of this tree, the ADR's facts, the native probes
  below and the measurement below.
- 2026-10-23: review round 1 (R19, must): outcome 3 gave the plain INSERT's rule to every
  failed INSERT. Fixed: a write that runs row by row has its own rule, with new probes.
- 2026-10-23: review round 2 (R19, must): a one-row INSERT fails a foreign key before its
  insert. Fixed: outcome 3 gives SQLite's rule (`isMultiWrite`), from `fkey.c`, `build.c`
  and `insert.c` of the pinned sources and new probes.
- 2026-10-23: review round 3: finding 1 (R19, must): a `RESTRICT` action of a REPLACE fails
  when it runs, not at the end of the statement. Fixed in outcome 3, with a new probe.
  Finding 2 (R19, must) is rejected: it says that the trigger probe gives 0, 3, 60; a new run
  of the probe gives 1, 1, 1 after `INSERT INTO p VALUES (1)` and 0, 2, 60 after the failed
  INSERT (the trigger's row counts, the statement's own row does not).
- 2026-10-23: review round 4 (R19, must): the probe list did not say which probes ran in a new
  session, so the rejection of round 3 compared two histories. Fixed: each item of the probes
  of failed writes that run row by row is a new session, with the counters before it. This is
  the fourth round in a row with a must finding, so the fix has no review; the owner decides.
- 2026-10-23: commit 1 (the counters of a connection, plain counts). `Counters`, `Counts`,
  `SqlState.counters` (unknown by default), `StatementRun.counts`, `advanceRun` (the transition of
  a run, with its counts for the counters), `PlainCounts` (the counts of a plain INSERT, upsert,
  UPDATE and DELETE), `Output` reads the change count from the counts of the run (one
  computation). The move of `advanceWith` to `SqlAdvance.lean` keeps `StatementStep.lean` under
  200 lines; the mutants and the coverage scope that named `StatementStep.lean` follow it.
  `Script.run_append` keeps its statement: its proof uses `runScriptFrom_counters`
  (`ScriptRunCounters.lean`), which says that a run does not depend on the counters while no
  statement reads them; `Connection.eq_idle` is replaced by `Connection.sameBesidesCounters_idle`.
  Commit 3 replaces the lemma by the form with reads and adds the `endsRun` hypothesis of owner
  decision 2. The row engine does not count yet (commit 2): a write that checks foreign keys or
  runs programs has the interim counts of its own rows. Tests that this commit
  touches: the examples of `CounterExamples.lean` (kernel, checked by the package build),
  `tests/mutant_guards_test.py`, the mutant tests by name that the moved text touches
  (`test_every_write_mutant_changes_a_verdict`, `test_every_after_error_mutant_changes_a_verdict`,
  `test_every_upsert_and_algorithm_mutant_changes_a_verdict`, `conformance_resolve_mutants_test.py`),
  and `test_model_mutation`, with a runtime built by `just conformance-build`. Nix evidence for
  this commit is pending: the status file cites no local result (ADR 0011). The mutants of the
  change counts of UPDATE, DELETE and upserts now change `StatementStep.lean` and `PlainCounts.lean`
  (guards `rule:runStatement` and `rule:upsertCounts`).
- 2026-10-23: refactor after the review of commit 1 (R11: kernel examples of the upsert counts
  for DO UPDATE, a skipped row, OR IGNORE, OR FAIL and OR ABORT in `CounterExamples.lean`; R12:
  `StepCatalogLaws.lean` is under 200 lines again; R19: this file). Tests:
  `CounterExamples.lean` and `StepCatalogLaws.lean` (package build).
- 2026-10-23: commit 2 (the row engine counts). `KeyState` gets `own`, `credited` and `inserted`;
  `KeyStop.error` carries the state of the failure; `NestedRun.credited` (`RowCredit.lean`) runs each
  nested write of a program or an action with no row counted and moves its rows to `credited` when
  it completes, so a nested write counts for `total_changes()` also when the statement fails later,
  and never for `changes()` or `last_insert_rowid()`; `replaceDelete` keeps the rows that REPLACE
  deletes out of the count; a single-row write that fails an immediate foreign key fails before it
  stores the row; `KeyState.keptCounts` and `KeyState.failedCounts` give the counts of `keyRun`,
  which replace the interim counts of commit 1. The proofs follow: `replaceDelete_holds`,
  `NestedRun.credited_keeps` (`RowEngineWrites.lean`), and `insertRow_holds`, `updateRow_holds`
  with the new state fields; no statement of ADR 0022 changed. Examples checked by the kernel
  (`CounterRowExamples.lean`): the counts of a trigger program, `RAISE(ABORT)` after a completed
  nested insert, `RAISE(FAIL)`, a cascade, DROP TABLE of a referenced table, REPLACE and the early
  and late foreign-key failures; the expected values are those of native SQLite 3.51.0. Tests:
  the package build, `tests/mutant_guards_test.py`, and the mutant tests by name
  `test_every_foreign_key_mutant_changes_a_verdict`, `test_every_trigger_mutant_changes_a_verdict`
  and `test_every_pragma_mutant_changes_a_verdict` (the REPLACE mutant now changes `replaceDelete`
  in `RowInsert.lean`, guard `rule:replaceDelete`). Nix evidence is pending.
- 2026-10-23: refactor after the review of commit 2 (R11: `replaceDelete` gives back the rows
  counted also when a program of the delete stops the statement, `KeyResult.mapState`, with the
  examples of `RAISE(FAIL)` in the trigger of a REPLACE delete in `CounterRowExamples.lean`; R2: the
  words of `KeyStop.Holds` say that the error stop carries a state that the invariant does not
  constrain; R19: the opening status). The proofs `KeyResult.mapState_holds` and
  `NestedRun.credited_keeps` are in `RowCreditHolds.lean`. Tests: the package build and the pragma
  mutant test by name, `test_every_pragma_mutant_changes_a_verdict`.
- 2026-10-23: commit 3 (the reads). `CounterKind`, `Counters.read`, `.firstUnknown`, `.view` and
  `Counters.LessKnown` (`Counters.lean`); `Resolved.Expr.counter kind` (resolved from `changes()`,
  `total_changes()` and `last_insert_rowid()` in `FunctionCalls.lean`), `EvalContext.counters`,
  `Statement.counterReads` (`StatementCounterReads.lean`). The counters reach every function that
  takes the clock through a new binder `(counters : Counters)` after `clock`: `runStatement`,
  `step`, `Resolved.Query.runOn`, `statementContext`, the theorems of ADR 0022 and their
  helpers. `SqlState.statementRun state clock parameters statement` is the one call of
  `runStatement` for a state: it gives the statement the counters that it reads (`Counters.view`)
  and sets `ready` false when one of them is unknown. `runScriptStep` ends the run with
  `counterUnknownReason` at such a statement. The independence law is now the relation
  `LessKnown` (`StatementCountersLaws.lean`, `ScriptRunCounters.lean`): a connection that knows
  fewer counters gives the same outputs and databases while the run does not end.
  `Script.run_append` (`RunLaws.lean`) takes the hypothesis `modeledLater` (owner decision 2, A);
  `Connection.lessKnown_idle` replaces `sameBesidesCounters_idle`. Restrictions: a counter in a
  CHECK is `check-function`, in a trigger body or `WHEN` is `triggerForm`, in a DEFAULT stays
  `unmodeled-default`; the new kind `connection-counter-read` is `last_insert_rowid()` in an
  INSERT or upsert and `total_changes()` in a write with trigger programs or foreign-key actions
  (`Resolved.Statement.readsCounterInWrite`, `ResolveState.withWrite`). Examples checked by the
  kernel: `CounterReadExamples.lean`. Statements of ADR 0022 and other theorems that changed:
  every theorem that takes a clock now also takes `counters` (binder order `(clock : Int)
  (counters : Counters) (parameters : List Value)`, calls `clock counters parameters`, literal-0
  calls `0 {} []`; their plain words say "clock value, counters, parameter list"); `NoWrites`
  gets the conjunct that the query reads no counter, because a query that reads one is not a
  statement that leaves the state alone in the proofs; `SuccessfulBody` is indexed by `Counters`.
  Recipe for the concurrent sessions (adr22s3, adr22s4): add the binder after every `(clock : Int)`
  of a theorem about `runStatement`, `step`, `runOn`, `statementContext` or `subqueryContext`
  (`sed -E 's/\(clock : Int\) \(parameters/(clock : Int) (counters : Counters) (parameters/'`), and
  `clock parameters` becomes `clock counters parameters` at their calls; `Expr.isParameter` is
  now `Expr.isRunValue` (a counter is a run value). `SqlState.statementRun` is called with its
  name in `SqlAdvance.lean` and `Pass.lean`, not with dot notation, so that the model mutation
  test replaces it. `Resolution/Restrictions.lean` is over 200 lines since before this task (the
  registry is one inductive type). Tests: the package build, `just dev-verdict` (corpus-v4 673
  AGREE and 591 MODEL_UNSUPPORTED, corpus-v5 2946 AGREE and 1430 MODEL_UNSUPPORTED: `delete4-3.0.1`
  agrees now; corpus-v50 17 and corpus-v51 21 AGREE; no DISAGREE), `tests/mutant_guards_test.py`,
  `tests/restriction_registry_test.py`, the 58 restriction examples run through the dev runtime,
  `test_model_mutation` (a runtime assembled from the local builds) and the mutant tests by name
  `test_every_after_error_mutant_changes_a_verdict` and `test_every_write_mutant_changes_a_verdict`.
  Nix evidence is pending.
- 2026-10-23: refactor after the review of commit 3 (R4: the two surface fixtures
  `tests/surface/GuideRuns.lean` and `ProgramExamples.lean` give `Script.run_append` its new
  hypothesis, and `DbBangChecks.lean` gives `ExecutionError.message` the counters; R2: the words of
  the row-local theorems and `ExecutionMessages.lean` name the counters, the example of
  `insertReadingChanges` checks the stored value; R5: `RunStep.LessKnown` names its constructors).
  R11 is deferred to commit 4 (schema positions). Tests: the package build (`lake build` of the
  model, all examples), the surface fixtures compiled with `lean --setup` from `lake setup-file`
  (the three changed files and all others), `pytest -m unit`, and the mutant tests by name
  `test_every_trigger_mutant_changes_a_verdict`, `test_every_foreign_key_mutant_changes_a_verdict`,
  `test_every_subquery_mutant_changes_a_verdict` and `test_every_date_function_and_modifier_mutant_changes_a_verdict`
  (a runtime assembled from the local builds). Nix evidence is pending.
- 2026-10-23: commit 4 (schema positions, outcome 6, and R11 of the review of commit 3).
  `Resolution/NondeterministicCalls.lean` finds a call of `changes()`, `total_changes()`,
  `last_insert_rowid()`, `random()` or `randomblob(n)` in a syntactic walk and resolves the
  expression without the calls (`prohibitNondeterministic`): no other error gives the error of
  the position, and any other prepare error, also a missing column, gives the new
  restriction `nondeterministic-error-order` (registry `.unsupported`, because SQLite keeps the
  last error of its walk and some errors stop it: `count(a) + changes()` gives the
  non-deterministic error, `changes() + count(a)` the misuse, `nosuch + changes()` the missing
  column and `abs(nosuch) + changes()` the call; the model does not follow the order; review round
  1 found the last of these). Three entry
  points use it: `resolveGeneratedExpression`, `indexExpressionTerm` and `indexFilter`. CHECK and
  DEFAULT keep their restrictions. `Resolution/NondeterministicExamples.lean` holds the kernel
  examples (five functions in three positions, nested calls, the missing column, a wrong number of
  arguments, the restriction), `conformance/restriction_examples.py` and
  `docs/semantic-subset.md` have the new restriction. Tests: the package build (`just dev-build`),
  `just dev-verdict`, `tests/restriction_registry_test.py`, `tests/mutant_guards_test.py` and the
  restriction examples run through the dev runtime. Nix evidence is pending.
- 2026-10-23: refactor after the review of commit 4 (R19: a missing column does not decide the
  error alone, so every expression with a call and another prepare error gives
  `nondeterministic-error-order`, with the new probes in "Native probes"; R12: `Restrictions.lean`
  is now below 200 lines, by wrapping and shortening comments; R19: the top status and the
  entry of commit 4 cite no local results). Tests: the package build, `just dev-verdict`,
  `tests/restriction_registry_test.py`, `tests/mutant_guards_test.py` and the restriction
  examples. Nix evidence is pending.
- 2026-10-23: commit 5 (the environment, outcome 8). `Env.counters` (unknown by default),
  `Env.newConnection` (0 for each counter), `Database.Raw.connection` with the counters as an
  optional argument, `Sql.run` from the counters of the environment, and the exports
  `Counters`, `CounterKind` and `counterUnknownReason`. `RunStep.LessKnown` is now the stronger
  relation (the first step reads an unknown counter, or both steps are the same, with the same
  end reason), so `runScriptFrom_counters` has the weaker hypothesis "no output ends at an unknown
  counter" (`Output.endsAtUnknownCounter`); `Script.run_append` derives it from `endsRun`.
  `ProgramEnvLaws.lean` (split from `ProgramLaws.lean`) has `Sql.runFrom_counters`,
  `Run.checked_congr`, `Sql.run_env` and `Script.run_env`, whose hypotheses are the clock
  condition and the counter condition. Tests: the package builds of `belay-sqlite-model` and
  `belay` (`just dev-build`), the surface fixtures with `lean --setup` (`ProgramExamples.lean`
  with the new counter examples and the laws, `GuidePrograms.lean` and all others),
  `tests/mutant_guards_test.py`, `tests/restriction_registry_test.py` and `test_model_mutation`.
  Nix evidence is pending.
- 2026-10-23: commit 6 (the readers of record version 7, outcome 9, work part). The tools read
  a native record of version 7, which is a version 6 record with the field `counters`
  (`changes`, `totalChanges`, `lastInsertRowid`): `conformance/record_counters.py` checks the
  field (version 7 must hold exactly these three integers in the 64-bit ranges, an older version
  must not hold it), `record_versions.py` has the new group `COUNTED`, and `native_replay.py` and
  `predict.py` pass the counters to the model input. In Lean, `Case.counters` and
  `PredictInput.counters` are optional (none: the run starts with unknown counters) and
  `startConnection` uses them. A case without counters is written without the field, so older
  cases keep their form. No recorder and no judge file changes in this commit.
  `tests/conformance_counters_test.py` checks a version 6 and a version 7 prediction, the
  model case with the compiled check and the kernel proof (one counter shifted gives DISAGREE),
  and the field check. Tests: `just dev-build`, `just dev-verdict`, the new test file and the
  test files for predict, continuing cases, the model, generation, records, shards and storage.
  Nix evidence is pending.
- 2026-10-23: refactor after the review of commit 6. The writer of a case omits `counters`
  with an explicit match on every JSON constructor (R5), and the errors of
  `conformance/record_counters.py` name the record field, state the requirement and say to
  record the case again (R10). The format documents (R13) change with the recorder in the judge
  commits (PR B), where version 7 first exists. Tests: `just dev-build` and
  `tests/conformance_counters_test.py`, `tests/conformance_model_test.py`. Nix evidence is pending.
- 2026-10-23: the Nix inputs of the readers. `build-support/tests.nix` lists the Python modules
  of the suites that import `record_versions`, so `record_counters` (imported by `native_replay`
  and `predict`) is added to the three lists, and `tests/nix_suites.json` puts
  `tests/conformance_counters_test.py` in the `harness` suite with the test of the continuing
  case. `tests/test_test_ownership.py` and `tests/test_ci_checks.py` pass. Nix evidence is
  pending.

## Native probes (3.51.0, dev shell `sqlite3`, one statement per line)

The ADR's table of facts and its examples are not repeated here. New facts for the task file:

- Generated column, `CREATE TABLE g(a, b AS (E))`: `changes()`, `total_changes()`,
  `last_insert_rowid()`, `random()` and `randomblob(2)` each give `non-deterministic functions
  prohibited in generated columns`. `changes() + nosuch` and `nosuch + changes()` give `no such
  column: nosuch`. `changes() + count(a)` gives `misuse of aggregate function count()`;
  `count(a) + changes()` the non-deterministic error. `changes() + nosuchfn(1)` gives `no such
  function: nosuchfn`; `nosuchfn(1) + changes()` the non-deterministic error. `abs(changes())`
  gives the non-deterministic error; `changes(1)` gives `wrong number of arguments to function
  changes()`; `changes() + ?` gives `parameters prohibited in generated columns`.
  `count(a) + CURRENT_TIME` gives the non-deterministic error.
  Added in review round 1 of commit 4 (index expression, `CREATE INDEX i ON d(E)`):
  `abs(nosuch) + changes()`, `coalesce(nosuch, 1) + changes()`, `nosuchfn(a) + changes()` and
  `nosuch IS NULL AND changes()` give the non-deterministic error, while `nosuch + changes()`,
  `-nosuch + changes()`, `(nosuch) + changes()`, `CASE WHEN nosuch THEN 1 END + changes()`,
  `changes() + abs(nosuch)`, `nosuch + abs(changes())` and `a + changes() + nosuch` give `no such
  column: nosuch`. So a missing column does not decide the error alone: the model has the
  restriction `nondeterministic-error-order` for every expression with a call and another error.
- Index, table `t(a, b)` with one row, and an empty table `e(a)`: `CREATE INDEX i ON t(changes())`,
  `t(a + total_changes())`, `t(random())` and `e(changes())` give `non-deterministic functions
  prohibited in index expressions`; `WHERE last_insert_rowid() > 0` and
  `WHERE randomblob(1) IS NOT NULL` give `... in partial index WHERE clauses`.
  `e(a + nosuch, changes())` gives `no such column: nosuch`; `e(changes(), a + nosuch)` the
  non-deterministic error. `t(changes() + count(a))` gives the misuse; `WHERE changes() + nosuch`
  and `WHERE nosuch + changes()` give `no such column`; `t(abs(changes()))` the
  non-deterministic error.
- `CREATE TABLE c1(a CHECK (changes() >= 0), b DEFAULT (changes()))` and
  `CREATE TABLE c2(a DEFAULT (last_insert_rowid()), b DEFAULT (total_changes()), c DEFAULT (random()))`
  succeed.
- Reads, on `t(id INTEGER PRIMARY KEY, v, w)` after `INSERT INTO t(v) VALUES (1), (2), (3)`
  (counters 3, 3, 3): `UPDATE t SET w = total_changes(), v = changes() WHERE id <=
  last_insert_rowid() RETURNING id, v, w, changes(), total_changes(), last_insert_rowid()` gives
  `1|3|3|3|3|3`, `2|3|3|3|3|3`, `3|3|3|3|3|3`, then 3, 6, 3. `DELETE FROM t WHERE id = 1
  RETURNING changes(), total_changes(), last_insert_rowid()` gives `3|6|3`, then 1, 7, 3.
  `SELECT (SELECT changes()), total_changes() FROM t WHERE changes() = 1` gives `1|7` twice.
  `INSERT INTO t(id, v) VALUES (2, 9) ON CONFLICT(id) DO UPDATE SET w = changes() RETURNING id, w`
  gives `2|1`, then 1, 8, 3. `DELETE FROM t` (2 rows) gives 2, 10, 3.
- `r(id INTEGER PRIMARY KEY, u UNIQUE)` with rows 1 and 2: `INSERT OR REPLACE INTO r VALUES (3, 'a')`
  gives 1, 13, 3 (13 = 10 + 2 + 1); `INSERT OR IGNORE INTO r VALUES (4, 'b')` gives 0, 13, 3.
  An INSERT into a `WITHOUT ROWID` table gives 1, 14, 3. `BEGIN`, an INSERT of rowid 10 and
  `ROLLBACK` give 1, 15, 10.
- Without triggers: `INSERT INTO t(v, w) VALUES (total_changes(), changes()), (total_changes(),
  changes())` after counters 2, 2, 2 stores 2 and 2 in both rows; an upsert of two DO UPDATE
  rows and one new row with `SET w = total_changes() + 100` stores 104 in both updated rows,
  then 3, 7, 9.
- After `INSERT INTO t VALUES (1), (2)` (2, 2, 2): `PRAGMA integrity_check`,
  `PRAGMA foreign_key_check`, `PRAGMA table_info(t)`, `PRAGMA recursive_triggers = 1` and
  `PRAGMA foreign_keys = 1` leave 2, 2, 2. `ALTER TABLE t ADD COLUMN b DEFAULT 3`,
  `CREATE INDEX`, `DROP INDEX`, `CREATE TABLE u(x)`, an INSERT into `u` and `DROP TABLE u` with
  foreign keys on and no reference give 1, 3, 1.
- Failed plain INSERTs, `t(id INTEGER PRIMARY KEY, v UNIQUE, n NOT NULL DEFAULT 0, c CHECK (c IS
  NULL OR c > 0))` with row (1, 1), counters 1, 1, 1: `INSERT INTO t(v) VALUES (10), (11), (1)`
  fails, then 0, 1, 3; `(20), (20)` fails, then 0, 1, 2; `INSERT INTO t(v, n) VALUES (30, 1),
  (31, NULL)` fails, then 0, 1, 2; `INSERT INTO t(v, c) VALUES (40, 1), (41, 1), (42, -1)` fails,
  then 0, 1, 3; `INSERT INTO t(id, v) VALUES (50, 50), ('x', 51)` fails with `datatype mismatch`,
  then 0, 1, 50; `INSERT INTO t(id, v) VALUES (1, 60)` fails, then 0, 1, 50.
- Failed writes that run row by row. Each item is a new session; the counters before the first
  failed statement are 1, 1, 1.
  - `t(id INTEGER PRIMARY KEY, v)` with row (1, 1) and `CREATE TRIGGER tr AFTER INSERT ON t WHEN
    new.v < 0 BEGIN SELECT RAISE(ABORT, 'fail'); END`: `INSERT INTO t VALUES (10, -1)` fails,
    then 0, 1, 10; `INSERT INTO t VALUES (20, 1), (21, -1), (22, 1)` fails, then 0, 1, 21. With a
    BEFORE INSERT trigger of the same form on `b`, `INSERT INTO b VALUES (40, 1), (41, -1)`
    fails, then 0, 1, 40.
  - Foreign keys on, `p(id INTEGER PRIMARY KEY)` with row 1, `c(id INTEGER PRIMARY KEY, pid
    REFERENCES p(id))`: `INSERT INTO c VALUES (30, 1), (31, 2), (32, 1)` fails with `FOREIGN KEY
    constraint failed`, then 0, 1, 32.
  - The same tables: `INSERT INTO c VALUES (30, 2)` fails, then 0, 1, 1 (the value before);
    `INSERT INTO c SELECT 40, 2` fails, then 0, 1, 40; `INSERT INTO c VALUES (50, 1)` succeeds,
    and `INSERT INTO c VALUES (51, 1), (52, 2)` fails, then 0, 2, 52.
  - The same tables, `log(x)` and `CREATE TRIGGER ct AFTER INSERT ON c BEGIN INSERT INTO log
    VALUES (new.id); END`: `INSERT INTO c VALUES (60, 2)` fails, then 0, 2, 60.
- `p(id INTEGER PRIMARY KEY, u UNIQUE)` with rows (1, 1) and (2, 2), foreign keys on, and
  `c(id INTEGER PRIMARY KEY, pid REFERENCES p(id) ON DELETE RESTRICT)` with row (5, 1)
  (counters 1, 3, 5): `INSERT OR REPLACE INTO p VALUES (7, 7), (8, 1)` fails with `FOREIGN KEY
  constraint failed`, then 0, 3, 7; `INSERT OR REPLACE INTO p VALUES (9, 1)` fails, then 0, 3, 7.

## Measurement

The scan of the task file's "Measurement", run in this workspace with `python3 -I`: for each
corpus of `judge/claims.json`, read each record of `shards/*.jsonl.gz` (the record or its
`native` member) and match `\b(changes|total_changes|last_insert_rowid|random|randomblob)\s*\(`,
ignoring case, against `migrationSql` and `setupSql`. `synthetic-workload` has no shards at its
top; a `grep` of its `corpus/shards` found no match. `mustAgree` of corpus-v4 and corpus-v5
was read from `judge/claims.json`.

## Coordination with the work in flight

- **The evidence after an error** (workspace `errev`): record version 6 and corpus-v51. This
  task's corpus needs both the run that continues and the counters at the start, so it takes
  version 7 and corpus-v52 (decision 1). Its PR A needs the version 6 readers of errev's PR A.
- **The pragmas of ADR 0019 slice 2** (workspace `adr19s2`): corpus-v50 and new statement
  forms, which leave the counters.
- **The keys-unique theorems of ADR 0022 slice 2** (workspace `adr22s2`): theorems over
  `runStatement` and `runSqlFrom`. A new field of `SqlState` or `StatementRun` changes proofs
  that take them apart; the theorem statements stay, because the effect databases stay.
- Order (decision 3): pragmas (v50); errev PR A and PR B (v51); keys-unique; this task's PR A;
  this task's PR B (v52).

## Owner decisions

On 2026-10-23, the owner accepted the recommendation of each decision below: record version 7
(version 6 and the counters) for corpus-v52; the hypothesis that the run of `q` does not end
early in `Script.run_append`; and the pull request order of "Coordination with the work in
flight". A fifth review, of the last fix of the status file, had no findings.

1. **The record of corpus-v52.**
   - A (recommended): version 7 is version 6 with the three counters at the start of the
     migration. The cases can read the counters after a failed statement, so the mutants of the
     failed rows get native evidence in this slice. Cost: PR B waits for errev's PR B.
   - B: version 7 is version 5 with the counters, recorded now. The failed rows keep Lean
     examples only, and their mutants wait for a later corpus.
   - C: a field on version 6 instead of a version. errev's owner decision 2 chose a version
     over a field for the same reason: each reader would have to check the field.
2. **`Script.run_append`** (`RunLaws.lean`), which becomes false (task file, key points).
   - A (recommended): the law gets a second hypothesis: no output of the run of `q` on the
     database that `p` gives ends the run (`Output.endsRun`). Then `q` reads no unknown counter
     there, and it gives the same outputs with the counters that `p` left. The guide's form stays
     an equation of outputs.
   - B: the law runs `q` on the connection at the end of `p`
     (`Script.runOn (db.run p).connection q`), with no new hypothesis. The guide's form then
     names a connection, which the guide does not use.
3. **The order of the pull requests**: as in "Coordination" (recommended), or this task first
   with version 6 and corpus-v51, which would make errev move to version 7 and corpus-v52.
   Cost of the second: errev is in progress and its task file names version 6 and v51.

## Review records

None yet.
