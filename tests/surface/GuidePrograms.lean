import Belay

/-! A fixture of `tests/surface_programs_test.py`: the examples of the user guide's sections
"Programs", "Running a program" and "The execution environment" (`Belay/Sqlite/Program.lean`,
`Belay/Sqlite/ProgramQueries.lean`, `Belay/Sqlite/ProgramRun.lean`, `Belay/Sqlite/Env.lean`,
`Belay/Sqlite/ValueDisplay.lean`), as the guide writes them. The guide writes `decide`; here each
proof about a run is `decide +kernel`. The file fails to elaborate when an example does not hold,
or when a message is not the expected one. -/

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

/-- The starting database of the guide's complete file: customers, and their sessions. -/
def start : Database := db! r"
  CREATE TABLE customers (
    id    INTEGER PRIMARY KEY,
    name  TEXT,
    email TEXT NOT NULL
  );
  CREATE TABLE sessions (
    id          INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    expires_at  INTEGER NOT NULL
  );
  INSERT INTO customers VALUES (1, 'ada', 'Ada@X'), (2, 'bob', 'bob@y');
  INSERT INTO sessions VALUES (10, 1, 100), (11, 1, 9999999999), (12, 2, 100);"

/-- Close the invoices with the amount 0. -/
def closeZero : Script := sql r"UPDATE invoices SET status = 'closed' WHERE amount = 0"

-- "Programs".
/-- Add a customer with the next free id. The value tells whether the INSERT succeeded. -/
def addCustomer (name email : String) : Sql Bool := do
  let some next ← single (sql r"SELECT coalesce(max(id), 0) + 1 FROM customers")
    | pure false
  let outputs ← send
    (sql r"INSERT INTO customers (id, name, email) VALUES ($next, $name, $email)")
  pure outputs.allOk

/-- Close the invoices with the amount 0, then count the open invoices. A script on its own
line in a `do` block is sent, and its value is dropped. -/
def closeAndCount : Sql (Option Value) := do
  closeZero
  single (sql r"SELECT count(*) FROM invoices WHERE status = 'open'")

example : (shop.run closeAndCount).value = some (some 1) := by decide +kernel
example : (shop.run closeAndCount).outputs = [.done 1, .rows [[1]]] := by decide +kernel

-- "Running a program".
/-- Add a customer, count the customers, delete that customer and count again. -/
def demo : Run (Option Value × Option Value) := start.run do
  sql r"INSERT INTO customers (id, name, email) VALUES (3, 'eve', 'eve@z')"
  let before ← single (sql r"SELECT count(*) FROM customers")
  sql r"DELETE FROM customers WHERE name = 'eve'"
  let after ← single (sql r"SELECT count(*) FROM customers")
  pure (before, after)

/-- info: some (some 3, some 2) -/
#guard_msgs in
#eval demo.value

example : (start.run (addCustomer "eve" "eve@z")).value = some true := by decide +kernel

/-- Count the customers, then add one on the database that the count left. Lean code in `IO`
runs programs one after another. The fixture elaborates `main`; it does not run it. -/
def main : IO Unit := do
  let run := start.run (single (sql r"SELECT count(*) FROM customers"))
  IO.println s!"customers: {run.value}"
  let run := run.db.run (addCustomer "eve" "eve@z")
  IO.println s!"added: {run.value}"

-- `db.run p` and `p.run db` are the same run.
example : start.run (addCustomer "eve" "eve@z") = (addCustomer "eve" "eve@z").run start := rfl

-- "The execution environment".
/-- Read `CURRENT_TIMESTAMP` under `clockAt`: `run` takes the environment as a named argument. -/
def stamped : Run (Option Value) := start.run (env := clockAt "2026-10-20 12:00:00") do
  single (sql r"SELECT CURRENT_TIMESTAMP")

example : stamped.value = some (some (("2026-10-20 12:00:00" : String) : Value)) := by decide +kernel

-- Under `Env.default`, a statement that reads the clock gives `Output.unmodeled`.
example : (start.run (single (sql r"SELECT CURRENT_TIMESTAMP"))).outputs = [.unmodeled clockUnmodeled] ∧
    (start.run (single (sql r"SELECT CURRENT_TIMESTAMP"))).value = none := by decide +kernel

-- For a script that does not read the clock, `Script.run_env` gives the same run in every
-- environment.
example (env : Env) : start.run (sql r"SELECT count(*) FROM customers") env =
    start.run (sql r"SELECT count(*) FROM customers") :=
  Script.run_env _ start env (by decide +kernel) (by decide +kernel)

-- A new connection knows each counter as 0; `Env.default` knows none, so a read ends the run.
example : (start.run (env := Env.newConnection) do
    single (sql r"SELECT changes()")).value = some (some (0 : Value)) := by
  decide +kernel
example : (start.run (single (sql r"SELECT changes()"))).outputs =
    [.unmodeled (counterUnknownReason .changes)] := by decide +kernel
