# ADR 0024: Connection state and random values

Date: 2026-10-23. Status: ACCEPTED (2026-10-23).
Implementation: two slices (D6), each with its own task file, as local commits, after the owner
accepts this ADR.
Audience: designers and reviewers.
Related: [ADR 0017](adr-0017-user-surface.md) ("Deferred, with their triggers": the row that this
ADR picks up; S3 gave `Env` its clock), [ADR 0012](adr-0012-query-semantics.md) (amendment 5:
the clock, owner decisions 2 and 8), [ADR 0013](adr-0013-model-structure.md) (D6: the clock is an
evaluation parameter), [ADR 0018](adr-0018-surface-sql.md) (D4 and D5: foreign keys and triggers;
D6: the results that SQLite may give), [ADR 0011](adr-0011-product-trust-and-development-integrity.md)
(the judge).

## Overview

The target user guide lists the inputs of a run in "The execution environment". Two rows of
that table are not in the model: random values (`random()`, `randomblob(n)`) and the connection
state (`changes()`, `last_insert_rowid()`). `total_changes()` reads the same state. The model
resolves all five functions as the restriction `unmodeled-function`.

This ADR gives the five functions a meaning in the model. As in ADRs 0012 to 0019, the model
follows SQLite 3.51.0 exactly, and it refuses with a restriction each form that it cannot
describe exactly. The one exception is random values (D4, owner decision 2). The two
groups are different:

- **The connection functions are deterministic.** Their values follow from the statements that
  ran on the connection. The model keeps them as state of the connection, and the corpora can
  check them.
- **Random values are not deterministic.** The model describes them as it describes the clock:
  the run takes a source of values, and a claim holds for every source. The sources give more
  runs than SQLite's generator can, so this description is sound but not exact. Native SQLite cannot
  check them, because the recorder refuses them.

## Context

Measured on this tree on 2026-10-23, after ADR 0017's S3 and ADR 0019's slice 3. The facts about
SQLite come from the dev shell's `sqlite3` 3.51.0, one statement per line, and from the sources
of the pinned release (`src/func.c`, `src/insert.c`, `src/vdbe.c`, `src/vdbeaux.c`).

What the code has today:

- **Resolution.** The catalog of built-in functions gives the five functions their numbers of
  arguments (`builtinFunction?`, `Resolution/FunctionCatalog.lean`): none, and one for
  `randomblob`. `scalarCall` (`Resolution/FunctionCalls.lean`) has no form for them, so each
  call is the restriction `unmodeled-function`. A run ends at such a statement with the
  restriction's reason (`ScriptRunExamples.lean`, the example of `random()`).
- **The connection.** `SqlState` (`SqlState.lean`) holds the database, the snapshot of an open
  transaction and the clock assignment. `Connection` (`ScriptRun.lean`) adds the setting of
  `PRAGMA foreign_keys`. Neither holds a count of changes or a rowid. The effect of a statement
  is a database (`Effect`, `Execution.lean`).
- **Change counts.** `statementOutput` (`StatementOutput.lean`) computes the number of changes
  of a statement again from the statement and the database before it, for `Output.done`
  (`Output.ofStep`), apart from the step (`runStatement`, `StatementStep.lean`). A write with
  trigger programs or foreign-key checks runs row by row (`KeyState`, `ForeignKeyPhases.lean`).
  Its state keeps the rows that the statement wrote, but no count of the rows that trigger
  programs and foreign-key actions write.
- **Rowids.** A new row gets the value of its rowid alias, or one more than the largest rowid
  (`LiteralData.newRowid`, `nextRowid`). SQLite's random rowid after the largest rowid is not
  described.
- **The clock is the design to follow.** Evaluation reads the statement's clock value from its
  context (`EvalContext.clock`, `ExprFault.lean`). `Resolved.Statement.readsClock` tells which
  statements read it. The execution relation relates a script to the outcome of every clock
  assignment (`ProfileExecutes`, `SqlExecution.lean`; ADR 0012, owner decision 8). The run of a
  script takes `Option Clock`, and a statement that reads the clock ends a run without a clock
  (`statementClock`, `clockUnmodeled`). The surface's `Env` holds the clock (`Env.lean`), and
  `Script.run_env` gives the run under every `Env` when the run under `Env.default` does not
  end at a clock read.
