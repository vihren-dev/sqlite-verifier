import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT 1 FROM t WHERE p` over
every database (ADR 0017, S4; `Belay/Sqlite/SelectOneFrom.lean`, the expression laws of the model
and the simp set `sql_simp` of `Belay/Sqlite/SqlSimpLaws.lean`). Each claim is about every
database; each claim has an instance on one database, where `decide +kernel` checks that its two
sides agree, so that no claim is vacuous. -/

open Belay.Sqlite
open Belay.Sqlite.Model hiding Database

/-- The guide's first database: table `invoices` with two open invoices, of 10 and of 0. -/
def shop : Database := db! r"
  CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    customer TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    status TEXT NOT NULL DEFAULT 'open'
  );
  INSERT INTO invoices (id, customer, amount) VALUES (1, 'acme', 10), (2, 'zeta', 0);"

/-- The catalog position and the table of `invoices` in `shop`. -/
def invoices : Nat × CatalogTable := (shop.raw.catalog.findTable (name! "invoices")).get (by decide +kernel)

example : shop.raw.catalog.findTable (name! "invoices") = some invoices := by decide +kernel

example : columnPosition invoices.2.columns (name! "amount") = some 2 := by decide +kernel

/-- Over every database that has a table `invoices` with a column `amount` at position `index`,
the query holds exactly when the comparison is true for some row of the table. -/
theorem some_invoice_has_amount_zero (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (column : columnPosition table.columns (name! "amount") = some index) :
    Holds (sql r"SELECT 1 FROM invoices WHERE amount = 0") db ↔
      ∃ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        Resolved.truthy (Comparison.eq.apply
          (Resolved.comparisonOperands (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none)
            (row.getD index .null) 0).1
          (Resolved.comparisonOperands (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none)
            (row.getD index .null) 0).2
          ((table.columns[index]?.map (·.collation)).getD .binary)) = true := by
  have resolves := FilterResolves.of_term (dqs := runContext.profile.dqsDml)
    (scope := tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) (aliases := [])
    (shapes := { later := [] })
    (term := .compare .eq (.identifier (name! "amount") .none) (.numeric "0")) (by simp [namesAlias])
    (by simp [sql_simp, column]; rfl)
  refine Iff.trans (Holds.iff_selectOne (head := rfl) (arguments := rfl) found resolves ?_) ?_
  · simp [sql_simp]
  · simp [sql_simp]; exact Iff.rfl

-- The instance on `shop`: some invoice has amount 0, and both sides agree.
example : Holds (sql r"SELECT 1 FROM invoices WHERE amount = 0") shop :=
  (some_invoice_has_amount_zero shop invoices.1 2 invoices.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

set_option doc.verso true

/-- Over every database with the named table and column, the amount-zero query is empty exactly when its resolved
comparison is false for every source row, and it never fails. Proof sketch: resolve the comparison once and apply
{name}`Empty.iff_selectOne` and {name}`Fails.not_selectOne` with the same calm condition. -/
theorem zero_amount_empty_and_safe (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (column : columnPosition table.columns (name! "amount") = some index) :
    (Empty (sql r"SELECT 1 FROM invoices WHERE amount = 0") db ↔
      ∀ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        Resolved.truthy ((Resolved.Expr.compare .eq
          (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none) (.column index)
          (.literal (.integer 0)) ((table.columns[index]?.map (·.collation)).getD .binary)).eval
            (Resolved.EvalContext.bound []) row) = false) ∧
    ¬ Fails (sql r"SELECT 1 FROM invoices WHERE amount = 0") db := by
  have resolves := FilterResolves.of_term (dqs := runContext.profile.dqsDml)
    (scope := tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) (aliases := [])
    (shapes := { later := [] })
    (term := .compare .eq (.identifier (name! "amount") .none) (.numeric "0")) (by simp [namesAlias])
    (by simp [sql_simp, column]; rfl)
  constructor
  · simpa using Empty.iff_selectOne (head := rfl) (arguments := rfl) found resolves (by simp [sql_simp])
  · exact Fails.not_selectOne (head := rfl) (arguments := rfl) found resolves (by simp [sql_simp])

/-- A table with an amount column and no zero amount, for the negative side of the row-existence claim. -/
def positiveOnly : Database := db! r"CREATE TABLE invoices (amount INTEGER); INSERT INTO invoices VALUES (1);"

/-- The table whose only row makes the amount-zero predicate false. -/
def positiveTable : CatalogTable := (positiveOnly.raw.catalog.findTable (name! "invoices")).get (by decide +kernel) |>.2

example : ¬ Holds (sql r"SELECT 1 FROM invoices WHERE amount = 0") positiveOnly := by
  intro holds
  have impossible := (some_invoice_has_amount_zero positiveOnly 0 0 positiveTable (by decide +kernel)
    (by decide +kernel)).1 holds
  revert impossible
  decide +kernel
example : Empty (sql r"SELECT 1 FROM invoices WHERE amount = 0") positiveOnly :=
  (zero_amount_empty_and_safe positiveOnly 0 0 positiveTable (by decide +kernel) (by decide +kernel)).1.2 (by decide +kernel)
example : ¬ Empty (sql r"SELECT 1 FROM invoices WHERE amount = 0") shop := by
  rw [(zero_amount_empty_and_safe shop invoices.1 2 invoices.2 (by decide +kernel) (by decide +kernel)).1]
  decide +kernel
example : ¬ Fails (sql r"SELECT 1 FROM invoices WHERE amount = 0") shop :=
  (zero_amount_empty_and_safe shop invoices.1 2 invoices.2 (by decide +kernel) (by decide +kernel)).2
example : ¬ Fails (sql r"SELECT 1 FROM invoices WHERE amount = 0") positiveOnly :=
  (zero_amount_empty_and_safe positiveOnly 0 0 positiveTable (by decide +kernel) (by decide +kernel)).2
