import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT 1 WHERE $x IN (SELECT e FROM t
[WHERE p])` over every database (ADR 0017, S4; `Belay/Sqlite/ColumnQuery.lean`). Each claim is
about every database; each claim has an instance on one database, where `decide +kernel` checks that
its two sides agree, so that no claim is vacuous. -/

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

/-- The guide's "`x` is the id of an invoice", over every database that has a table `invoices` with a column `id`
at position `col`: the query holds exactly when some stored row has a value in that column that is equal to
`x` under the comparison that `IN` uses (the affinity of the column, and its collation). Proof sketch: the
script resolves with the lemmas and `sql_simp` (the column `id` resolves to the cell `col` of the table, the main
condition to an `IN` of a parameter with the affinity and the collation of that column); `Holds.iff_selectOne_column`
turns the claim into the truth of `IN` over the values of the column, `Resolved.truthy_inValue_eq_true` turns that into
a statement about one candidate, and the membership of a row in the scan order is the membership in the stored rows
(`Table.scanRows_perm`). -/
theorem x_is_an_invoice_id (db : Database) (x : Int64) (position col : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (column : columnPosition table.columns (name! "id") = some col) :
    Holds (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") db ↔
      ∃ row ∈ db.raw.rows.getD position [],
        (Resolved.comparisonOperands (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
          (.integer x.toInt) (row.values.getD col .null)).2.isNull = false ∧
        ((table.columns[col]?.map CatalogColumn.collation).getD Collation.binary).compare
          (Resolved.comparisonOperands (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
            (.integer x.toInt) (row.values.getD col .null)).1
          (Resolved.comparisonOperands (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
            (.integer x.toInt) (row.values.getD col .null)).2 = Ordering.eq := by
  have operand : resolveOperand runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) { current := some 0 } false
      (.identifier (name! "id") .none) = .ok (.column col, table.columns[col]?.map CatalogColumn.affinity) :=
    resolveOperand_identifier_table column
  have subResolves : FilterResolves runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) [] none none { current := some 0 } :=
    .inl ⟨rfl, rfl⟩
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.inQuery (.parameter 1) 0 false))
      (some (.inQuery (.parameter 1) 0 (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
        ((table.columns[col]?.map (·.collation)).getD .binary) false))
      { later := [scalarShape (table.columns[col]?.map CatalogColumn.affinity) none
        (table.columns[col]?.map (·.collation)) lowest] } :=
    fun lowest => FilterResolves.of_term (term := .inQuery (.parameter 1) 0 false)
      (result := (.inQuery (.parameter 1) 0 (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
        ((table.columns[col]?.map (·.collation)).getD .binary) false, none))
      (by simp [namesAlias]) (by simp [sql_simp, scalarShape, inCollation])
  rw [← Syntax.Expr.columnCollation_identifier_table (catalog := db.raw.catalog) (reference := ⟨name! "invoices", none, none⟩)
    (position := position) column] at mainResolves
  refine Iff.trans (Holds.iff_selectOne_column (head := rfl) (reference := ⟨name! "invoices", none, none⟩)
    (by decide) (by decide) rfl found operand (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]) subResolves
    mainResolves (by simp [Resolved.Expr.any]) (by simp [sql_simp]) (by simp)
    (by simp [sql_simp])) ?_
  rw [Syntax.Expr.columnCollation_identifier_table column]
  simp [sql_simp, Resolved.SubqueryRun.certain]
  rw [Resolved.truthy_inValue_eq_true]
  simp [Resolved.scalarRows, sql_simp]
  have mem : ∀ r, r ∈ ({ shape := table, rows := db.raw.rows[position]?.getD [] } : Table).scanRows ↔
      r ∈ db.raw.rows[position]?.getD [] := fun r => (Table.scanRows_perm _).mem_iff
  simp [Resolved.sourceRows, boundValue, Value.isNull, mem]
  constructor
  · rintro ⟨_, ⟨_, ⟨row, inRows, rfl⟩, rfl⟩, nonNull, equal⟩
    exact ⟨row, inRows, nonNull, equal⟩
  · rintro ⟨row, inRows, nonNull, equal⟩
    exact ⟨_, ⟨_, ⟨row, inRows, rfl⟩, rfl⟩, nonNull, equal⟩

-- The instances on `shop`, whose invoices have the ids 1 and 2: the query holds for `x = 2` and not for `x = 5`.
theorem shop_has_invoice_two (x : Int64) (isTwo : x = 2) :
    Holds (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") shop :=
  (x_is_an_invoice_id shop x invoices.1 0 invoices.2 (by decide +kernel) (by decide +kernel)).2
    (by subst isTwo; decide +kernel)

theorem shop_has_no_invoice_five (x : Int64) (isFive : x = 5) :
    ¬ Holds (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") shop :=
  fun holds => by
    have := (x_is_an_invoice_id shop x invoices.1 0 invoices.2 (by decide +kernel) (by decide +kernel)).1 holds
    subst isFive
    revert this
    decide +kernel

set_option doc.verso true

/-- Over every database with the invoices table and id column, IN is empty exactly when its resolved membership
test is not true, and it never fails. Proof sketch: resolve the parameter and column with their comparison affinity
and collation, then apply {name}`Empty.iff_selectOne_column` and {name}`Fails.not_selectOne_column`. -/
theorem invoice_membership_empty_and_safe (db : Database) (x : Int64) (position col : Nat) (table : CatalogTable)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (column : columnPosition table.columns (name! "id") = some col) :
    (Empty (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") db ↔
      Resolved.truthy ((Resolved.Expr.inQuery (.parameter 1) 0
        (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
        ((table.columns[col]?.map (·.collation)).getD .binary) false).eval
        ((Resolved.EvalContext.bound [.integer x.toInt]).withRuns [Resolved.SubqueryRun.certain
          (Resolved.scalarRows (Resolved.EvalContext.bound [.integer x.toInt]) none (.column col)
            { shape := table, rows := db.raw.rows.getD position [] })]) []) = false) ∧
    ¬ Fails (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") db := by
  have operand : resolveOperand runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) { current := some 0 } false
      (.identifier (name! "id") .none) = .ok (.column col, table.columns[col]?.map CatalogColumn.affinity) :=
    resolveOperand_identifier_table column
  have subResolves : FilterResolves runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) [] none none { current := some 0 } :=
    .inl ⟨rfl, rfl⟩
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.inQuery (.parameter 1) 0 false))
      (some (.inQuery (.parameter 1) 0 (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
        ((table.columns[col]?.map (·.collation)).getD .binary) false))
      { later := [scalarShape (table.columns[col]?.map CatalogColumn.affinity) none
        (table.columns[col]?.map (·.collation)) lowest] } :=
    fun lowest => FilterResolves.of_term (term := .inQuery (.parameter 1) 0 false)
      (result := (.inQuery (.parameter 1) 0 (comparisonAffinity none (table.columns[col]?.map CatalogColumn.affinity))
        ((table.columns[col]?.map (·.collation)).getD .binary) false, none))
      (by simp [namesAlias]) (by simp [sql_simp, scalarShape, inCollation])
  rw [← Syntax.Expr.columnCollation_identifier_table (catalog := db.raw.catalog) (reference := ⟨name! "invoices", none, none⟩)
    (position := position) column] at mainResolves
  constructor
  · refine Iff.trans (Empty.iff_selectOne_column (head := rfl) (reference := ⟨name! "invoices", none, none⟩)
      (by decide) (by decide) rfl found operand (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]) subResolves
      mainResolves (by simp [Resolved.Expr.any]) (by simp [sql_simp]) (by simp) (by simp [sql_simp])) ?_
    rw [Syntax.Expr.columnCollation_identifier_table column]
    rfl
  · exact Fails.not_selectOne_column (head := rfl) (reference := ⟨name! "invoices", none, none⟩)
      (by decide) (by decide) rfl found operand (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]) subResolves
      mainResolves (by simp [Resolved.Expr.any]) (by simp [sql_simp]) (by simp) (by simp [sql_simp])

example (x : Int64) (isFive : x = 5) : Empty (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") shop :=
  (invoice_membership_empty_and_safe shop x invoices.1 0 invoices.2 (by decide +kernel)
    (by decide +kernel)).1.2 (by subst isFive; decide +kernel)
example (x : Int64) (isTwo : x = 2) : ¬ Empty (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") shop := by
  rw [(invoice_membership_empty_and_safe shop x invoices.1 0 invoices.2 (by decide +kernel) (by decide +kernel)).1]
  subst isTwo
  decide +kernel
example (x : Int64) : ¬ Fails (sql r"SELECT 1 WHERE $x IN (SELECT id FROM invoices)") shop :=
  (invoice_membership_empty_and_safe shop x invoices.1 0 invoices.2 (by decide +kernel) (by decide +kernel)).2
