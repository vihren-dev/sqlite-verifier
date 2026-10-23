import Belay

/-! A fixture of `tests/surface_guide_test.py`. It checks the runs of `db.run`,
`Database.Raw.run` and `Run.checked` (`Belay/Sqlite/Run.lean`, `Belay/Sqlite/ProgramRun.lean`, `Belay/Sqlite/RunLaws.lean`), over
the model's `runScriptFrom` (`Belay/Sqlite/Model/ScriptRun.lean`). It also checks the facts of
`Belay/Sqlite/Database.lean` and the display of outputs (`Belay/Sqlite/Model/OutputRepr.lean`).
The examples show these facts:
- A run continues after an error, and the failed statement changes no row.
- Transactions, `OR ROLLBACK` and `PRAGMA foreign_keys` behave as in SQLite.
- Each statement resolves when it runs. A statement that the model does not describe ends the run.
- The row order of queries. The facts of a valid database need no hypothesis.
- When the database at the end is not valid, the run keeps the start database.

The kernel checks each example, and `#guard_msgs` checks each `#eval`. The file fails to
elaborate when an example does not hold. -/

open Belay.Sqlite

/-- The guide's database `shop`: the table `invoices` with two rows, built with `db!`
(`Belay/Sqlite/DbBang.lean`). -/
def shop : Database := db! r"
  CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    customer TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    status TEXT NOT NULL DEFAULT 'open'
  );
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'acme', 10), (2, 'zeta', 0);"

/-- The ids of all invoices, in id order. -/
def ids : Script := sql r"SELECT id FROM invoices ORDER BY id"

/-- The guide's UPDATE that closes the invoices with amount 0. -/
def closeZero : Script := sql r"UPDATE invoices SET status = 'closed' WHERE amount = 0"

-- A failed INSERT gives error 19 (SQLITE_CONSTRAINT), and the next statement runs and sees the
-- rows from before it: a NOT NULL column without a value, then a PRIMARY KEY conflict.
/-- info: [error 19, rows [[1], [2]]] -/
#guard_msgs in
#eval (shop.run (sql r"INSERT INTO invoices (id, amount) VALUES (3, 5)" ++ ids)).outputs
example : (shop.run (sql r"INSERT INTO invoices (id, amount) VALUES (3, 5)" ++ ids)).outputs =
    [.error 19, .rows [[1], [2]]] := by decide +kernel
example : (shop.run (sql r"INSERT INTO invoices (id, customer, amount) VALUES (1, 'bob', 5)" ++ ids)).outputs =
    [.error 19, .rows [[1], [2]]] := by decide +kernel
-- An INSERT of two rows whose second row conflicts writes neither row.
example : (shop.run (sql r"INSERT INTO invoices (id, customer, amount) VALUES (3, 'bob', 5), (1, 'dup', 1)" ++
    ids)).outputs = [.error 19, .rows [[1], [2]]] := by decide +kernel

/-- A transaction with a write that succeeds and a write with a PRIMARY KEY conflict. -/
def failInTransaction : Script := sql r"BEGIN;
  INSERT INTO invoices (id, customer, amount) VALUES (3, 'bob', 5);
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'dup', 1)"

-- An error inside a transaction leaves it open: COMMIT succeeds and keeps the earlier write.
/-- info: [done 0, done 1, error 19, done 0, rows [[1], [2], [3]]] -/
#guard_msgs in
#eval (shop.run (failInTransaction ++ sql r"COMMIT" ++ ids)).outputs
example : (shop.run failInTransaction).transaction = some shop.raw := by decide +kernel
example : (shop.run (failInTransaction ++ sql r"COMMIT")).transaction = none ∧
    (shop.run (failInTransaction ++ sql r"COMMIT")).db.rows "invoices" =
      some ([[1, "acme", 10, "open"], [2, "zeta", 0, "open"], [3, "bob", 5, "open"]] : List (List Value)) := by
  decide +kernel

/-- A transaction with a write that succeeds and an `OR ROLLBACK` write with a PRIMARY KEY
conflict. -/
def rollbackInTransaction : Script := sql r"BEGIN;
  INSERT INTO invoices (id, customer, amount) VALUES (3, 'bob', 5);
  INSERT OR ROLLBACK INTO invoices (id, customer, amount) VALUES (1, 'dup', 1)"

