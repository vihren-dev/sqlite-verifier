import Belay

/-! A fixture of `tests/surface_claims_test.py`: the query form `SELECT 1 WHERE (SELECT count(*) FROM t
[WHERE p]) <op> $n` over every database (ADR 0017, S4; `Belay/Sqlite/CountQuery.lean`). Each claim is
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

/-- The guide's "table `t` has `$n` rows", over every database that has a table `invoices`: the query
holds exactly when the table has `n` rows. -/
theorem invoices_has_n_rows (db : Database) (position : Nat) (table : CatalogTable) (n : Int64)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table)) :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") db ↔
      (db.raw.rows.getD position []).length = n.toInt := by
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.compare .eq (.subquery 0) (.parameter 1)))
      (some (.compare .eq none (.subquery 0) (.parameter 1) .binary)) { later := [countShape lowest] } :=
    fun lowest => FilterResolves.of_term (term := .compare .eq (.subquery 0) (.parameter 1))
      (result := (.compare .eq none (.subquery 0) (.parameter 1) .binary, none)) (by simp [namesAlias]) (by
      simp [sql_simp, countShape]; rfl)
  have subResolves : FilterResolves runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) [] none none { current := some 0 } :=
    .inl ⟨rfl, rfl⟩
  refine Iff.trans (Holds.iff_selectOne_count (head := rfl) (count := by decide) (arguments := rfl) found subResolves
    mainResolves (by simp [sql_simp]) (by simp)) ?_
  simp [sql_simp, Resolved.comparisonOperands, boundValue, Resolved.SubqueryRun.count, Value.isNull,
    Comparison.holds]

-- The instances on `shop`, which has two invoices: with `n = 2` the query holds, with `n = 3` it does not.
theorem shop_has_two_invoices (n : Int64) (isTwo : n = 2) :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") shop :=
  (invoices_has_n_rows shop invoices.1 invoices.2 n (by decide +kernel)).2 (by subst isTwo; decide +kernel)

theorem shop_has_not_three_invoices (n : Int64) (isThree : n = 3) :
    ¬ Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") shop :=
  fun holds => by
    have := (invoices_has_n_rows shop invoices.1 invoices.2 n (by decide +kernel)).1 holds
    subst isThree
    revert this
    decide +kernel

/-- The same claim with a `WHERE` in the subquery: over every database that has a table `invoices` with a
column `amount` at position `index`, the number of invoices with a negative amount is `n` exactly when
the comparison is true for `n` stored rows of the table. -/
theorem invoices_with_negative_amount_are_n (db : Database) (position index : Nat) (table : CatalogTable) (n : Int64)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table))
    (column : columnPosition table.columns (name! "amount") = some index) :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices WHERE amount < 0) = $n") db ↔
      ((db.raw.rows.getD position []).filter fun row =>
        Resolved.truthy (Comparison.lt.apply
          (Resolved.comparisonOperands (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none)
            (row.values.getD index .null) 0).1
          (Resolved.comparisonOperands (comparisonAffinity (table.columns[index]?.map CatalogColumn.affinity) none)
            (row.values.getD index .null) 0).2
          ((table.columns[index]?.map (·.collation)).getD .binary))).length = n.toInt := by
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.compare .eq (.subquery 0) (.parameter 1)))
      (some (.compare .eq none (.subquery 0) (.parameter 1) .binary)) { later := [countShape lowest] } :=
    fun lowest => FilterResolves.of_term (term := .compare .eq (.subquery 0) (.parameter 1))
      (result := (.compare .eq none (.subquery 0) (.parameter 1) .binary, none)) (by simp [namesAlias]) (by
      simp [sql_simp, countShape]; rfl)
  have subResolves := FilterResolves.of_term (dqs := runContext.profile.dqsDml)
    (scope := tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) (aliases := [])
    (shapes := { current := some 0 })
    (term := .compare .lt (.identifier (name! "amount") .none) (.numeric "0")) (by simp [namesAlias])
    (by simp [sql_simp, column]; rfl)
  refine Iff.trans (Holds.iff_selectOne_count (head := rfl) (count := by decide) (arguments := rfl) found subResolves
    mainResolves (by simp [sql_simp]) (by simp [sql_simp])) ?_
  simp [sql_simp, Resolved.comparisonOperands, boundValue, Resolved.SubqueryRun.count, Value.isNull,
    Comparison.holds]
  rw [Resolved.countMatching_eq]
  refine Iff.of_eq (congrArg (fun count : Int => count = n.toInt)
    (congrArg Nat.cast (congrArg List.length (List.filter_congr fun row _ => ?_))))
  simp [sql_simp, Resolved.comparisonOperands, Value.isNull, Comparison.holds]
  rfl

