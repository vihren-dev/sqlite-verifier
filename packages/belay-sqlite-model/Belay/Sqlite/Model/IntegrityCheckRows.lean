import Belay.Sqlite.Model.IntegrityCheck
import Belay.Sqlite.Model.DatabaseConstraintChecks
import Belay.Sqlite.Model.QueryLaws

set_option doc.verso true

/-! The first laws of the check pragmas (ADR 0019, D2): a table gives no failures exactly when
its cells give none and no two of its rows conflict, and its cells give none exactly when
{lit}`Table.NotNull`, {lit}`Table.TypesFit` and {lit}`Table.ChecksHold` hold. The laws of the keys
are in {lit}`IntegrityCheckKeys`. -/

namespace Belay.Sqlite.Model

/-- For every quick flag, table name, indexes, table and row lists {lit}`earlier` and
{lit}`rows`: the walk {name}`Table.failuresFrom` over {lit}`rows` after {lit}`earlier` gives no
failure exactly when all of these hold:

* no row of {lit}`rows` has a failure of its cells ({name}`Table.cellFailures`);
* for every row {lit}`a` of {lit}`earlier` and row {lit}`b` of {lit}`rows`: they are not out of
  order ({name}`Table.orderConflict`), and for every index of {lit}`indexes`, the entry of
  {lit}`b` is not followed by an equal entry of {lit}`a` ({name}`Table.entryDuplicated`);
* for every two rows {lit}`a` and {lit}`b` of {lit}`rows`, {lit}`a` before {lit}`b`: they are
  not out of order, and for every index of {lit}`indexes`, the entry of {lit}`a` is not followed
  by an equal entry of {lit}`b`, and the entry of {lit}`b` not by an equal entry of {lit}`a`.

Proof sketch: induction over {lit}`rows`; a row's failures are its pairs with the earlier rows
and with the later rows. -/
theorem Table.failuresFrom_eq_nil (quick : Bool) (name : Identifier) (indexes : List CheckedIndex) (table : Table) :
    ∀ earlier rows : List Row, table.failuresFrom quick name indexes earlier rows = [] ↔
      (∀ row ∈ rows, table.cellFailures name row = []) ∧
      (∀ a ∈ earlier, ∀ b ∈ rows, table.orderConflict quick a b = false ∧
        ∀ checked ∈ indexes, table.entryDuplicated quick checked b a false = false) ∧
      rows.Pairwise fun a b => table.orderConflict quick a b = false ∧ ∀ checked ∈ indexes,
        table.entryDuplicated quick checked a b true = false ∧ table.entryDuplicated quick checked b a false = false
  | earlier, [] => by simp [Table.failuresFrom]
  | earlier, row :: later => by
    have orderNil : table.orderFailures quick name earlier row = [] ↔
        ∀ a ∈ earlier, table.orderConflict quick a row = false := by
      unfold Table.orderFailures
      split <;> simp_all
    have uniqueNil : table.uniqueFailures quick indexes earlier row later = [] ↔
        ∀ checked ∈ indexes, (∀ a ∈ earlier, table.entryDuplicated quick checked row a false = false) ∧
          ∀ b ∈ later, table.entryDuplicated quick checked row b true = false := by
      simp [Table.uniqueFailures, List.filter_eq_nil_iff]
    rw [Table.failuresFrom, List.append_eq_nil_iff, List.append_eq_nil_iff, List.append_eq_nil_iff, orderNil,
      uniqueNil, Table.failuresFrom_eq_nil quick name indexes table (row :: earlier) later]
    simp only [List.mem_cons, List.pairwise_cons, forall_eq_or_imp]
    constructor
    · rintro ⟨⟨⟨order, cells⟩, unique⟩, laterCells, ⟨rowAll, earlierAll⟩, pairs⟩
      exact ⟨⟨cells, laterCells⟩,
        fun a member => ⟨⟨order a member, fun checked found => (unique checked found).1 a member⟩,
          earlierAll a member⟩,
        fun b member => ⟨(rowAll b member).1, fun checked found =>
          ⟨(unique checked found).2 b member, (rowAll b member).2 checked found⟩⟩, pairs⟩
    · rintro ⟨⟨cells, laterCells⟩, earlierAll, rowAll, pairs⟩
      exact ⟨⟨⟨fun a member => (earlierAll a member).1.1, cells⟩,
          fun checked found => ⟨fun a member => (earlierAll a member).1.2 checked found,
            fun b member => ((rowAll b member).2 checked found).1⟩⟩, laterCells,
        ⟨fun b member => ⟨(rowAll b member).1, fun checked found => ((rowAll b member).2 checked found).2⟩,
          fun a member => (earlierAll a member).2⟩, pairs⟩