- **Schema positions.** For a time keyword, resolution gives SQLite's errors
  `non-deterministic functions prohibited in generated columns`, `... in index expressions` and
  `... in partial index WHERE clauses` (`Resolved.Expr.isNow` in `GeneratedColumns.lean` and
  `IndexTerms.lean`).
- **The recorder.** Its authorizer refuses each statement that calls `random` or `randomblob`
  (`conformance/native_acquisition.py`), so no corpus case calls them. The extraction of corpus
  v5 excluded 79 upstream instances for `random` and 21 for `randomblob`; that of v4 excluded 10
  for `randomblob`. The authorizer does not refuse the three connection functions. The recorder
  records `sqlite3_changes` after each INSERT, UPDATE and DELETE
  (`conformance/native_statements.py`). It runs the setup and the migration of a case on one
  connection (`conformance/native_record.py`), so at the start of the migration the connection
  holds the counts and the rowid that the setup left.
- **The corpora.** A lexical scan of the migrations finds `changes()` in 3 cases of v4 and 5
  cases of v5. No migration of a corpus calls the other four functions.
- **The guide.** No example of the guide calls one of the five functions. They are only in the
  table of "The execution environment". Two open questions of the guide name the connection
  state: question 2 (is `≈` a congruence when a later statement can read hidden state?) and
  question 3 (is `last_insert_rowid()` an output of each statement?).

Facts checked on native SQLite 3.51.0. A new connection gives 0 for each of the three counters.
The counters after each statement:

| Statement | `changes()` after it | `total_changes()` after it | `last_insert_rowid()` after it |
| --- | --- | --- | --- |
| INSERT, UPDATE or DELETE that succeeds | the rows that the statement itself inserted, updated or deleted; an UPDATE that sets a value to itself counts the row, and the DO UPDATE of an upsert counts its row; the rows that REPLACE deleted, that IGNORE or DO NOTHING skipped, and that trigger programs or foreign-key actions wrote do not count | the value before, plus the changes of the statement, of each statement of its trigger programs and of its foreign-key actions | the rowid of the last row that the statement inserted into a rowid table, also with REPLACE; DO UPDATE, a `WITHOUT ROWID` table and a row that IGNORE skips do not change it |
| INSERT, UPDATE or DELETE that fails with ABORT or ROLLBACK, for a constraint or another error such as `datatype mismatch` | 0 | the value before, plus the changes of the statements of its trigger programs and of its foreign-key actions that ended before the failure, but not the statement's own rows; the rollback does not take them back | the rowid of the last row that the statement inserted before the failure; the rollback does not take it back |
| INSERT, UPDATE or DELETE that fails with FAIL | the rows that it kept | the value before, plus those rows and the changes of the trigger programs and foreign-key actions that ended before the failure | as for success, over the kept rows |
| `DROP TABLE` of a table that a foreign key references, with foreign keys on, that succeeds | the rows of the table, which SQLite deletes first without the table's own triggers | the value before, plus those rows, the rows of the foreign-key actions and the changes of the trigger programs that the actions run | unchanged |
| Such a `DROP TABLE` that fails with `FOREIGN KEY constraint failed` | 0 | the value before, plus the rows of the foreign-key actions and the changes of the statements of the trigger programs that they run, but not the table's own rows; the rollback does not take them back | unchanged |
| Every other statement: a query (also one that fails), `CREATE`, `ALTER TABLE ... ADD COLUMN`, another `DROP`, `BEGIN`, `COMMIT`, `ROLLBACK`, `PRAGMA`, and a statement that fails to prepare | unchanged | unchanged | unchanged |

For example, `INSERT INTO t(v) VALUES (10), (1)` with a UNIQUE `v` that holds 1 inserts rowid 4,
fails at the second row, and leaves `changes()` 0 and `last_insert_rowid()` 4. A failed INSERT
whose BEFORE INSERT trigger wrote two rows adds 2 to `total_changes()`, although the rollback
removes the rows. `DELETE FROM p WHERE id = 1`, whose foreign-key actions delete two rows and
update one, gives `changes()` 1 and adds 4 to `total_changes()`. An `UPDATE p SET id = id + 10, ...`
with `ON UPDATE CASCADE` that updates the first row, whose action updates two child rows, and
then fails with a UNIQUE constraint at the second row adds 2 to `total_changes()`. An
`INSERT OR FAIL` of two rows whose AFTER INSERT trigger inserts two rows, and whose second row
fails, gives `changes()` 1 and adds 3 to `total_changes()`. `DROP TABLE p` with foreign keys on,
where one table references `p` with `ON DELETE CASCADE` from two rows and another table
references `p` without an action, fails, gives `changes()` 0 and adds 2 to `total_changes()`.

