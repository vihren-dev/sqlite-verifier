# belay

The surface: the library that Lean developers import, `Belay`, with the SQLite surface under
`Belay.Sqlite` (ADR 0016). It imports the model only through its roots, `Belay.Sqlite.Model`,
`Belay.Sqlite.Model.Codec` and `Belay.Sqlite.Model.Codec.Resolution` (the terms of statement
syntax that `sql r"..."` gives), and reads SQL text with the text package below it,
`packages/belay-sqlite-text`.

The text package calls the SQLite parser library while a file elaborates, so the modules of
both packages are precompiled and linked with the library. Lake reads the library's folder from
the environment variable `BELAY_PARSER_LIBRARY`:

```sh
nix-build build-support/default.nix -A parserLibrary.library --out-link build/parser-library
BELAY_PARSER_LIBRARY=$PWD/build/parser-library lake build Belay Belay:shared
```

Lake loads the precompiled modules for `lake build`, `lake lean FILE` and the editor's server.
`lake env lean FILE` does not load them, and `lean` then stops at the first parser call.

## Programs and runs

A script is SQL text as data: `sql r"..."` gives a `Script`. A program can use the output of a
statement to choose what it sends next. `Sql α` is the type of programs that give a value of type
`α`, and it is a monad:

```lean
def closeAndCount : Sql (Option Value) := do
  sql r"UPDATE invoices SET status = 'closed' WHERE amount = 0"
  single (sql r"SELECT count(*) FROM invoices WHERE status = 'open'")
```

- `Sql.pure v` sends no statement. `Sql.exec statement values rest` sends one statement and
  gives its output to `rest`. All other programs are built from these two.
- `send s : Sql (List Output)` sends each statement of `s`; the value is their outputs.
- `query s : Sql (Except Nat (List (List Value)))` sends a script of exactly one statement; the
  value is its rows, or its error code. For an output `oneOf`, it gives the first result.
- `single s : Sql (Option Value)` sends a script of exactly one statement; the value is the only
  value of a result with one row of one column, and `none` otherwise.
- A script on its own line in a `do` block is sent, and its value is dropped.
- `outputs.allOk` tells whether no output is an error or `Output.unmodeled`.

`db.run p` runs a program or a script on a database, and `p.run db` (`Sql.run`) is the same run
of a program. A script runs as the program `send s`. The result is a `Run α`:

- `value : Option α`: the program's value, or `none` when a statement gives `Output.unmodeled`
  (the rest of the program does not run) or when the database at the end is not valid;
- `outputs`: one output for each statement that ran;
- `db` and `start`: the databases at the end and at the start; `db` is `start` when the
  database at the end is not valid;
- `transaction`, `foreignKeys` and `recursiveTriggers`: the state of the connection at the end.

The last argument of a run is the environment, `env := e`, with `Env.default` when it is not
given. `Env.default` has no clock: a statement that reads the clock, such as
`CURRENT_TIMESTAMP`, gives `Output.unmodeled`. `clockAt "2026-10-20 12:00:00"` gives that time,
in UTC, to every statement; Lean checks the text where it is written. `Env.atTime` takes the time
in Julian-day milliseconds, and `{ clock := some f }` gives the time `f i` to statement `i`.

```lean
example : (start.run (env := clockAt "2026-10-20 12:00:00") do
    single (sql r"SELECT date('now')")).value = some (some (("2026-10-20" : String) : Value)) := by
  decide +kernel
```

A connection also has three counters: the value of `changes()`, `total_changes()` and
`last_insert_rowid()`. The environment gives them at the start of the run. `Env.default` knows
none of them: a statement that calls a counter function before a write of the run has set that
counter gives `Output.unmodeled`. `Env.newConnection` gives 0 to each counter, as a new SQLite
connection does. A write sets the counters that it changes, so the next statement can read them.
The fields are independent: `{ Env.newConnection with clock := some f }` has both.

```lean
example : (start.run (env := Env.newConnection) do
    single (sql r"SELECT changes()")).value = some (some (0 : Value)) := by
  decide +kernel
```

`Script.run_env` states that a run in which no statement reads the clock and no statement ends at
a counter that the run does not know is the same in every environment.

## Claims about every database

`Holds q db` says that every possible result of the query has a row. `Empty q db` says that
all its possible results have no rows. `Fails q db` says that the query gives an error.
An unmodeled query satisfies none of these claims. Use the query-form lemmas, such as
`Holds.iff_selectOne_count`, to express a claim in terms of the catalog and stored rows.
A free database cannot be evaluated with `decide`; supply its schema facts and use the laws.

The `sql_simp` simp set resolves and evaluates common expressions, including parameters,
comparisons, Boolean operators, `BETWEEN`, `COLLATE`, `count(*)` and `sum`. For example,
`simp [sql_simp]` turns a resolved `count(*)` into the length of its group. The aggregate
equations also have `grind` attributes. For a conditional law, use
`simp (disch := assumption) [sql_simp]` when its hypotheses are already available.

For integer and NULL inputs, `sumOf_fails_iff` describes overflow by the first integer
prefix sum outside the 64-bit range. Later integer cancellation does not clear that overflow.
When every prefix fits, `sumOf_value_of_fits` gives NULL for no integer inputs and the exact
integer sum otherwise. These laws require integer or NULL inputs; text and REAL inputs use
the general aggregate equations and SQLite's conversion rules.

`Holds.iff_step`, `Empty.iff_step` and `Fails.iff_step` expose every resolution branch for
any query. `Fails.of_prepareError` covers a missing table or column, and
`Fails.select_body_prepareError` lifts an expression-resolution error without repeating the
statement interpreter. `Script.not_claims_query_of_undescribed` covers a query that may fail
or has an unsupported subquery. Keep those cases in proofs: a row satisfying a filter does
not imply `Holds` if another row can make evaluation fail.

For a scalar call without `FROM`, `resolveStatement_selectNoFrom_columns` admits a resolved
scalar column, including a fallible function. `Holds.iff_noFrom_scalar`,
`Empty.iff_noFrom_scalar` and `Fails.iff_noFrom_scalar` retain the run's fault and the filter.
Thus `SELECT abs(1)` holds, `SELECT abs(-9223372036854775808)` fails, and adding `WHERE 0`
skips that failing projection and makes the result empty, for every database.
