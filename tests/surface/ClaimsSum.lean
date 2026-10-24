import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT sum(c) FROM t` over every database (ADR 0017,
S4; `Belay/Sqlite/AggregateQuery.lean`). The query fails with `integer overflow` when the sum of the integers leaves the
64-bit range, and otherwise has one row, also for an empty table. Each claim is about every database; each claim has
instances on databases, where `decide +kernel` checks that its two sides agree, so that no claim is vacuous. The
instances include two rows of 4611686018427387904 and a TEXT column, where `sum` reads each text as an integer. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- A table `ledger` with two rows of 4611686018427387904 (2 to the power 62): their sum is 2 to the power 63, which
is more than the largest 64-bit integer. -/
def bigLedger : Database := db! r"
  CREATE TABLE ledger (id INTEGER PRIMARY KEY, cents INTEGER);
  INSERT INTO ledger (id, cents) VALUES (1, 4611686018427387904), (2, 4611686018427387904);"

/-- A table `ledger` with two small rows. -/
def smallLedger : Database := db! r"
  CREATE TABLE ledger (id INTEGER PRIMARY KEY, cents INTEGER);
  INSERT INTO ledger (id, cents) VALUES (1, 10), (2, 20);"

/-- A table `ledger` without a row. -/
def emptyLedger : Database := db! r"
  CREATE TABLE ledger (id INTEGER PRIMARY KEY, cents INTEGER);"

/-- A table `ledger` whose column `cents` is TEXT, with eleven rows `'0999999999999999999'`: `sum` reads each text as the
integer 999999999999999999, and the sum of eleven of them is more than the largest 64-bit integer. -/
def textLedger : Database := db! r"
  CREATE TABLE ledger (id INTEGER PRIMARY KEY, cents TEXT);
  INSERT INTO ledger (id, cents) VALUES (1, '0999999999999999999'), (2, '0999999999999999999'),
    (3, '0999999999999999999'), (4, '0999999999999999999'), (5, '0999999999999999999'), (6, '0999999999999999999'),
    (7, '0999999999999999999'), (8, '0999999999999999999'), (9, '0999999999999999999'), (10, '0999999999999999999'),
    (11, '0999999999999999999');"

/-- The catalog position and table of `ledger` in each database. -/
def bigTable : Nat × CatalogTable := (bigLedger.raw.catalog.findTable (name! "ledger")).get (by decide +kernel)
/-- The catalog position and table of `ledger` in `smallLedger`. -/
def smallTable : Nat × CatalogTable := (smallLedger.raw.catalog.findTable (name! "ledger")).get (by decide +kernel)
/-- The catalog position and table of `ledger` in `emptyLedger`. -/
def emptyTable : Nat × CatalogTable := (emptyLedger.raw.catalog.findTable (name! "ledger")).get (by decide +kernel)
/-- The catalog position and table of `ledger` in `textLedger`. -/
def textLedgerTable : Nat × CatalogTable := (textLedger.raw.catalog.findTable (name! "ledger")).get (by decide +kernel)

example : bigLedger.raw.catalog.findTable (name! "ledger") = some bigTable := by decide +kernel
example : smallLedger.raw.catalog.findTable (name! "ledger") = some smallTable := by decide +kernel
example : emptyLedger.raw.catalog.findTable (name! "ledger") = some emptyTable := by decide +kernel
example : textLedger.raw.catalog.findTable (name! "ledger") = some textLedgerTable := by decide +kernel

/-- Over every database that has a table `ledger` with a column `cents` at position `index`, `SELECT sum(cents) FROM
ledger` fails exactly when the aggregate `sum` of that column fails over the rows of the table in scan order: when an
integer sum leaves the 64-bit range and no REAL value follows. Proof sketch: `Fails.iff_selectAggregate` with the
resolution of the column (`resolveOperand_identifier_table`) and no condition. -/
theorem sum_of_cents_overflows (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "ledger") = some (position, table))
    (column : columnPosition table.columns (name! "cents") = some index) :
    Fails (sql r"SELECT sum(cents) FROM ledger") db ↔
      (Resolved.Aggregate.sum (.column index)).fails (Resolved.EvalContext.bound [])
        (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }) = true := by
  refine Iff.trans (Fails.iff_selectAggregate (head := rfl) (reference := ⟨name! "ledger", none, none⟩) (build := .sum) (name := "sum")
    (resolved := .column index) (condition := none) (aggregate := .sum (.column index)) rfl rfl found
    (resolveOperand_identifier_table column) rfl (.inl ⟨rfl, rfl⟩) rfl (by simp)
    (by simp [Resolved.Output.operands, Resolved.Expr.calm_column])) ?_
  simp [List.filter_eq_self.2 (fun _ _ => rfl)]

/-- Over every database as in `sum_of_cents_overflows`, the query returns a row exactly when the aggregate does not
fail, also for a table without a row (the sum is NULL). -/
theorem sum_of_cents_returns_a_row (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "ledger") = some (position, table))
    (column : columnPosition table.columns (name! "cents") = some index) :
    Holds (sql r"SELECT sum(cents) FROM ledger") db ↔
      (Resolved.Aggregate.sum (.column index)).fails (Resolved.EvalContext.bound [])
        (Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }) = false := by
  refine Iff.trans (Holds.iff_selectAggregate (head := rfl) (reference := ⟨name! "ledger", none, none⟩) (build := .sum) (name := "sum")
    (resolved := .column index) (condition := none) (aggregate := .sum (.column index)) rfl rfl found
    (resolveOperand_identifier_table column) rfl (.inl ⟨rfl, rfl⟩) rfl (by simp)
    (by simp [Resolved.Output.operands, Resolved.Expr.calm_column])) ?_
  simp [List.filter_eq_self.2 (fun _ _ => rfl)]

-- Two rows of 2 to the power 62: the query fails, and both sides agree.
example : Fails (sql r"SELECT sum(cents) FROM ledger") bigLedger :=
  (sum_of_cents_overflows bigLedger bigTable.1 1 bigTable.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

-- Two small rows: the query does not fail, it returns a row.
example : Holds (sql r"SELECT sum(cents) FROM ledger") smallLedger :=
  (sum_of_cents_returns_a_row smallLedger smallTable.1 1 smallTable.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

-- A table without a row: the query returns a row (the sum is NULL).
example : Holds (sql r"SELECT sum(cents) FROM ledger") emptyLedger :=
  (sum_of_cents_returns_a_row emptyLedger emptyTable.1 1 emptyTable.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

-- Eleven texts that read as 999999999999999999: the query fails with `integer overflow`.
example : Fails (sql r"SELECT sum(cents) FROM ledger") textLedger :=
  (sum_of_cents_overflows textLedger textLedgerTable.1 1 textLedgerTable.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

set_option doc.verso true

/-- Over every database with the ledger and cents column, SUM is never empty: a safe sum returns one row and an
overflow fails. Proof sketch: resolve the column and apply {name}`Empty.not_selectAggregate`. -/
theorem sum_of_cents_is_never_empty (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "ledger") = some (position, table))
    (column : columnPosition table.columns (name! "cents") = some index) :
    ¬ Empty (sql r"SELECT sum(cents) FROM ledger") db :=
  Empty.not_selectAggregate (head := rfl) (reference := ⟨name! "ledger", none, none⟩) (build := .sum) (name := "sum")
    (resolved := .column index) (condition := none) (aggregate := .sum (.column index)) rfl rfl found
    (resolveOperand_identifier_table column) rfl (.inl ⟨rfl, rfl⟩) rfl (by simp)
    (by simp [Resolved.Output.operands, Resolved.Expr.calm_column])

example : ¬ Holds (sql r"SELECT sum(cents) FROM ledger") bigLedger := by
  rw [sum_of_cents_returns_a_row bigLedger bigTable.1 1 bigTable.2 (by decide +kernel) (by decide +kernel)]
  decide +kernel
example : ¬ Fails (sql r"SELECT sum(cents) FROM ledger") smallLedger := by
  rw [sum_of_cents_overflows smallLedger smallTable.1 1 smallTable.2 (by decide +kernel) (by decide +kernel)]
  decide +kernel
example : ¬ Empty (sql r"SELECT sum(cents) FROM ledger") smallLedger :=
  sum_of_cents_is_never_empty smallLedger smallTable.1 1 smallTable.2 (by decide +kernel) (by decide +kernel)
example : ¬ Empty (sql r"SELECT sum(cents) FROM ledger") bigLedger :=
  sum_of_cents_is_never_empty bigLedger bigTable.1 1 bigTable.2 (by decide +kernel) (by decide +kernel)
example : ¬ Empty (sql r"SELECT sum(cents) FROM ledger") emptyLedger :=
  sum_of_cents_is_never_empty emptyLedger emptyTable.1 1 emptyTable.2 (by decide +kernel) (by decide +kernel)
