import Belay.Sqlite.ModelFacts

set_option doc.verso true

/-! Constant-value extension is a structural projection fact, independent of observation contracts. -/

namespace Belay.Sqlite

/-- Retain rowids and row order, replacing each row's cells with one observed
supplied value. Use {lean}`Value.null` for a nullable field without a default.
The input cells do not affect the result; an empty input gives an empty output. -/
def constantExtension (value : Value) (rows : List (Int × List (Option Value))) : List (Int × List (Option Value)) :=
  rows.map fun row => (row.1, [some value])

/-- For every test, list and item: if {name}`findPosition` finds nothing in the
list and the test accepts the item, it finds the item after the list. The proof
inducts over the list: the test rejects each head, so each step adds one to the
position, and the empty prefix finds the item at position zero. -/
theorem findPosition_append_none {test : α → Bool} {items : List α} (absent : findPosition test items = none)
    (accepted : test item = true) : findPosition test (items ++ [item]) = some (items.length, item) := by
  induction items with
  | nil => simp [findPosition, accepted]
  | cons head rest ih =>
    simp only [findPosition] at absent
    split at absent
    · cases absent
    · rename_i rejected
      have tail := ih (by simpa using absent)
      simp [findPosition, List.cons_append, rejected, tail]

/-- For every table, column, value and requested old-field list, assume:
* Every stored row has one cell per original column.
* {name}`columnPosition` finds no original column with the added column's name.
Then projecting that name after {name}`Table.appendColumns` equals
{name}`constantExtension` of the original old-field projection, with the
affinity-applied value. Thus every old row contributes its physical rowid and
one observed value. The old-field list has no
membership requirement: only its projection's rowids are used. With no rows, the
width assumption is vacuous and both projections are empty; the fresh-name
assumption remains. The proof unfolds the projections and compares each row:
freshness places the new field after the original columns, and row width makes
its selected cell the appended value. -/
theorem Table.project_newColumn {table : Table} {column : CatalogColumn} (value : Value)
    (width : ∀ row ∈ table.rows, row.values.length = table.shape.columns.length)
    (fresh : columnPosition table.shape.columns column.name = none) :
    (table.appendColumns [(column, value)]).project [column.name] =
      constantExtension (storeValue column.affinity value) (table.project fields) := by
  have absent : findPosition (fun old => normalizeIdentifier old.name == normalizeIdentifier column.name)
      table.shape.columns = none := by
    simpa [columnPosition] using fresh
  have found : columnPosition (table.shape.columns ++ [column]) column.name = some table.shape.columns.length := by
    simp [columnPosition, findPosition_append_none (item := column) absent (by simp)]
  simp only [Table.project, Table.appendColumns, constantExtension, List.map_map]
  apply List.map_congr_left
  intro row member
  simp [found, Row.appendValues, ← width row member]


/-- For every table and name list, {name}`Covers` implies that
{name}`columnPosition` finds every requested name. An empty list satisfies both
conditions vacuously. Use it where code checks the lookup of each name. The
proof turns each successful lookup into its Boolean test. -/
theorem Covers.columnsPresent (covered : Covers table names) :
    names.all (fun name => (columnPosition table.shape.columns name).isSome) = true := by
  apply List.all_eq_true.mpr
  intro name member
  obtain ⟨index, found⟩ := covered name member
  simp [found]

end Belay.Sqlite
