import Belay

/-! A fixture of `tests/surface_guide_test.py`: the examples of the user guide's sections
"A first example", "Scripts" and "Row order" that run a script (`Belay/Sqlite/Run.lean`,
`Belay/Sqlite/RunLaws.lean`, `Belay/Sqlite/Database.lean`, `Belay/Sqlite/SqlBang.lean`,
`Belay/Sqlite/DbBang.lean`, and the display of outputs in `Belay/Sqlite/Model/OutputRepr.lean`).
The guide writes `decide`; here each proof about a run is `decide +kernel`. The guide's `#sql`
example of "A first example" is not in this file. The file fails to elaborate when an example
does not hold. -/

open Belay.Sqlite

/-- The guide's first database: table `invoices` with two open invoices, of 10 and of 0. -/
def shop : Database := db! r"
  CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    customer TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    status TEXT NOT NULL DEFAULT 'open'
  );
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'acme', 10), (2, 'zeta', 0);"

/-- The script of `shop`'s text. -/
def shopScript : Script := sql r"
  CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    customer TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    status TEXT NOT NULL DEFAULT 'open'
  );
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'acme', 10), (2, 'zeta', 0);"

-- "A first example": `db!` gives the database that the run of its text gives on the empty
-- database, and its proof of validity uses no axiom beyond Lean's standard ones.
example : shop.raw = (Database.Raw.run {} shopScript).connection.state.database := by decide +kernel

/-- info: 'shop' depends on axioms: [propext, Classical.choice, Quot.sound] -/
#guard_msgs in
#print axioms shop

-- "Scripts": `sql! shop r"..."` checks the text against `shop` and gives the script of `sql r"..."`.
example : (sql! shop r"SELECT id FROM invoices") = sql r"SELECT id FROM invoices" := rfl

/-- Close the invoices with the amount 0. -/
def closeZero : Script := sql r"UPDATE invoices SET status = 'closed' WHERE amount = 0"

/-- The open invoices, by id. -/
def openInvoices : Script := sql r"SELECT id, amount FROM invoices WHERE status = 'open' ORDER BY id"

-- "A first example": the UPDATE changes one row, then the query gives the open invoice.
/-- info: [done 1, rows [[1, 10]]] -/
#guard_msgs in
#eval (shop.run (closeZero ++ openInvoices)).outputs

example : (shop.run (closeZero ++ openInvoices)).outputs = [.done 1, .rows [[1, 10]]] := by
  decide +kernel

-- "Scripts": `Script.run_append` for `shop`. `closeZero` ends outside a transaction, leaves
-- foreign keys and recursive triggers off, and has no `Output.unmodeled`, so `openInvoices` runs on its database.
example : (shop.run (closeZero ++ openInvoices)).outputs =
    (shop.run closeZero).outputs ++ ((shop.run closeZero).db.run openInvoices).outputs :=
  Script.run_append shop closeZero openInvoices (by decide +kernel) (by decide +kernel)
    (by decide +kernel) (by decide +kernel)

/-- An INSERT that succeeds, an INSERT that fails on the PRIMARY KEY, and a query. -/
def failsSecond : Script := sql r"
  INSERT INTO invoices (id, customer, amount) VALUES (3, 'kay', 5);
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'dup', 1);
  SELECT id FROM invoices ORDER BY id"

-- "Scripts": a statement that fails gives `Output.error`, and the next statement runs.
/-- info: [done 1, error 19, rows [[1], [2], [3]]] -/
#guard_msgs in
#eval (shop.run failsSecond).outputs

-- `Script.runUntilError` stops at the first error, as `sqlite3_exec` does: the outputs end
-- with the error, and the query after it does not run.
/-- info: [done 1, error 19] -/
#guard_msgs in
#eval (failsSecond.runUntilError shop).outputs

example : (failsSecond.runUntilError shop).outputs = [.done 1, .error 19] := by
  decide +kernel

/-- A query of the missing table `customers`, then a query of `invoices`. -/
def missingTable : Script := sql r"SELECT id FROM customers; SELECT id FROM invoices ORDER BY id"

-- "Scripts": a statement that names a missing table gives `Output.error 1`, and the next
-- statement runs.
/-- info: [error 1, rows [[1], [2]]] -/
#guard_msgs in
#eval (shop.run missingTable).outputs

example : (shop.run missingTable).outputs = [.error 1, .rows [[1], [2]]] := by
  decide +kernel

/-- The database of the guide's example of row order, without the index. -/
def unindexed : Database := db! r"
  CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, address TEXT, notes TEXT);
  INSERT INTO customers VALUES (1, 'bob', 'x', 'y'), (2, 'ada', 'x', 'y');"

/-- The database of the example, with the index. -/
def indexed : Database := db! r"
  CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, address TEXT, notes TEXT);
  INSERT INTO customers VALUES (1, 'bob', 'x', 'y'), (2, 'ada', 'x', 'y');
  CREATE INDEX customers_name ON customers (name);"

-- The index of `indexed` exists: a second index of the same name fails with error 1.
example : (indexed.run (sql r"CREATE INDEX customers_name ON customers (name)")).outputs = [.error 1] := by
  decide +kernel

-- "Row order": a query without `ORDER BY` gives its rows in the normal form, sorted by
-- `Value.compare`, with the index and without it.
/-- SQLite returns the rows ada and bob, in some order. -/
example : (indexed.run (sql r"SELECT name FROM customers")).outputs
    = [.rows [["ada"], ["bob"]]] := by
  decide +kernel

example : (unindexed.run (sql r"SELECT name FROM customers")).outputs
    = [.rows [["ada"], ["bob"]]] := by
  decide +kernel

-- "Row order": `LIMIT 1` without `ORDER BY` gives one entry for each result that SQLite may
-- give; when every result is the same, the output is a plain `Output.rows`.
/-- SQLite returns one row, ada or bob. -/
example : (indexed.run (sql r"SELECT name FROM customers LIMIT 1")).outputs
    = [.oneOf [[["ada"]], [["bob"]]]] := by
  decide +kernel

/-- info: [oneOf [[["ada"]], [["bob"]]]] -/
#guard_msgs in
#eval (indexed.run (sql r"SELECT name FROM customers LIMIT 1")).outputs

example : (indexed.run (sql r"SELECT 1 FROM customers LIMIT 1")).outputs = [.rows [[1]]] := by
  decide +kernel

/-- Three customers with the same name, `ada`, with the notes `m`, `z` and `a` in rowid order,
and the customer `bob`. The `Value.compare` order of the notes is neither the rowid order nor its
reverse. -/
def namesakes : Database := db! r"
  CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, address TEXT, notes TEXT);
  INSERT INTO customers VALUES (1, 'ada', 'x', 'm'), (2, 'ada', 'x', 'z'), (3, 'ada', 'x', 'a'),
    (4, 'bob', 'x', 'y');"

-- "Row order": the rows come in the order of `ORDER BY`; the three rows that `ORDER BY name`
-- does not separate are sorted by `Value.compare` among themselves, not in rowid order.
/-- info: [rows [["ada", "a"], ["ada", "m"], ["ada", "z"], ["bob", "y"]]] -/
#guard_msgs in
#eval (namesakes.run (sql r"SELECT name, notes FROM customers ORDER BY name")).outputs

example : (namesakes.run (sql r"SELECT name, notes FROM customers ORDER BY name")).outputs
    = [.rows [["ada", "a"], ["ada", "m"], ["ada", "z"], ["bob", "y"]]] := by
  decide +kernel