The values that a statement reads while it runs:

- **`changes()`** in every expression of a statement is the value from before the statement,
  also when its trigger programs write. In an UPDATE of three rows with an AFTER UPDATE trigger
  that inserts two rows, `SET v = changes()` gives each row the same value.
- **`total_changes()`** is the value from before the statement while no trigger program has
  written. In the UPDATE above, `SET w = total_changes()` gives the three rows 4, 6 and 8.
- **`last_insert_rowid()`** in UPDATE and DELETE is the value from before the statement, also
  when their trigger programs insert. An INSERT changes it while it runs: after an INSERT of
  rowid 5, `INSERT INTO t(id, v) VALUES (30, last_insert_rowid()), (31, last_insert_rowid()),
  (32, last_insert_rowid())` stores 5, 30 and 31. When the table has a trigger, or when the
  `SELECT` of the INSERT reads the table, SQLite computes every row before it inserts the
  first (`useTempTable`, `insert.c`), so every row reads the value from before the statement.
  `RETURNING last_insert_rowid()` gives the rowid of each returned row.
- **Inside a trigger program**, SQLite keeps `changes()` and `last_insert_rowid()` at the start
  of the program and restores them at its end (`OP_Program` in `vdbe.c`, the frame restore in
  `vdbeaux.c`); the statements of the program set them as other statements do. In an AFTER
  INSERT program, `last_insert_rowid()` is the new row's rowid at the start.
- **Schema positions.** `DEFAULT` and `CHECK` accept the five functions, and a `DEFAULT` of
  `changes()` reads the value at each INSERT. Generated columns, index expressions and partial
  index filters refuse each of the five with the three errors above.

Random values:

- **`random()`** (`randomFunc`, `func.c`) takes eight bytes from SQLite's generator and turns a
  negative value `r` into `-(r & 0x7fffffffffffffff)`. So it gives an INTEGER from
  -9223372036854775807 to 9223372036854775807, and never -9223372036854775808 (from the source;
  a probe cannot show the absence of one value).
- **`randomblob(N)`** takes the integer of its argument, as `sqlite3_value_int64` gives it, and
  gives a BLOB of N bytes, or of 1 byte when N is less than 1. `randomblob(0)`, `randomblob(-3)`,
  `randomblob(NULL)`, `randomblob('x')` and `randomblob(x'0102')` have length 1,
  `randomblob('3')` length 3 and `randomblob(2.9)` length 2. `randomblob(1000000000)` works, and
  `randomblob(1000000001)` fails with `string or blob too big` (code 18).
- **One evaluation, one value.** `SELECT random() = random()` gave 0. SQLite evaluates a call
  once for an `ORDER BY` or `GROUP BY` term that is a result column: `INSERT INTO s SELECT
  random() AS r FROM t ORDER BY r` and `... ORDER BY random()` over 200 rows stored the values
  in order, and `SELECT random() % 3 AS r ... GROUP BY r` gave a different `r` to each group. It
  evaluates the call again for an alias in `WHERE`: of `SELECT random() AS r FROM t WHERE r > 0`
  over 200 rows, 44 result rows had `r <= 0`.
- **The pager uses the same generator.** On a database file, with `.testctrl prng_seed 7`, an
  INSERT between two `SELECT random()` changes the second value, and a SELECT between them does
  not.

## Decision

### D1. The counters are state of the connection

`SqlState` gets SQLite's three counters: the changes of the last statement that set them
(`db->nChange`), the total (`db->nTotalChange`) and the last inserted rowid (`db->lastRowid`).
Each counter is known or unknown. The table of facts is the rule for each statement form that
the model describes, also for the statements of trigger programs and for foreign-key actions.

