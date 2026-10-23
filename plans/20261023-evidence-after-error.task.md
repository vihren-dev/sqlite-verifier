# Evidence for the statements after an error (ADR 0017, deferred)

Created 2026-10-23. Status: OPEN (not started). This file says what must be true when the task
is done. Status file: [status](20261023-evidence-after-error.status.md).
Specification: [ADR 0017](../docs/adr-0017-user-surface.md), "Deferred, with their triggers",
first row, and D3 (amended 2026-10-22: the run continues after an error and resolves each
statement against the current state); [ADR 0011](../docs/adr-0011-product-trust-and-development-integrity.md)
(the judge); `CLAUDE.md`, "Development claims". It comes before S4.
Builds on: S2 (`plans/20261022-surface-s2.task.md`, outcome 2), S3, and ADR 0019 slice 3.

## Scope

The model's run `runScriptFrom` (`Model/ScriptRun.lean`) continues after an error. The surface's
`Database.Raw.run` uses it. No corpus case shows a statement after a failed one, because the
recorder stops at the first error. This task gives that evidence: the recorder runs on after a
failed statement, a new authored corpus records such scripts, and the judge compares the
model's run with them. The old corpora keep their meaning.

Out of scope: new SQL in the model; scripts with a syntax error (the frontend refuses the whole
script, so the model makes no claim about its later statements); errors outside the recorder's
SQL errors (`SQL_ERRORS` in `native_connection.py`: codes 1, 18, 19 and 20), such as
`SQLITE_FULL`, after which SQLite can roll back by itself; a new recording of the old corpora.

## Pull requests

ADR 0011 and ADR 0017's row require two pull requests. Owner decision 1 in the status file
decides where the recorder goes. With its recommendation:

- **PR A, the work** (first; no change to the lock). The subject: the model, the conformance
  runner, `conformance/predict.py`, and the readers of record version 6
  (`record_versions.py`, `native_replay.model_case`). It never changes `judge/`, a claimed
  corpus, `judge/claims.json` or `integrity/judge.lock.json`.
- **PR B, the judge change** (on top of PR A; the owner's approval). The recorder's mode that
  runs on, the authored definitions and their corpus writer, their tests and mutants,
  `judge/records.py`, the new corpus directory, its claim and the new lock
  (`just judge-lock`).

## Outcome

1. **The recorder runs on, by choice.** `record_sql` (`native_record.py`) and `execute`
   (`native_statements.py`) get a mode in which a statement with an SQL error does not end the
   trace. Every statement of the migration then gives one event. A record of this mode has
   native record version 6: version 5 with this rule. Without the mode, the recorder stops at
   the first error, as now, and gives the version that it gives now.
2. **Statement boundaries after a prepare error.** SQLite's prepare tail is not always at the
   end of the failed statement. It stops at the token of a syntax error, and in the middle of
   the text for some resolution errors (`CREATE TABLE t(a, a, b)`, `CREATE TABLE` of a table
   that exists, `CREATE TRIGGER` on a missing table; measured below). In version 6, a
   statement ends at the end of the shortest prefix of the remaining text that
   `sqlite3_complete` accepts, or at the end of the text when no prefix is complete. For a
   statement that prepares, this is where the prepare tail ends; the recorder refuses a case
   where the two differ. The event's `sql` is the whole statement.
3. **What an event records.** The form of each event does not change: `sql`, rows, primary and
   extended code, `phase` (`prepare` or `step`), columns, changes, parameters, tie groups,
   clock value, and the visible and persisted tables with `transactionOpen` after it. Rows of a
   query that failed are the rows that SQLite gave before the error, as now.
4. **The judge.** `judge/records.py` counts version 6 among the versions with outputs
   (`WITH_OUTPUTS`), so the subject gets one list of parameters per statement and the judge
   compares each statement's output. The comparison of steps, phases, boundaries and outputs
   in `judge/compare.py` does not change. Its rule for a script that the frontend refuses
   still reads the last event; the authored corpus has no syntax error, and its claim requires
   every case to agree, so the rule cannot pass a refused case.
5. **The subject predicts with the run that continues.** For a version 6 input, the prediction
   comes from the model's run that continues: the schema resolves as now, then each statement
   resolves against the connection's state when it runs (`Connection.resolveState`), runs, and
   the run goes on after an error. The prediction gives, for each statement, the observation
   after it (both views, `transactionOpen`, primary code, phase) and its output (columns,
   rows, changes). A statement that ends the model's run (`RunStep.ended`) makes the case out
   of scope (`supported` false). For versions 1 to 5, the prediction is the one of today.
6. **One definition of the run.** The evidence must be evidence for `runScriptFrom`. So the
   conformance pass that continues uses the model's step (`runScriptStep`, or a model function
   that `runScriptStep` is defined from), not a copy of it. A theorem states that the outputs of
   the pass are those of `runScriptFrom` for every input, so that a mutant of the model's run
   (Tests) changes the verdict.