-- The instance on `shop`: no invoice has a negative amount, so the count is zero and the query holds for `n = 0`.
theorem shop_has_no_negative_invoice (n : Int64) (isZero : n = 0) :
    Holds (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices WHERE amount < 0) = $n") shop :=
  (invoices_with_negative_amount_are_n shop invoices.1 2 invoices.2 n (by decide +kernel) (by decide +kernel)).2
    (by subst isZero; decide +kernel)

set_option doc.verso true

/-- Over every database with the table of invoices and every bound integer, the count comparison is empty exactly
when the count differs from that integer, and never fails. Proof sketch: share the subquery resolutions between
{name}`Empty.iff_selectOne_count` and {name}`Fails.not_selectOne_count`, then simplify the integer comparison. -/
theorem invoice_count_empty_and_safe (db : Database) (position : Nat) (table : CatalogTable) (n : Int64)
    (found : db.raw.catalog.findTable (name! "invoices") = some (position, table)) :
    (Empty (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") db ↔
      (db.raw.rows.getD position []).length ≠ n.toInt) ∧
    ¬ Fails (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") db := by
  have mainResolves : ∀ lowest, FilterResolves runContext.profile.dqsDml [] []
      (some (.compare .eq (.subquery 0) (.parameter 1)))
      (some (.compare .eq none (.subquery 0) (.parameter 1) .binary)) { later := [countShape lowest] } :=
    fun lowest => FilterResolves.of_term (term := .compare .eq (.subquery 0) (.parameter 1))
      (result := (.compare .eq none (.subquery 0) (.parameter 1) .binary, none)) (by simp [namesAlias]) (by
      simp [sql_simp, countShape]; rfl)
  have subResolves : FilterResolves runContext.profile.dqsDml
      (tableScope db.raw.catalog ⟨name! "invoices", none, none⟩ position table) [] none none { current := some 0 } :=
    .inl ⟨rfl, rfl⟩
  constructor
  · refine Iff.trans (Empty.iff_selectOne_count (head := rfl) (count := by decide) (arguments := rfl) found subResolves
      mainResolves (by simp [sql_simp]) (by simp)) ?_
    simp [sql_simp, Resolved.comparisonOperands, boundValue, Resolved.SubqueryRun.count, Value.isNull, Comparison.holds]
  · exact Fails.not_selectOne_count (head := rfl) (count := by decide) (arguments := rfl) found subResolves
      mainResolves (by simp [sql_simp]) (by simp)

example (n : Int64) (isThree : n = 3) : Empty (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") shop :=
  (invoice_count_empty_and_safe shop invoices.1 invoices.2 n (by decide +kernel)).1.2 (by subst isThree; decide +kernel)
example (n : Int64) (isTwo : n = 2) : ¬ Empty (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") shop := by
  rw [(invoice_count_empty_and_safe shop invoices.1 invoices.2 n (by decide +kernel)).1]
  subst isTwo
  decide +kernel
example (n : Int64) : ¬ Fails (sql r"SELECT 1 WHERE (SELECT count(*) FROM invoices) = $n") shop :=
  (invoice_count_empty_and_safe shop invoices.1 invoices.2 n (by decide +kernel)).2
