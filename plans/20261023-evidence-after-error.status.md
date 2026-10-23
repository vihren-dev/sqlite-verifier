# Status: evidence for the statements after an error

Created 2026-10-23. Status: OPEN (PR A in progress).
Task file: [20261023-evidence-after-error.task.md](20261023-evidence-after-error.task.md).
Specification: [ADR 0017](../docs/adr-0017-user-surface.md) ("Deferred, with their triggers",
first row; D3 and its amendment of 2026-10-22);
[ADR 0011](../docs/adr-0011-product-trust-and-development-integrity.md) (the judge and its lock).

## Relevant files

- The model's run: `packages/belay-sqlite-model/Belay/Sqlite/Model/ScriptRun.lean`
  (`Connection`, `Connection.afterError`, `runScriptStep`, `runScriptFrom`),
  `ScriptRunLaws.lean`, `ScriptRunStates.lean`, `StatementOutput.lean`, `PossibleOutput.lean`.
- The conformance runner: `packages/verifier-conformance/VerifierConformance/Pass.lean`
  (`passFrom`), `Case.lean` (`errorPhase`, `classifyCase`, `checkCase`), `Predict.lean`.
- The recorder: `conformance/native_statements.py` (`execute`), `native_record.py`
  (`record_sql`), `native_library.py`, `native_connection.py` (`SQL_ERRORS`),
  `record_versions.py`, `native_replay.py` (`model_case`), `corpus.py` (`native_replay`),
  `authored_evidence.py`, `predict.py`.
- The judge: `judge/records.py` (`WITH_OUTPUTS`, `subject_input`), `judge/compare.py`.
- Tests: `tests/conformance_query_coverage_test.py` (`CASE_SETS`),
  `tests/conformance_corpus_writers_test.py`, `tests/test_judge_records.py`,
  `tests/test_judge.py`, `tests/conformance_predict_test.py`.
- Formats: `docs/native-corpus-format.md`, `docs/conformance-format-v2.md`.

## Native probes (SQLite 3.51.0, 2026-10-23)

Probe scripts ran the native library through `conformance.native_connection`; the logs are in
`build/agent-logs/errev-probe1.log` to `errev-probe5.log` of the workspace `errev`. Results:

