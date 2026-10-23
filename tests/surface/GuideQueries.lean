import Belay

/-! A fixture of `tests/surface_guide_test.py`: the examples of the user guide's section
"Queries as propositions" over one database (`Belay/Sqlite/Queries.lean`,
`Belay/Sqlite/QueryLaws.lean`, the model's `Model/QueryOutputs.lean`). The guide writes `decide`; here each proof is `decide +kernel`.
The file fails to elaborate when an example does not hold, or when a message is not the
expected one. -/

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

-- The guide's example: some invoice has amount 0.
example : Holds (sql r"SELECT 1 FROM invoices WHERE amount = 0") shop := by decide +kernel

-- No invoice has a negative amount: the query runs and gives no row.
example : Empty (sql r"SELECT 1 FROM invoices WHERE amount < 0") shop := by decide +kernel

-- A query of a missing table fails, so it does not hold.
example : Fails (sql r"SELECT 1 FROM payments") shop := by decide +kernel

example : ¬ Holds (sql r"SELECT 1 FROM payments") shop := by decide +kernel

-- A query that gives no row does not hold, and `¬ Holds` follows from `Empty`.
example : ¬ Holds (sql r"SELECT 1 FROM invoices WHERE amount < 0") shop :=
  fun holds => holds.not_empty (by decide +kernel)

-- `LIMIT 1` without `ORDER BY`: each result that SQLite may give has a row, so the query holds.
example : Holds (sql r"SELECT id FROM invoices LIMIT 1") shop := by decide +kernel

-- `EXCEPT` compares the rows of two queries: each invoice of amount 0 is open, and some invoice
-- does not have amount 0.
example : Empty (sql r"SELECT id FROM invoices WHERE amount = 0 EXCEPT SELECT id FROM invoices WHERE status = 'open'")
    shop := by decide +kernel

example : ¬ Empty (sql r"SELECT id FROM invoices EXCEPT SELECT id FROM invoices WHERE amount = 0") shop := by
  decide +kernel

-- A query whose output the model does not describe, here one that reads the clock: none of the
-- three holds.
example : ¬ Holds (sql r"SELECT CURRENT_TIMESTAMP") shop ∧ ¬ Empty (sql r"SELECT CURRENT_TIMESTAMP") shop ∧
    ¬ Fails (sql r"SELECT CURRENT_TIMESTAMP") shop := by decide +kernel

-- The query of the foreign-key setting only reads.
example : Holds (sql r"PRAGMA foreign_keys") shop := by decide +kernel

-- A script that is not one read-only statement is an elaboration error at the term. Lean adds
-- the first message for an argument whose tactic fails.
/--
@ +1:18...23
error: could not synthesize default value for parameter '_query' using tactics
---
@ +1:18...23
error: the script must be one read-only statement: a SELECT, or PRAGMA foreign_keys without a value; remove the other statements, or use Database.run
-/
#guard_msgs (positions := true) in
example : Prop := Holds (sql r"SELECT 1; SELECT 2") shop

/--
@ +1:18...23
error: could not synthesize default value for parameter '_query' using tactics
---
@ +1:18...23
error: the script must be one read-only statement: a SELECT, or PRAGMA foreign_keys without a value; remove the other statements, or use Database.run
-/
#guard_msgs (positions := true) in
example : Prop := Empty (sql r"DELETE FROM invoices") shop