7. **The classifier and the kernel proofs.** A model case (`native_replay.model_case`, the
   Lean `Case`) of a version 6 record says that the run continues. `classifyCase` then
   compares each statement with the pass of outcome 6, and `checkCase` proves the agreement by
   `decide +kernel`. For older cases nothing changes.
8. **The SQLite behaviors that the new corpus shows.** Each case has statements after a failed
   one that read or write what the failure left. Checked natively (3.51.0, status file):
   - a prepare error (`no such table`, `no such column`, a wrong count of values) in autocommit
     and inside a transaction: nothing changes, and a transaction stays open;
   - a prepare error that SQLite reports in the middle of the text (outcome 2);
   - a prepare error of a trigger body: `INSERT INTO t` after `DROP TABLE log`, where a trigger
     of `t` writes `log`, fails with `no such table: main.log`; after `CREATE TABLE log` the
     same INSERT runs;
   - a constraint failure under ABORT, the default, inside a transaction: the statement's
     changes go back, the transaction stays open, and a later `COMMIT` keeps the earlier writes;
   - `OR FAIL` inside a transaction: the rows before the failing row stay;
   - `OR ROLLBACK` (INSERT and UPDATE) and a column declared `ON CONFLICT ROLLBACK`, inside a
     transaction: the transaction rolls back and closes, a table created in it is gone (the next
     INSERT into it fails at prepare), the next statement runs in autocommit, and `COMMIT`
     fails with `cannot commit - no transaction is active`; outside a transaction it is ABORT;
   - errors in a trigger: `RAISE(ABORT)` (statement rollback, the trigger's writes too),
     `RAISE(FAIL)` (the earlier rows and their trigger writes stay), `RAISE(ROLLBACK)` (the
     transaction closes); a constraint failure of a write in the body; `OR ROLLBACK` in the
     body; and an outer `INSERT OR ROLLBACK`, whose algorithm the body's write takes;
   - transaction control: `BEGIN` inside a transaction fails at step and the transaction stays
     open; `COMMIT` and `ROLLBACK` without a transaction fail at step;
   - failures that change what later statements see: a failed `CREATE UNIQUE INDEX` leaves its
     name free; a failed `ADD COLUMN ... NOT NULL` leaves no column, so a SELECT of it fails at
     prepare, and a later `ADD COLUMN` with a default succeeds; a failed `CREATE TABLE` leaves
     its name free;
   - a run error of a query before its first row (`sum()` overflow) inside a transaction;
   - with foreign keys on (profile `foreign-keys`), an immediate foreign-key failure inside a
     transaction, followed by a write that succeeds and `COMMIT`.
9. **Old corpora keep their meaning.** No claimed corpus changes. For versions 1 to 5 the
   recorder, the native replay (`conformance.corpus.native_replay`), the model case and the
   prediction behave as before.
10. **The specification follows.** ADR 0017's deferred row is removed, and D3 gets a dated
    sentence that the corpus of this task holds the evidence. `docs/native-corpus-format.md`
    (it says that execution stops on its first SQL error) and `docs/conformance-format-v2.md`
    describe version 6.

## Measurement

Over the claimed corpora on 2026-10-23 (`judge/claims.json`; script in the status file): 974 of
7,301 records end with an error, and 55 of them have SQL text after the text that the failed
statement consumed (native version 1: 5, version 4: 36, version 5: 14). A recorder that runs
on by default would change these 55 records, so the mode must be a choice.

## Tests

- **The new authored corpus**, in `CASE_SETS` of `tests/conformance_query_coverage_test.py`: the
  cases of outcome 8, each a version 6 record with a phase on each error, each AGREE in the
  compiled classifier, each with a kernel proof. The test asserts `nativeVersion == 5` today;
  it accepts 6 for this set.
- **The corpus writer**, in `tests/conformance_corpus_writers_test.py`, with the next free
  corpus version (Key points).
- **The judge**: `tests/test_judge_records.py` and `tests/test_judge.py` give a version 6
  record its parameters and compare an output after a failed statement.
- **The recorder**: a version 6 record of a script with a mid-text prepare error has one event
  for each statement; the default mode stops at the first error.
- **The subject without the recorder** (PR A): Lean examples with kernel proofs of the
  continuing pass (an error inside a transaction, `OR ROLLBACK`, a failed `ADD COLUMN`);
  `tests/conformance_predict_test.py` with a hand-written version 6 input; a
  `model_case` test with a hand-written version 6 record.
- **Old corpora**: the predictions of every claimed corpus are byte-identical to those before
  the task (`nix-build integrity/judge.nix -A predictions`, then `diff -r`); the 55 records of
  the measurement replay natively unchanged (`native_replay`).
- **Mutants**, each killed by one authored case, each with a `rule:` guard
  (`conformance/mutant_guards.py`): `Connection.afterError` closes an open transaction after
  every error (the risk: an error treated as `OR ROLLBACK`); it keeps the transaction open
  after an `OR ROLLBACK` failure (the risk: the exception of S2's outcome 2); and the next
  statement resolves against the catalog that the failed statement would have made, as
  `resolve` folds it (the risk that S2's key point "Resolution assumes that earlier statements
  succeed" names).
- **The verdict**: every case of the new corpus agrees; no other count changes.
- The usual checks: `just test-full`, `just verdict`, then `just test-nix` and
  `just test-scheduled` once before the pull requests.

## Key points

- **Where the trace stops today.** `execute` returns after the first event with a code;
  `native_trace.record` (the older fixture path) also stops. `native_replay.model_case`
  refuses a trace with an error before its last event ("Native/frontend statement-count
  mismatch"). `judge/records.py` says that the parameter list "tells the subject how far SQLite
  got". `passFrom` (`VerifierConformance/Pass.lean`) halts, and `classifyCase` and `predict`
  use it after `resolveSchemaAndScript`, which resolves the whole script at once.
- **Version 6 changes few places.** `record_versions.py` holds the sets (`WITH_OUTPUTS`,
  `PROFILED`, `PHASED`); `corpus.py`, `corpus_shards.py`, `record_parser.py`,
  `profile_scope.py`, `execution_profile.py`, `native_replay.py`, `native_replay_report.py`
  and `upstream_fidelity.py` read `PROFILED`. The judge has its own copy of `WITH_OUTPUTS`.
  `authored_evidence.NATIVE_VERSION` is 5, and `corpus.native_replay` must re-record a version
  6 record in the mode that runs on.
- **Old corpora must keep their meaning.** Do not use the continuing run for versions 1 to 5,
  also not cut to the recorded length: it resolves each statement when it runs, so a
  restriction after the first error no longer refuses the case, and verdicts change.
- **`Output` is not enough for the corpus.** `Output.error` keeps only the primary code, and
  `Output` has no column names. The pass needs the transition of each statement for the phase
  (`errorPhase`) and `statementOutput` and `possibleOutput` for the outputs; outcome 6 forbids
  a second copy of `runScriptStep`.
- **The connection of a case.** The run starts idle on the database of the schema and the
  recorded rows, with `foreignKeys` from the profile, and with `some` clock when the record has
  clock values (`none` otherwise, so a statement that reads the clock ends the run).
- **What the model refuses.** A `DEFERRABLE INITIALLY DEFERRED` key is the restriction
  `deferred-foreign-key`, so a `COMMIT` that fails on it is out of the corpus. A query that
  fails after it gave rows is out of the model (`RunEnd.may`). Probe each case natively and
  check that the model describes it before it goes into the corpus.
- **Judge-locked files** (ADR 0011): `judge/*.py`, `judge/*.json`, each claimed corpus,
  `nix/sqlite.nix` and `nix/flake.lock`. The lock does not cover `conformance/native_*.py`;
  the recorder's protection is the owner's review of PR B and the lock of the corpus that it
  wrote.
- **The corpus version.** The pragmas task of ADR 0019, slice 2, records corpus-v50 in the
  workspace `adr19s2`. This task takes v51, the next free number. Check `judge/claims.json` and
  the open stacks again when the corpus is recorded.
- **Files below 200 lines**, docstrings that give the reason, and plain words for each new
  proposition (`AGENTS.md`).