- The prepare tail ends at the failed token for syntax errors, and in the middle of the text
  for these resolution errors: `CREATE TABLE t(a, a, b)` (duplicate column), `CREATE TABLE`
  of a table that exists, `CREATE TRIGGER r AFTER INSERT ON nosuch BEGIN ...` (the tail then
  runs the body's statements, and `END;` fails as a statement). `no such table`, `no such
  column`, a wrong count of values, `ADD COLUMN` of a duplicate, `DROP` of a missing object and
  `CREATE INDEX` on a missing column consume the text up to the `;`.
- `sqlite3_complete` is false for `CREATE TABLE t(a, a,` and for a trigger without `END`, and
  true when `END;` follows. `native_library.py` does not bind it yet.
- ABORT inside a transaction: statement rollback, the transaction stays open, `COMMIT` keeps
  the earlier writes. `OR FAIL` keeps the earlier rows; `sqlite3_changes` is their count, and 0
  after an ABORT failure.
- `OR ROLLBACK` (INSERT, UPDATE, `UNIQUE ON CONFLICT ROLLBACK`) inside a transaction: the
  transaction rolls back and closes; a table created in it is gone (`no such table` at
  prepare); `COMMIT` fails at step, code 1, `cannot commit - no transaction is active`. Outside
  a transaction it acts as ABORT.
- `BEGIN` inside a transaction, and `COMMIT` or `ROLLBACK` without one, fail at step.
- `RAISE(ABORT)` rolls back the statement and its trigger writes; `RAISE(FAIL)` keeps the
  earlier rows; `RAISE(ROLLBACK)` inside a transaction closes it (code 1811). `OR ROLLBACK` in a
  trigger body rolls back the transaction; an outer `OR ROLLBACK` replaces the body's default.
  A constraint failure in the body (2067) rolls back the statement.
- A STRICT mismatch (3091) and a `sum()` overflow inside a transaction keep it open.
- A failed `CREATE UNIQUE INDEX` and a failed `CREATE TABLE t(a, a)` leave the name free. After
  a failed `ADD COLUMN b NOT NULL`, `SELECT b` fails at prepare, and `ADD COLUMN b DEFAULT 2`
  succeeds.
- A trigger body that writes a dropped table makes the outer INSERT fail at prepare
  (`no such table: main.log`); after `CREATE TABLE log` it runs.
- An immediate foreign-key failure (787) inside a transaction keeps it open. A deferred key
  that fails at `COMMIT` keeps the transaction open, but the model refuses deferred keys
  (`deferred-foreign-key`). `PRAGMA foreign_keys = OFF` inside a transaction changes nothing.
- `json()` that fails on a later row gives the earlier rows first; the model does not describe
  such a query (it gives `RunEnd.may`).

## Measurement of the claimed corpora (2026-10-23)

Log: `build/agent-logs/errev-count.log`. Run with `PYTHONPATH=.` in the repository:

```python
import json
from collections import Counter
from pathlib import Path
from conformance.corpus import load
claims = json.loads(Path("judge/claims.json").read_text())["corpora"]
total = stopped = early = 0; versions = Counter()
for name, entry in sorted(claims.items()):
    for r in load(Path(entry["path"]))[1]:
        total += 1; trace = r["trace"]
        if trace and trace[-1].get("primaryCode"):
            stopped += 1
            used = sum(len(e["sql"].encode()) for e in trace)
            rest = r["migrationSql"].encode()[used:].decode(errors="replace")
            if rest.strip().strip(";").strip():
                early += 1; versions[r.get("nativeVersion")] += 1
print(total, stopped, early, dict(versions))
```

Result: 7,301 records; 974 end with an error; 55 have text after the failed statement
(version 1: 5, version 4: 36, version 5: 14).

## Size estimate

About 600 to 800 changed lines without the corpus data: the continuing pass with its theorem
and examples (about 250 lines of Lean), the classifier and the prediction (about 100), the
recorder mode and `sqlite3_complete` (about 100), the authored definitions and the writer
(about 150), tests and mutants (about 150), and the documents. A model fault that the new
corpus finds is extra work and is not in this estimate.

## Progress log

- 2026-10-23: research, native probes and measurement; task file and this status file.
- 2026-10-23: `just review` of the task and status files (change `qrlwyxux`): no findings.
- 2026-10-23 (PR A): the model's step is made of `runScriptStepWith` and `ranScriptStep`, and `resolveSchema` resolves a schema alone, so a conformance pass can take the same step.
- 2026-10-23 (PR A, refactor): review of `rwlmrrzx`: the docstring of `runScriptStepWith` names no conformance runner (R6), and the status file cites no local result (R19).
- 2026-10-23 (PR A): the conformance pass that continues (`runPassFrom`, with `runPassFrom_results`), the classifier of a case that continues (`Classify.lean`), the prediction of a version 6 input, and the readers of version 6 (`record_versions.CONTINUING`, `native_replay.model_case`, `predict.py`).
- 2026-10-23 (PR A): a mutant copy builds `VerifierConformance.Classify`, which its classifier program imports (`resolve_mutants.verdicts`); the earlier commit built only `VerifierConformance.Case`. The predictions of the claimed corpora are byte-identical to those before the task (`diff -r`).
- 2026-10-23 (PR A, refactor): `runPassFrom_results` moves to `RunPassLaws.lean`, so that the import closure of `VerifierConformance.Classify`, which each mutant copy builds, does not contain this proof; the docstring of `resolve_mutants` names that module (review of `yksqxkqo`).
- 2026-10-23 (PR A, refactor): the module docstring of `RunPassLaws` and the status line say only that the classifier does not import this proof (review of `llzrutmv`).
- 2026-10-23 (PR A): `tests/conformance_continuing_case_test.py` runs in the Nix suite `harness`, with `tests/conformance_predict_test.py`, whose helper it imports.

## Tests for each commit

- Task and status files: none (documents only); `just review`.
- The model's step: `just dev-build`.
- The pass, the classifier, the prediction and the readers: `just dev-build`, `just dev-verdict`, `just documentation-inventory`; `tests/conformance_continuing_case_test.py`, `tests/conformance_predict_test.py`, `tests/conformance_phase_test.py`, `tests/conformance_mutation_test.py`, `tests/conformance_model_test.py`, `tests/conformance_generation_test.py`, `tests/failed_catalog_observation_test.py`, `tests/test_model_package.py -m unit`, `tests/test_native_replay_storage.py`, `tests/conformance_trace_test.py`.

## Remaining

- PR B: outcomes 1 to 4, 8 and 10, the mutants and corpus-v51.

## Owner decisions

On 2026-10-23, the owner accepted the recommendation of both decisions: option A of decision 1
(the recorder's mode goes in the judge pull request) and option A of decision 2 (native record
version 6).

1. **Where the recorder change goes.**
   - Option A (recommended): PR A (the work, first) has the model, the conformance runner, the
     prediction and the readers of version 6, tested with Lean examples and hand-written
     version 6 inputs. PR B (the judge, on top) has the recorder's mode, the authored
     definitions and writer, their tests and mutants, `judge/records.py`, corpus-v51, its claim
     and the lock. This agrees with ADR 0017's row ("the oracle/recorder and a new corpus" are
     the judge change), and the owner reviews the oracle change. Cost: a model fault that the
     recorded corpus finds needs a fix in PR A below the recorder commits.
   - Option B: as in the earlier slices, the recorder, the definitions and their tests go in
     PR A; PR B has only `judge/records.py`, the corpus, the claim and the lock. Cost: the
     oracle change gets no owner approval, and ADR 0017's row needs an amendment.
2. **Version 6 or a flag.** Option A (recommended): a new native record version 6, so each
   record says how it was recorded and the readers stay simple. Option B: a record field
   (for example `continuesAfterError`) on version 5. Cost of B: each reader of version 5 must
   check the field, and `judge/records.py` must read it too.
