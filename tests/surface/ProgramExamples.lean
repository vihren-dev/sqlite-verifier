import Belay

/-! A fixture of `tests/surface_programs_test.py`: the runs of programs (`Belay/Sqlite/Program.lean`,
`Belay/Sqlite/ProgramQueries.lean`, `Belay/Sqlite/ProgramRun.lean`, `Belay/Sqlite/ProgramLaws.lean`)
and of a clock (`Belay/Sqlite/Env.lean`). The kernel checks each example:
- `query` and `single` on each output kind: rows, one row of one column, several rows, no row,
  `done`, `error` and `oneOf`.
- A statement that reads the clock ends a program without a clock: the rest does not run, and
  the value is none. A program's value can depend on an earlier output.
- The run of `send s` is the model's run of `s`, and `p.run db = db.run p`.
- `CURRENT_TIMESTAMP`, `date('now')` and a DEFAULT of `CURRENT_TIMESTAMP` under `clockAt` give
  SQLite's text, and `Output.unmodeled` under `Env.default`.
- The laws of runs apply to programs and scripts. -/

open Belay.Sqlite

/-- Table `t` with the rows 1 and 2, table `n` without rows, and table `stamps` whose column `at`
has the DEFAULT `CURRENT_TIMESTAMP`. -/
def two : Database := db! r"
  CREATE TABLE t (a INTEGER NOT NULL);
  INSERT INTO t VALUES (1), (2);
  CREATE TABLE n (a);
  CREATE TABLE stamps (id INTEGER PRIMARY KEY, at TEXT DEFAULT CURRENT_TIMESTAMP);"

/-- The value of {lit}`query` and of {lit}`single` on {lit}`two` for the script. -/
def readBoth (script : Script) (one : script.statements.length = 1 := by decide) :
    Option (Except Nat (List (List Value)) × Option Value) :=
  (two.run do return (← query script one, ← single script one)).value

-- Rows, one row of one column, several rows, several columns and no row.
example : readBoth (sql r"SELECT a FROM t ORDER BY a") = some (.ok [[1], [2]], none) := by decide +kernel
example : readBoth (sql r"SELECT max(a) FROM t") = some (.ok [[2]], some 2) := by decide +kernel
example : readBoth (sql r"SELECT 1, 2") = some (.ok [[1, 2]], none) := by decide +kernel
example : readBoth (sql r"SELECT a FROM n") = some (.ok [], none) := by decide +kernel
-- `done`: a statement without rows. An INSERT with RETURNING gives its rows.
example : readBoth (sql r"DELETE FROM n") = some (.ok [], none) := by decide +kernel
example : readBoth (sql r"INSERT INTO n VALUES (7) RETURNING a") = some (.ok [[7]], some 7) := by decide +kernel
-- `error`: the error code; `single` gives none.
example : readBoth (sql r"SELECT a FROM missing") = some (.error 1, none) := by decide +kernel
-- `oneOf`: the first result in the order of `compareResults`.
example : (two.run (sql r"SELECT a FROM t LIMIT 1")).outputs = [.oneOf [[[1]], [[2]]]] := by decide +kernel
example : readBoth (sql r"SELECT a FROM t LIMIT 1") = some (.ok [[1]], some 1) := by decide +kernel

/-- Read `date('now')`, then insert a row. Without a clock, the first statement ends the
program: the INSERT after it does not run, and the value is none. -/
def readsClockFirst : Sql Bool := do
  let stamp ← single (sql r"SELECT date('now')")
  let outputs ← send (sql r"INSERT INTO n VALUES (1)")
  pure (stamp.isSome && outputs.allOk)

example : (two.run readsClockFirst).outputs = [.unmodeled clockUnmodeled] ∧
    (two.run readsClockFirst).value = none ∧ (two.run readsClockFirst).db.rows "n" = some [] := by decide +kernel

/-- Send an INSERT only when `t` has two rows: the program depends on an earlier output. -/
def insertWhenTwo : Sql (List Output) := do
  match ← single (sql r"SELECT count(*) FROM t") with
  | some 2 => send (sql r"INSERT INTO t VALUES (3)")
  | _ => pure []

example : (two.run insertWhenTwo).value = some [.done 1] ∧ (two.run insertWhenTwo).db.rows "t" = some [[1], [2], [3]] ∧
    ((two.run insertWhenTwo).db.run insertWhenTwo).value = some [] := by decide +kernel

/-- Two INSERTs, of which the second fails, then `BEGIN` and a query. The run of `send s` is the
model's run of `s`: the same outputs, database and connection. -/
def failsSecond : Script := sql r"INSERT INTO t VALUES (3); INSERT INTO t VALUES (NULL); BEGIN; SELECT a FROM t ORDER BY a"

example : (two.run (send failsSecond)).outputs = (two.raw.run failsSecond).outputs ∧
    (two.run (send failsSecond)).outputs = [.done 1, .error 19, .done 0, .rows [[1], [2], [3]]] ∧
    (two.run (send failsSecond)).db.raw = (two.raw.run failsSecond).connection.state.database ∧
    (two.run (send failsSecond)).transaction = (two.raw.run failsSecond).connection.state.snapshot ∧
    (two.run (send failsSecond)).value = some (two.raw.run failsSecond).outputs := by decide +kernel
example (s : Script) : two.run s = Run.checked two (SqlRun.ofScript (two.raw.run s)) := Database.run_script_default two s
example (p : Sql Bool) : p.run two = two.run p := rfl
example (s : Script) (env : Env) : two.run s env = (send s).run two env := rfl

-- The clock: each statement that reads it gets SQLite's text of the time of `clockAt`.
example : clockAt "2026-10-20 12:00:00" = Env.atTime 212659257600000 := rfl
example : (two.run (env := clockAt "2026-10-20 12:00:00")
      (sql r"SELECT CURRENT_TIMESTAMP, date('now'); INSERT INTO stamps (id) VALUES (1); SELECT at FROM stamps")).outputs =
    [.rows [[("2026-10-20 12:00:00" : String), ("2026-10-20" : String)]], .done 1, .rows [[("2026-10-20 12:00:00" : String)]]] := by
  decide +kernel
-- The same script under `Env.default` ends at its first statement.
example : (two.run (sql r"SELECT CURRENT_TIMESTAMP, date('now'); INSERT INTO stamps (id) VALUES (1)")).outputs =
    [.unmodeled clockUnmodeled] := by decide +kernel
example : (two.run (sql r"INSERT INTO stamps (id) VALUES (1)")).outputs = [.unmodeled clockUnmodeled] := by decide +kernel

-- The laws of runs: `Script.run_env` for a script without clock reads, `Sql.run_env` for a
-- program, and the S2 laws over the new `Run`.
example (env : Env) : two.run (sql r"SELECT a FROM t ORDER BY a") env = two.run (sql r"SELECT a FROM t ORDER BY a") :=
  Script.run_env _ two env (by decide +kernel)
example (env : Env) : insertWhenTwo.run two env = insertWhenTwo.run two := Sql.run_env _ two env (by decide +kernel)
example (p q : Script) : two.raw.run (p ++ q) = (two.raw.run p).andThen (q.runOn ·) := Database.Raw.run_append two.raw p q
example (q : Script) : (two.run (sql r"DELETE FROM n" ++ q)).outputs =
    (two.run (sql r"DELETE FROM n")).outputs ++ ((two.run (sql r"DELETE FROM n")).db.run q).outputs :=
  Script.run_append two _ q (by decide +kernel) (by decide +kernel) (by decide +kernel)
example : (failsSecond.runUntilError two).outputs = [.done 1, .error 19] := by decide +kernel