-- `OR ROLLBACK` rolls the transaction back and closes it: the earlier write is gone, and a
-- later COMMIT gives error 1 (no transaction is active).
/-- info: [done 0, done 1, error 19, error 1, rows [[1], [2]]] -/
#guard_msgs in
#eval (shop.run (rollbackInTransaction ++ sql r"COMMIT" ++ ids)).outputs
example : (shop.run (rollbackInTransaction ++ sql r"COMMIT")).outputs = [.done 0, .done 1, .error 19, .error 1] ∧
    (shop.run rollbackInTransaction).transaction = none ∧
    (shop.run rollbackInTransaction).db.rows "invoices" = shop.rows "invoices" := by decide +kernel

/-- `BEGIN` and a write, without the end of the transaction. -/
def openTransaction : Script := sql r"BEGIN; INSERT INTO invoices (id, customer, amount) VALUES (3, 'bob', 5)"

-- `BEGIN` in `p` and `COMMIT` in `q`: `q` runs in the transaction that `p` left open, with the
-- database at `BEGIN` kept. The run of `q` alone on `(db.run p).db` has no transaction to end.
example : (shop.run openTransaction).transaction = some shop.raw := by decide +kernel
example : (shop.run (openTransaction ++ sql r"COMMIT" ++ ids)).outputs =
    [.done 0, .done 1, .done 0, .rows [[1], [2], [3]]] := by decide +kernel
example : ((shop.run openTransaction).db.run (sql r"COMMIT")).outputs = [.error 1] := by decide +kernel
example : ((sql r"COMMIT").runOn (shop.raw.run openTransaction).connection).outputs = [.done 0] ∧
    ((sql r"COMMIT").runOn (shop.raw.run openTransaction).connection).connection.state.snapshot = none := by
  decide +kernel

-- Each statement resolves when it runs: a query of a table that an earlier statement drops
-- gives error 1 (no such table).
/-- info: [done 0, error 1] -/
#guard_msgs in
#eval (shop.run (sql r"DROP TABLE invoices; SELECT id FROM invoices")).outputs
example : (shop.run (sql r"DROP TABLE invoices" ++ ids)).outputs = [.done 0, .error 1] := by decide +kernel