- **One computation.** The step of a statement gives its counts with its effect, in the same
  computation, as `runStatement` gives the effect and the support check. `Output.done` reads the
  same count, and the second computation in `statementOutput` goes (no compatibility path). The
  row engine counts the rows that trigger programs and foreign-key actions write, including
  those of statements that end before a failure.
- **Unknown, not guessed.** When the model does not know a counter, it becomes unknown. For
  example, the model checks a plain INSERT of several rows once for all rows (`checkedWrite`),
  so after its failure it does not know the last row before the failing row; then
  `last_insert_rowid()` becomes unknown, unless the task file shows that the model finds that
  row. An unknown counter does not stop a run; only a read of it does (D2).
- **ROLLBACK, BEGIN and COMMIT** do not change the counters, as in SQLite.

### D2. Reads of the counters

- The three functions resolve to expression forms that read the counters from the statement's
  evaluation context, as the time keywords read the clock. The context holds the values from
  before the statement.
- The model describes a read where SQLite gives the value from before the statement:
  `changes()` in each expression of a statement; `total_changes()` in a query, and in a write
  that runs no trigger program and no foreign-key action; `last_insert_rowid()` in a query, an
  UPDATE and a DELETE.
- Model restrictions (R7), each with a reason: `last_insert_rowid()` in an INSERT or an upsert,
  whose value changes with each row in the order of `insert.c`; `total_changes()` in a write
  that runs trigger programs or foreign-key actions; and each of the three in a trigger
  program, a `DEFAULT` and a `CHECK` constraint.
- A read of an unknown counter gives `Output.unmodeled` with a reason, and the run ends at it,
  as a clock read in a run without a clock.
- SQLite's errors for the five functions in a generated column, an index expression and a
  partial index filter are SQLite rules (R7). Resolution gives them, as it does for the time
  keywords.

### D3. The counters at the start of a run

The counters at the start of a run come from the run's environment. `Env.default` leaves the
three counters unknown, so a run under it describes a connection with any history (owner
decision 1). A statement sets each counter, and after that a read is described: under
`Env.default`, `INSERT ...; SELECT last_insert_rowid()` gives the inserted rowid. An environment
for a new connection gives 0 to the three counters, as SQLite does. `runSqlFrom` takes the
counters in its `SqlState`. `Script.run_env` keeps its form: if the run under `Env.default` does
not end at a read of an input that `Env.default` does not give (the clock, a random value or an
unknown counter), the run is the same under every environment.

### D4. Random values: a source that a claim quantifies over

- **The source.** The run takes an optional source of random bytes, as it takes an optional
  clock, and `Env` gets the source. `Env.default` has none, so a statement that calls `random()`
  or `randomblob()` gives `Output.unmodeled` with a reason, and the run ends at it.
- **The values.** Under a source, each evaluation of a call takes its bytes from the source,
  by the statement's index and a key of the evaluation: the call's position in the statement
  and the row for which the model evaluates it. `random()` converts eight bytes as
  `randomFunc` does. `randomblob(N)` takes N bytes, or 1 when N is less than 1, with N from the
  model's integer conversion of a value. A size above the model's limit for a computed blob is
  not described, as for `zeroblob` above `zeroblobLimit` (4,096 bytes, `Functions/Scalar.lean`).
- **The claims.** The execution relation relates a script to the outcome of every clock
  assignment and every source, so a claim holds for every source. A law says that a statement
  that calls neither function runs the same under every source, as `runSqlAt_of_readsClock`
  says for the clock. Under one source, equal values in an `ORDER BY` term are a tie, and the
  results that SQLite may give for it are those of ADR 0018 D6.
- **Sound, and larger than SQLite.** SQLite's generator gives some sequences of bytes, and the
  source can give any sequence, so a claim for every source holds for each run of SQLite. The
  model gives a separate key to each evaluation of SQLite whose value reaches the result, and
  one key where SQLite uses one evaluation twice, so it never makes two values equal that SQLite
  draws apart, or the reverse. But the model's runs are more than SQLite's: the generator
  (ChaCha20 in `random.c`) has a finite state, so it cannot give every long sequence of bytes,
  and a source can give values that no run of SQLite gives. This is an approximation, against
  the rule of ADRs 0012 to 0019 that the model is exact. Its cost: a claim that holds only
  because of the generator's limits cannot be proved, and a counterexample under a source can
  be one that SQLite cannot give. An exact model needs the generator's states and SQLite's
  order of draws, which the first alternative rejects. Owner decision 2 accepts or refuses the
  approximation.
