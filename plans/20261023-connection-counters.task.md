# The connection counters (ADR 0024, slice 1)

Created 2026-10-23. Status: OPEN (not started). This file says what must be true when the task
is done. Status file: [status](20261023-connection-counters.status.md).
Specification: [ADR 0024](../docs/adr-0024-connection-state-and-random-values.md) (ACCEPTED
2026-10-23), D1 to D3, D5 for the connection functions, D6 slice 1; owner decisions 1, 3 and 5
(option A of each). [ADR 0011](../docs/adr-0011-product-trust-and-development-integrity.md) (the
judge); `CLAUDE.md`, "Development claims". It comes before ADR 0017's S6.
Builds on: the row engine of ADR 0018 D4 and D5; the run that continues (ADR 0017, D3); the
evidence after an error (`plans/20261023-evidence-after-error.task.md`, record version 6).

## Scope

`changes()`, `total_changes()` and `last_insert_rowid()` get a meaning in the model, and the
five functions of ADR 0024 get SQLite's errors in generated columns, index expressions and
partial index filters. Out of scope: random values (slice 2: `random()` and `randomblob()` stay
`unmodeled-function` elsewhere); the reads of ADR 0024 "Not decided here"; the random rowid.

## Pull requests

As for the evidence after an error (its owner decision 1, A) and ADR 0024's owner decision 3:
- **PR A, the work** (no change to the lock): the model, the surface, the conformance runner,
  `conformance/predict.py`, and the readers of the new record version (`record_versions.py`,
  `native_replay.model_case`), tested with Lean examples and hand-written inputs.
- **PR B, the judge change** (on top of PR A; the owner's approval): the recorder change of
  outcome 9, the authored definitions and their corpus writer, their tests and mutants,
  `judge/records.py`, corpus-v52, its claim, the old-corpus cases that now agree in `mustAgree`,
  and the new `integrity/judge.lock.json` (`just judge-lock`).

## Outcome

1. **The counters are state.** `SqlState` holds SQLite's three counters (`db->nChange`,
   `db->nTotalChange`, `db->lastRowid`), each known or unknown. `runSqlFrom` takes them in its
   `SqlState`, and `Connection` carries them from statement to statement in `runScriptFrom`.
2. **The rule of each statement.** After each statement that the model describes, the counters
   follow the table of facts of ADR 0024 ("Context"), also for the statements of trigger
   programs and for foreign-key actions. Checked natively (3.51.0, status file), in addition to
   the ADR's facts: an `INSERT OR IGNORE` that skips every row sets `changes()` to 0; `DELETE`
   without `WHERE` counts each row; the DO UPDATE rows of an upsert count, and leave
   `last_insert_rowid()`; `ROLLBACK`, `BEGIN`, `COMMIT`, `PRAGMA`, `CREATE`, `ADD COLUMN`,
   `DROP INDEX` and a `DROP TABLE` of a table that no foreign key references leave all three.
   A counter that adds to an unknown value stays unknown (`total_changes()` after a start with
   an unknown total).
