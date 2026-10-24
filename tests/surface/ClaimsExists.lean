import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query forms `SELECT 1 WHERE [NOT] EXISTS
(SELECT 1 FROM t WHERE p)` over every database (ADR 0017, S4; `Belay/Sqlite/ExistsQuery.lean`).
Each claim is about every database; each claim has an instance on one database, where
`decide +kernel` checks that its two sides agree, so that no claim is vacuous. -/

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

/-- Over every database that has a table `invoices` with a column `amount` at position `index`,
"no invoice has a negative amount" holds exactly when the comparison is true for no row. -/
theorem no_invoice_is_negative (db : Database) (position index : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (column : columnPosition table.columns (name! "amount") = some index) :
    Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices WHERE amount < 0)") db ↔
      ∀ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] },
        Resolved.truthy (Comparison.lt.apply
          (Resolved.comparisonOperands (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none)
            (row.getD index .null) 0).1
          (Resolved.comparisonOperands (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none)
            (row.getD index .null) 0).2
          ((table.columns[index]?.map (·.collation)).getD .binary)) = false := by
  have resolves := FilterResolves.of_term (dqs := runContext.profile.dqsDml)
    (scope := tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) (aliases := [])
    (shapes := { current := some 0 })
    (term := .compare .lt (.identifier (name! "amount") .none) (.numeric "0")) (by simp [namesAlias])
    (by simp [sql_simp, column]; rfl)
  refine Iff.trans (Holds.iff_selectOne_notExists (head := rfl) (arguments := rfl) found resolves ?_) ?_
  · simp [sql_simp]
  · simp [sql_simp]; exact Iff.rfl

-- The instance on `shop`: no invoice is negative, and both sides agree.
example : Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices WHERE amount < 0)") shop :=
  (no_invoice_is_negative shop invoices.1 2 invoices.2 (by decide +kernel) (by decide +kernel)).2
    (by decide +kernel)

set_option doc.verso true

/-- Over every database with a table of invoices, EXISTS holds exactly when the table has a source row, is empty
exactly when it has none, and never fails. Proof sketch: apply all three EXISTS laws to the absent filter. -/
theorem exists_invoice_observations (db : Database) (position : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table)) :
    (Holds (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") db ↔
      ∃ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }, True) ∧
    (Empty (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") db ↔
      ∀ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }, False) ∧
    ¬ Fails (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") db := by
  have resolves : FilterResolves runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) [] none none { current := some 0 } :=
    .inl ⟨rfl, rfl⟩
  refine ⟨?_, ?_, ?_⟩
  · simpa using Holds.iff_selectOne_exists (head := rfl) (arguments := rfl) found resolves (by simp)
  · simpa using Empty.iff_selectOne_exists (head := rfl) (arguments := rfl) found resolves (by simp)
  · exact Fails.not_selectOne_exists (head := rfl) (arguments := rfl) found resolves (by simp)

/-- Over every database with a table of invoices, NOT EXISTS reverses the row and empty observations of EXISTS,
and never fails. Proof sketch: apply all three NOT EXISTS laws to the absent filter. -/
theorem not_exists_invoice_observations (db : Database) (position : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table)) :
    (Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") db ↔
      ∀ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }, False) ∧
    (Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") db ↔
      ∃ row ∈ Resolved.sourceRows { shape := table, rows := db.raw.rows.getD position [] }, True) ∧
    ¬ Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") db := by
  have resolves : FilterResolves runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) [] none none { current := some 0 } :=
    .inl ⟨rfl, rfl⟩
  refine ⟨?_, ?_, ?_⟩
  · simpa using Holds.iff_selectOne_notExists (head := rfl) (arguments := rfl) found resolves (by simp)
  · simpa using Empty.iff_selectOne_notExists (head := rfl) (arguments := rfl) found resolves (by simp)
  · exact Fails.not_selectOne_notExists (head := rfl) (arguments := rfl) found resolves (by simp)

/-- An existing table without invoices distinguishes an empty result from a missing-table error. -/
def noInvoices : Database := db! r"CREATE TABLE invoices (amount INTEGER);"

/-- The existing empty table of invoices. -/
def emptyInvoices : CatalogTable := (noInvoices.raw.catalog.findTable (name! "invoices")).get (by decide +kernel) |>.2

example : Holds (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") shop :=
  (exists_invoice_observations shop invoices.1 invoices.2 (by decide +kernel)).1.2 (by decide +kernel)
example : ¬ Holds (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") noInvoices := by
  rw [(exists_invoice_observations noInvoices 0 emptyInvoices (by decide +kernel)).1]
  decide +kernel
example : Empty (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") noInvoices :=
  (exists_invoice_observations noInvoices 0 emptyInvoices (by decide +kernel)).2.1.2 (by decide +kernel)
example : ¬ Empty (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") shop := by
  rw [(exists_invoice_observations shop invoices.1 invoices.2 (by decide +kernel)).2.1]
  decide +kernel
example : ¬ Fails (sql r"SELECT 1 WHERE EXISTS (SELECT 1 FROM invoices)") shop :=
  (exists_invoice_observations shop invoices.1 invoices.2 (by decide +kernel)).2.2
example : Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") noInvoices :=
  (not_exists_invoice_observations noInvoices 0 emptyInvoices (by decide +kernel)).1.2 (by decide +kernel)
example : ¬ Holds (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") shop := by
  rw [(not_exists_invoice_observations shop invoices.1 invoices.2 (by decide +kernel)).1]
  decide +kernel
example : Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") shop :=
  (not_exists_invoice_observations shop invoices.1 invoices.2 (by decide +kernel)).2.1.2 (by decide +kernel)
example : ¬ Empty (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") noInvoices := by
  rw [(not_exists_invoice_observations noInvoices 0 emptyInvoices (by decide +kernel)).2.1]
  decide +kernel
example : ¬ Fails (sql r"SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM invoices)") noInvoices :=
  (not_exists_invoice_observations noInvoices 0 emptyInvoices (by decide +kernel)).2.2