/-- For every table name, column and cell: the cell has no failure ({name}`columnFailure`)
exactly when the cell is not NULL or the column has no NOT NULL, and the cell fits the column's
{lit}`STRICT` type when it has one.
Proof sketch: case analysis on the NOT NULL flag, the strict type and whether the cell is NULL. -/
theorem columnFailure_eq_none (name : Identifier) (column : CatalogColumn) (value : Value) :
    columnFailure name column value = none ↔
      (!column.notNull || value != .null) = true ∧ column.strictType.all (·.fits value) = true := by
  unfold columnFailure
  cases notNull : column.notNull <;> cases strict : column.strictType <;> by_cases isNull : value = .null <;>
    simp_all [StrictType.fits] <;> split <;> simp_all

/-- For every table name, table and row: the row has no failure of its cells
({name}`Table.cellFailures`) exactly when, in the pairs of a column and a cell, no NOT NULL
column holds NULL, the row fits the types ({name}`LiteralData.typesFit`) and it satisfies the
CHECK constraints ({name}`LiteralData.checksHold`).
Proof sketch: an append is empty when both parts are, and a {lit}`filterMap` is empty when each pair
gives none ({name}`columnFailure_eq_none`). -/
theorem Table.cellFailures_eq_nil (name : Identifier) (table : Table) (row : Row) :
    table.cellFailures name row = [] ↔
      ((table.shape.columns.zip row.values).all fun (column, value) => !column.notNull || value != .null) = true ∧
        LiteralData.typesFit table.shape row = true ∧ LiteralData.checksHold table.shape row = true := by
  unfold Table.cellFailures LiteralData.typesFit
  rw [List.append_eq_nil_iff, List.filterMap_eq_nil_iff]
  simp only [List.all_eq_true, columnFailure_eq_none]
  constructor
  · rintro ⟨cells, checks⟩
    refine ⟨fun pair member => (cells pair member).1, fun pair member => (cells pair member).2, ?_⟩
    revert checks; split <;> simp_all
  · rintro ⟨nulls, types, checks⟩
    exact ⟨fun pair member => ⟨nulls pair member, types pair member⟩, by simp [checks]⟩

/-- For every table name and table: no row of the table in scan order has a failure of its
cells exactly when the table satisfies {name}`Table.NotNull`, {name}`Table.TypesFit` and
{name}`Table.ChecksHold`. Proof sketch: the scan is a permutation of the rows
({name}`Table.scanRows_perm`), and each fact is the check of {name}`Table.cellFailures_eq_nil`
over every row ({name}`Table.notNullRows_iff` and the others). -/
theorem Table.cellFailures_scan (name : Identifier) (table : Table) :
    (∀ row ∈ table.scanRows, table.cellFailures name row = []) ↔ table.NotNull ∧ table.TypesFit ∧ table.ChecksHold := by
  rw [← Table.notNullRows_iff, ← Table.typedRows_iff, ← Table.checkedRows_iff]
  simp only [LiteralData.notNullRows, LiteralData.typedRows, LiteralData.checkedRows, List.all_eq_true,
    table.scanRows_perm.mem_iff, Table.cellFailures_eq_nil]
  exact ⟨fun all => ⟨fun row member => (all row member).1, fun row member => (all row member).2.1,
      fun row member => (all row member).2.2⟩,
    fun ⟨nulls, types, checks⟩ row member => ⟨nulls row member, types row member, checks row member⟩⟩

end Belay.Sqlite.Model