3. **A failed INSERT.** `last_insert_rowid()` is the rowid of the last row that the
   statement inserted before the failure, or the value from before when it inserted none.
   - A plain INSERT (no clauses or algorithms, no trigger program, no foreign-key check)
     checks each row before it inserts it, so the last row is the row before the failing row:
     the first row such that the rows up to it fail a constraint, the distinct rowids or the
     rowid alias check. Probes (table with rowid 1): `VALUES (10), (11), (1)` with a UNIQUE `v`
     that holds 1 gives 3; `(20), (20)` gives 2; a NOT NULL, CHECK or `datatype mismatch`
     failure at the second or third row gives the rowid of the row before it; a first row that
     fails leaves the value. So the model knows this counter, and does not make it unknown (D1).
   - A write that runs row by row knows its last inserted row, in SQLite's order of the
     checks, programs and actions of each row. Probes: a `RAISE(ABORT)` of an AFTER INSERT
     program comes after the insert of its row (`VALUES (20, 1), (21, -1), (22, 1)` gives 21);
     of a BEFORE INSERT program, before it (`(40, 1), (41, -1)` gives 40). An `ON DELETE
     RESTRICT` action fails when it runs: `INSERT OR REPLACE INTO p VALUES (7, 7), (8, 1)`, whose
     second row deletes a referenced parent, gives 7. A missing parent of an INSERT fails at the
     end of the statement when SQLite marks it as a multi-row write (`isMultiWrite`, set for
     example by a `SELECT`, several `VALUES` rows or a trigger; `sqlite3BeginWriteOperation`):
     `VALUES (30, 1), (31, 2), (32, 1)` with no parent 2 gives 32, `SELECT 40, 2` gives 40,
     `VALUES (60, 2)` with an AFTER INSERT trigger gives 60. Else it fails before the insert
     (`fkey.c`): a one-row `VALUES (30, 2)` leaves the value.
4. **One computation.** The step of a statement (`runStatement`) gives the counts with its
   effect, from the same computation. `Output.done` and `statementOutput` read that count;
   `statementOutput` no longer computes a count, and no longer calls `runStatement` a second
   time for a write that checks foreign keys. The change count of an output stays as the
   recorder records it: present for INSERT, UPDATE and DELETE only. The effect database of
   each statement does not change.
5. **Reads.** The three functions resolve to expression forms that read the counters from the
   statement's evaluation context, with the values from before the statement. Described: a read
   of `changes()` in each expression of a statement; `total_changes()` in a query, and in a write
   that runs no trigger program and no foreign-key action; `last_insert_rowid()` in a query, an
   UPDATE and a DELETE. Also checked natively: `RETURNING` and `WHERE` read the values from
   before, and in an INSERT of several rows or an upsert without triggers `total_changes()` is
   the same for each row. Model restrictions, each with a reason (R7): `last_insert_rowid()` in
   an INSERT or an upsert; `total_changes()` in a write that runs trigger programs or
   foreign-key actions; each of the three in a trigger program, a `DEFAULT` and a `CHECK`.
6. **An unknown counter.** A statement that reads an unknown counter ends the run of
   `runScriptStep` with `Output.unmodeled` and a reason that names the counter and what to do
   (write the value as a literal, or run under an environment that gives the counters). Its
   support check (`statementReady`, so `supportedSqlFrom`) is false, so no verification target
   covers it. An unknown counter that no statement reads does not stop a run.