- **The positions of slice 2.** The model describes a call only where the task file shows from
  SQLite's code how often SQLite evaluates it: the result columns and `ORDER BY` terms of a
  query over one table or no table, also an `ORDER BY` term that SQLite matches with a result
  column; the cells of `INSERT ... VALUES`; the values of `UPDATE ... SET`; and `RETURNING`.
  Every other position is a model restriction with a reason: `WHERE`, `GROUP BY`, `HAVING`, the
  arguments of aggregates, joins, subqueries, trigger programs, upsert clauses, `DEFAULT` and
  `CHECK`.

### D5. Evidence

- **The connection functions.** An authored corpus with a case for each row of the table of
  facts and each read of D2, with mutants for the rules that are easy to get wrong: the rows
  that REPLACE deletes counted, the rows of trigger programs counted in `changes()`, the rows of
  trigger programs and foreign-key actions left out of `total_changes()`, and `DROP TABLE` of a
  referenced table that does not set `changes()`. The mutants for failed statements
  (`changes()` kept, `last_insert_rowid()` taken back by the rollback, the auxiliary changes
  before the failure left out of `total_changes()`) need the next item. A corpus run starts with unknown counters, so
  a case that reads a counter before its migration sets it is out of scope, without a judge
  change. The judge change that claims the new cases is its own pull request (ADR 0011).
- **After a failed statement.** The recorder stops at the first error
  (`conformance/native_statements.py`), so no case can read the counters after a failed
  statement. The rows of the table for failed statements get native evidence only with the
  recorder change of ADR 0017's first deferred row (the statements after an error). Until then
  they have Lean examples, with the probes recorded in the task file, and the mutants for them
  wait for that change.
- **The start of a case.** `total_changes()` is never known in a corpus run that starts with
  unknown counters. Owner decision 3 chooses whether the recorder also records the three
  counters at the start of the migration, in a new corpus, so that the case run starts from
  them.
- **Random values.** The recorder refuses them, so no native case checks them (owner decision
  4). Their evidence is kernel-checked Lean examples and laws: the law of D4 for statements
  without calls, `typeof(random())` and the range of `random()` for every source, and the
  length of `randomblob(N)` for each kind of argument above, with the facts of `func.c` and
  the probes recorded in the task file.

### D6. Slices

| Slice | Content | Needs | Needed by |
| --- | --- | --- | --- |
| 1 | D1 to D3, and D5 for the connection functions: the counters, their reads, the errors of the five functions in schema positions, and the counters of `Env` | the row engine of ADR 0018 D4 and D5, which counts the rows of trigger programs and foreign-key actions; owner decisions 1 and 3 | ADR 0017 S6, whose `≈` must account for state that a later statement reads (guide open question 2); the 8 corpus cases that call `changes()` |
| 2 | D4, and D5 for random values | slice 1's resolved forms of the five functions; owner decisions 2 and 4 | no slice of ADR 0017 today; a guide example or a measurement that needs random values |

Each slice works as in ADR 0015: an authored corpus with kernel proofs where SQLite can check
it, mutants for the rules that are easy to get wrong, the verdict of every corpus, and
`just test-full` at the slice's end.

## Consequences

- **The run carries more state.** `SqlState` and `Connection` hold the
  counters, so the laws of runs (`runScriptFrom_agrees`, the append and index laws,
  `Script.run_append`) carry them. The run of `p ++ q` starts `q` with the counters that `p`
  left, which the connection already gives.
- **Equivalence sees the counters.** A later statement can read them, so two scripts that give
  the same database but different counters are not interchangeable. S6 decides how `≈` compares
  them (guide open question 2).
- **Claims over random values are proofs.** `decide` cannot check a claim for every source.
  Under `Env.default`, `Holds`, `Empty` and `Fails` of a query that calls `random()` do not hold,
  because its output is `Output.unmodeled`, as for a clock read today.
- **Counterexamples that use random values** (S5) cannot replay in `sqlite3` as they are,
  because `sqlite3` does not take the values of the source. S5 decides how to show them.