-- `random()` and `CURRENT_TIMESTAMP` give `Output.unmodeled`, and the run ends at it: the
-- statement after it gives no output.
/-- info: [done 1, unmodeled "this function, or this form of it, is not modeled; rewrite the
expression without it"] -/
#guard_msgs (whitespace := normalized) in
#eval (shop.run (closeZero ++ sql r"SELECT random()" ++ ids)).outputs
/-- info: [done 1, unmodeled "the statement reads the clock, which this run does not describe;
write the time as a literal value"] -/
#guard_msgs (whitespace := normalized) in
#eval (shop.run (closeZero ++ sql r"SELECT CURRENT_TIMESTAMP" ++ ids)).outputs
example : (shop.run (closeZero ++ sql r"SELECT random()" ++ ids)).outputs.map Output.endsRun = [false, true] := by
  decide +kernel
example : (shop.run (closeZero ++ sql r"SELECT CURRENT_TIMESTAMP" ++ ids)).outputs =
    [.done 1, .unmodeled Belay.Sqlite.Model.clockUnmodeled] := by decide +kernel

-- A REAL shows as a literal that reads back as the same double.
/-- info: [rows [[1.0e-08, 1.123456789, 0.1, 3.333333333333333148e-01]]] -/
#guard_msgs in
#eval (shop.run (sql r"SELECT 0.00000001, 1.123456789, 0.1, 1.0 / 3")).outputs

-- `LIMIT 1` without `ORDER BY`: SQLite may give either row, so the output is `Output.oneOf`.
-- When every result is the same, the output is `Output.rows`.
/-- info: [oneOf [[["acme"]], [["zeta"]]]] -/
#guard_msgs in
#eval (shop.run (sql r"SELECT customer FROM invoices LIMIT 1")).outputs
example : (shop.run (sql r"SELECT customer FROM invoices LIMIT 1")).outputs = [.oneOf [[["acme"]], [["zeta"]]]] := by
  decide +kernel
example : (shop.run (sql r"SELECT 1 FROM invoices LIMIT 1")).outputs = [.rows [[1]]] := by decide +kernel

/-- The guide's table `customers` of "Row order", without the index. -/
def people : Database := db! r"
  CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, address TEXT, notes TEXT);
  INSERT INTO customers VALUES (1, 'bob', 'x', 'y'), (2, 'ada', 'x', 'y');"

/-- A query without `ORDER BY`: SQLite gives bob, ada without the index and ada, bob with it. -/
def names : Script := sql r"SELECT name FROM customers"

/-- The guide's index on the names. -/
def nameIndex : Script := sql r"CREATE INDEX customers_name ON customers (name)"

-- A query without `ORDER BY` gives its rows in the normal form, so its output is the same
-- before and after the index.
/-- info: [rows [["ada"], ["bob"]], done 0, rows [["ada"], ["bob"]]] -/
#guard_msgs in
#eval (people.run (names ++ nameIndex ++ names)).outputs
example : (people.run (names ++ nameIndex ++ names)).outputs =
    [.rows [["ada"], ["bob"]], .done 0, .rows [["ada"], ["bob"]]] := by decide +kernel

-- The facts of `shop` and of the database after any run need no hypothesis.
example : shop.raw.NotNull := shop.notNull
example : shop.raw.ChecksHold := shop.check
example (s : Script) : (shop.run s).db.raw.NotNull := (shop.run s).db.notNull
example (s : Script) : (shop.run s).db.raw.KeysUnique := (shop.run s).db.unique
example (db : Database) (s : Script) : (db.run s).db.raw.RowidsDistinct := (db.run s).db.rowid_unique
example : (shop.run closeZero).db.raw.ChecksHold := (shop.run closeZero).db.check

/-- The plain database of `shop` with the rows of `invoices` replaced: row 1 holds NULL in the
NOT NULL column `customer`, as a pragma or another program could write it. It is not valid. -/
def broken : Database.Raw :=
  shop.raw.setRows 0
    [{ rowid := 1, values := [1, .null, 10, "open"] }, { rowid := 2, values := [2, "zeta", 0, "open"] }]

/-- A DELETE of the valid row 2, then the ids. -/
def deleteZeta : Script := sql r"DELETE FROM invoices WHERE id = 2" ++ ids

-- `Database.Raw.run` gives the result that the run reached, without the check. The check of
-- `Run.checked` gives no database for it: the outputs end with `Output.unmodeled`, the run
-- keeps the start database, here `shop`, and the value is none.
example : broken.Admitted Profile.pinned ∧ ¬broken.NotNull ∧ ¬broken.Valid Profile.pinned := by decide +kernel
example : (broken.run deleteZeta).outputs = [.done 1, .rows [[1]]] := by decide +kernel
example : (Run.checked shop (SqlRun.ofScript (broken.run deleteZeta))).outputs = [.done 1, .rows [[1]], .unmodeled invalidReason] := by
  decide +kernel
example : (Run.checked shop (SqlRun.ofScript (broken.run deleteZeta))).db.raw = shop.raw ∧
    (Run.checked shop (SqlRun.ofScript (broken.run deleteZeta))).transaction = none ∧
    (Run.checked shop (SqlRun.ofScript (broken.run deleteZeta))).value = none := by decide +kernel
-- The check reads only the database at the end: after a DELETE of the row with the NULL, the
-- database is valid, and the outputs do not end with `Output.unmodeled`.
example : (Run.checked shop (SqlRun.ofScript (broken.run (sql r"DELETE FROM invoices WHERE id = 1" ++ ids)))).outputs =
    [.done 1, .rows [[2]]] := by decide +kernel
-- When the model's run ends with `Output.unmodeled`, the check adds no second one.
example : (Run.checked shop (SqlRun.ofScript (broken.run (sql r"INSERT INTO invoices (id, customer, amount) VALUES (3, 'kay', 5)")))).outputs =
    [.unmodeled Belay.Sqlite.Model.unmodeledHere] := by decide +kernel

/-- A table whose column refers to `invoices`, and a row without its parent. -/
def orphanNote : Script := sql r"CREATE TABLE notes (invoice INTEGER REFERENCES invoices (id));
  INSERT INTO notes VALUES (9)"

-- `PRAGMA foreign_keys = ON` stays on for the next statements and at the end of the run. With
-- foreign keys off, as at the start of a run, SQLite stores the row without its parent.
example : (shop.run (sql r"PRAGMA foreign_keys = ON")).outputs = [.done 0] ∧
    (shop.run (sql r"PRAGMA foreign_keys = ON")).foreignKeys = true := by decide +kernel
example : (shop.run (sql r"PRAGMA foreign_keys = ON" ++ orphanNote)).outputs = [.done 0, .done 0, .error 19] := by
  decide +kernel
example : (shop.run orphanNote).outputs = [.done 0, .done 1] ∧ (shop.run orphanNote).foreignKeys = false := by
  decide +kernel