7. **Schema positions.** Each of the five functions in a generated column, an index expression
   or a partial index filter gives SQLite's error `non-deterministic functions prohibited in
   generated columns` (`... in index expressions`, `... in partial index WHERE clauses`) where
   SQLite gives it, also for `random()` and `randomblob()`. A `DEFAULT` and a `CHECK` with one
   of the three counters are restrictions (outcome 5); with `random()` or `randomblob()` they
   stay restrictions, as today.
8. **The environment.** `Env` gets the counters at the start of a run. `Env.default` leaves
   them unknown. A named environment for a new connection gives 0 to each, as SQLite does.
   `Sql.run` starts with the environment's counters. Under `Env.default`,
   `INSERT INTO t VALUES (1); SELECT last_insert_rowid()` gives the inserted rowid, and
   `SELECT changes()` alone gives `Output.unmodeled`. `Script.run_env` keeps its form: its
   hypothesis also excludes the reason of outcome 6.
9. **The recorder (PR B).** In a new record version, the recorder records the three counters
   of the writer connection at the start of the migration, after the setup and after each
   reopen of the connection. The judge gives them to the subject with the other inputs, and the
   case run starts from them. Records of older versions keep their meaning: their case run
   starts with unknown counters.
10. **The specification follows.** ADR 0024 gets a dated note of slice 1; ADR 0017's deferred
    row (which says that ADR 0024 is PROPOSED) keeps only slice 2; the two format documents
    (`docs/native-corpus-format.md`, `docs/conformance-format-v2.md`) describe the new version.

## Measurement

Lexical scan of the claimed corpora (`judge/claims.json`) on 2026-10-23 (script in the status
file): 22 records call one of the five functions, all of them `changes()`: 10 in corpus-v4 and
12 in corpus-v5. 8 call it in the migration (v4: `e_changes` 5.2.0, 6.0, 7.1; v5: the same and
`delete4` 3.0.1 and 3.0.2); the other 14 call it only in the setup. In each of the two corpora,
4 of them are in `mustAgree` today (`e_changes` 5.2.1, 5.2.2, 6.0 and 7.1): they create a trigger
whose body calls `changes()`, and no statement that runs reads a counter. They must keep
agreeing. The model resolves a trigger's body at the write that runs it
(`Resolution/TriggerBodies.lean`), so the restriction of a read in a trigger program comes at
that write, not at `CREATE TRIGGER`. After this task, `delete4-3.0.1` (v5: DELETE from a
`WITHOUT ROWID` table, then `SELECT printf('(%d)', changes())`) must agree too. The other 13
stay out: a read in a trigger program that runs is a restriction, and `delete4-3.0.2` starts
with `WITH RECURSIVE`, which the frontend refuses for a write.

## Tests

- **Lean examples with kernel proofs** for each row of the table of facts and each read of
  outcome 5, under `Env.default` and under the new-connection environment: the counts of
  REPLACE, IGNORE, DO UPDATE, `WITHOUT ROWID`, trigger programs and foreign-key actions;
  each failed row of the table (ABORT, ROLLBACK, FAIL, the failed `DROP TABLE`) with the
  values of the ADR's examples; the failed INSERTs of outcome 3; each restriction and each
  schema error of outcome 7.
- **Laws**: the counters change only through writes and the `DROP TABLE` of outcome 2 (a
  query, `BEGIN`, `COMMIT` and `ROLLBACK` keep them); a run from unknown counters that does
  not end at a counter read gives the same outputs and connection databases from any known
  counters; `Script.run_env` with the new hypothesis; the run laws of the key points.
- **Error order** (outcome 7): the probes of the status file (for example `changes() + nosuch`
  and `nosuch + changes()` give `no such column`, `count(a) + changes()` gives the
  non-deterministic error, `changes() + count(a)` the misuse) each agree, or are a restriction.
- **The authored corpus corpus-v52** (PR B), in `CASE_SETS` of
  `tests/conformance_query_coverage_test.py`, each case AGREE with a kernel proof: one case
  for each row of the table of facts and each read of outcome 5, reads before the migration
  sets a counter, `total_changes()` after trigger programs and foreign-key actions, and the
  reads after a failed statement (record version 6 mode).
- **Mutants**, each killed by one authored case, each with a `rule:` guard
  (`conformance/mutant_guards.py`): the rows that REPLACE deletes counted; the rows of trigger
  programs counted in `changes()`; the rows of trigger programs and foreign-key actions left out
  of `total_changes()`; a `DROP TABLE` of a referenced table that does not set `changes()`;
  `changes()` kept after a failure; `last_insert_rowid()` taken back by the rollback; the
  auxiliary changes before a failure left out of `total_changes()`.
- **The recorder** (PR B): a record of the new version has the counters after a setup that
  writes, and 0 after a setup that reopens the connection; older modes record as before.
- **The judge** (PR B): `tests/test_judge_records.py` gives the counters of a new-version
  record to the subject. **The subject** (PR A): `tests/conformance_predict_test.py` and a
  `model_case` test with hand-written new-version inputs.
- **The verdict**: every case of corpus-v52 and `delete4-3.0.1` agree; no other verdict
  changes. The checks of `CLAUDE.md`, "Checks and their cadence".

## Key points

- **Where the counts are today.** `statementOutput` (`StatementOutput.lean`) computes each
  count again: `rows.length` for a plain INSERT, the selected rows for UPDATE and DELETE,
  `keptCount` for an upsert, and `keyRows` of a second `runStatement` call for a write that
  checks foreign keys. `KeyState.written` (`ForeignKeyPhases.lean`) keeps the statement's own
  rows only; the rows of trigger programs (`TriggerRun.lean`) and of foreign-key actions
  (`ForeignKeyRows.lean`) are not counted. `insertOutcome` and `checkedWrite`
  (`StatementRun.lean`) check all rows of a plain INSERT at once (outcome 3).
- **The clock is the pattern, with one difference.** Reads go through `EvalContext`
  (`ExprFault.lean`) as `EvalContext.clock` does, and a statement that reads a counter is known
  from its resolution, as `Resolved.Statement.readsClock` (`StatementClock.lean`). But the
  relation `ProfileExecutes` (`SqlExecution.lean`) quantifies over clock assignments; it must
  not quantify over start counters, because a free triple gives runs that SQLite cannot give
  (ADR 0024, "Alternatives considered"). Outcome 6 uses the support check instead.
- **The walk order of schema errors.** `generatedIssue` (`GeneratedColumns.lean`) and
  `indexExpressionIssue` (`IndexTerms.lean`) look for a time keyword only after
  `resolveOperand` succeeds, so another error of the walk comes first. SQLite keeps the last
  error of its walk, and a missing column stops it (probes, status file). The precedent is
  `ParameterOrder.lean`: give SQLite's error where it is the only error that the walk can find,
  and a restriction elsewhere. `random()` and `randomblob()` fail in `scalarCall`
  (`FunctionCalls.lean`) before these checks today.
- **`Script.run_append` becomes false as it is.** `(db.run p).db.run q` starts `q` from
  `Database.Raw.connection` (`Run.lean`), with unknown counters, while `db.run (p ++ q)` runs
  `q` with the counters that `p` left. For `p = INSERT ...` and `q = SELECT changes()`, the left
  side gives the count and the right side `Output.unmodeled`. Owner decision 2 of the status
  file chooses the new law. `Connection.eq_idle` (`RunLaws.lean`) also gets the counters.
  `Database.Raw.run_append` holds as it is.
- **Other work on the same declarations.** ADR 0022 slice 2 (workspace `adr22s2`) proves that
  `runStatement` and `runSqlFrom` keep unique keys; a new field of `SqlState` or `StatementRun`
  breaks proofs that take these structures apart (as `Connection.eq_idle` does). Outcome 4
  keeps the effect databases, so its theorem statements stay. The pragmas of ADR 0019 slice 2
  (workspace `adr19s2`) add statement forms; each leaves the counters (outcome 2).
- **The recorder.** `record_sql` (`native_record.py`) runs the setup and the migration on one
  writer connection, and reopens it for `{"reopen": true}` and for a read-only profile; read the
  counters just before the migration's `execute`, with `sqlite3_changes64`,
  `sqlite3_total_changes64` and `sqlite3_last_insert_rowid` (`native_library.py` declares none of
  them today). The observations between statements are queries, which do not change the
  counters. `execute` records `changes` only for DML without DDL actions.
- **Record version and corpus number.** The evidence after an error adds version 6 (the run
  that continues) and corpus-v51; corpus-v50 is the pragmas corpus. This task takes the next
  version, 7 (version 6 with the counters), and corpus-v52 (owner decision 1 of the status file).
  Check `judge/claims.json`, `record_versions.py` and the open stacks again before recording.
- **Judge-locked files** (ADR 0011): `judge/*.py`, `judge/*.json`, each claimed corpus,
  `nix/sqlite.nix`, `nix/flake.lock`; not `conformance/native_*.py` (the owner reviews PR B).
- **Files below 200 lines** (`StatementStep.lean` has 199), docstrings, plain words (`AGENTS.md`).