- **Predictions change in slice 1** for the cases that call `changes()`, and the five functions
  in schema positions become SQLite's errors instead of a restriction. A judge change claims
  the cases that agree.

## Alternatives considered

**Model SQLite's generator with a controlled seed.** It would make random values deterministic
and recordable. Rejected: the pager draws from the same generator, so a write between two calls
changes the second value (the probe above); the model would need the pager's draws, SQLite's
order of evaluation, which depends on the plan, and the ChaCha20 generator of `random.c`.

**List every random value with `Output.oneOf`.** Rejected: `random()` has 2^64 - 1 values, and
the values also reach the database through INSERT and UPDATE, where no output lists them.

**A seeded Lean generator in `Env` as the meaning of random values.** It gives one `#eval`
result. Rejected as the semantics, because a claim must hold for every value that SQLite may
give. A helper of that kind can come over the source when a guide example needs it, because
the source stays the primitive.

**The counters as an input for each statement, as the clock.** Rejected: the counters follow
from the statements that ran, so an input would allow runs that SQLite cannot give, such as
`changes()` 5 after an INSERT of one row.

**Counters that are always 0 at the start of a run.** It is simpler for `#eval`, but a claim
then covers only a run on a new connection, and an application seldom has one. It is option B
of owner decision 1.

## Not decided here

- The counters inside trigger programs, `last_insert_rowid()` in an INSERT, and
  `total_changes()` in a write with trigger programs: a later slice, with SQLite's save and
  restore of `OP_Program` and the rule of `useTempTable`, when a measurement or an example needs
  them.
- Random values in the positions that D4 refuses.
- SQLite's random rowid after the largest rowid, which the source could describe.
- Whether `last_insert_rowid()` is an output of each statement (guide open question 3): the
  counter of D1 is the primitive, and an output can be built over it.
- SQLite's `string or blob too big` for `randomblob(N)` above 1,000,000,000: the task file of
  slice 2 decides it with the blob limit.

## Owner decisions

On 2026-10-23, the owner accepted the recommendation (A) of each decision. The text of each
decision stays as it was proposed:

1. **The counters at the start of a run (D3).**
   - A (recommended): unknown under `Env.default`; an environment can give them, and one for a
     new connection gives 0. A claim covers a connection with any history, and
     `Script.run_env` keeps its form.
   - B: always 0, as on a new connection. Simpler for `#eval`, but a claim covers only a new
     connection.
   - C: given by the environment, 0 by default. A claim under `Env.default` then covers only a
     new connection.
2. **Random values (D4).**
   - A (recommended): a source in `Env`, none by default, over which a claim quantifies, in the
     positions of slice 2. The model's runs are more than SQLite's (D4): every claim that the
     model proves holds for SQLite, but a counterexample can use values that SQLite's generator
     cannot give.
   - B: they stay a restriction, and the guide says that the model does not describe them.
   - C: SQLite's generator with a controlled seed (see "Alternatives considered").
3. **The counters at the start of a corpus case (D5).**
   - A (recommended): a judge change in slice 1, with its own pull request: the recorder records
     the three counters of the connection at the start of the migration, in a new corpus, and
     the case run starts from them. Then `total_changes()` after a successful statement and
     the reads before the migration sets a counter get native evidence; the rule of
     `total_changes()` for trigger programs and foreign-key actions is easy to get wrong. Its
     rule after a failure still needs the recorder change for the statements after an error.
   - B: no recorder change. `total_changes()` has Lean examples only, and the reads before the
     migration sets a counter stay out of scope.
4. **Native evidence for random values (D5).**
   - A (recommended): none from the corpora; kernel examples and laws, from `func.c`. No guide
     example and no corpus case needs random values today.
   - B: a judge change: a recorder mode that runs a case under two seeds
     (`SQLITE_TESTCTRL_PRNG_SEED`) and records it only when the outputs are the same, so that
     cases such as `typeof(random())` and `length(randomblob(N))` become evidence.
5. **The order of the slices (D6).**
   - A (recommended): slice 1 before ADR 0017's S6; slice 2 when a guide example or a
     measurement needs random values.
   - B: both slices before S4.
   - C: both slices wait until a guide example uses the functions, the trigger of ADR 0017's
     deferred row.
