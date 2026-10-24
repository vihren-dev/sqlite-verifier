import Belay.Sqlite.Model.DatabaseFacts
import Belay.Sqlite.Model.StoreValueLaws

set_option doc.verso true

/-! What ADD COLUMN keeps of each table atom of {lit}`Database.Admitted` (ADR 0022, D3, slice 4),
one law for each atom. {lit}`Table.appendColumns` keeps the old cells and the rowids, and appends
one stored cell for each new column to every row. So "rowids distinct", "rowids in range", "rows
wide" and "rows aliased" are kept without a condition, and "rows stored" is kept when the rows are
wide, because the stored form of an old cell is read at the position of its own column. -/

namespace Belay.Sqlite.Model

/-- For every table and list of columns with values: if the table satisfies {name}`Table.RowidsDistinct`,
the table after {name}`Table.appendColumns` does. Proof sketch: the rowids of the rows are the same
list. -/
theorem Table.RowidsDistinct.appendColumns {table : Table} (distinct : table.RowidsDistinct)
    (columns : List (CatalogColumn × Value)) : (table.appendColumns columns).RowidsDistinct := by
  simpa [Table.RowidsDistinct, Table.appendColumns, Row.appendValues, List.map_map, Function.comp_def] using distinct

/-- For every table and list of columns with values: if the table satisfies {name}`Table.RowidsInRange`,
the table after {name}`Table.appendColumns` does. Proof sketch: a row after is an old row with cells
appended, and the rowid stays. -/
theorem Table.RowidsInRange.appendColumns {table : Table} (inRange : table.RowidsInRange)
    (columns : List (CatalogColumn × Value)) : (table.appendColumns columns).RowidsInRange := by
  intro row member
  obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
  exact inRange original oldMember

/-- For every table and list of columns with values: if the table satisfies {name}`Table.RowsWide`,
the table after {name}`Table.appendColumns` does. Proof sketch: a row after has as many cells more as
the table has columns more. -/
theorem Table.RowsWide.appendColumns {table : Table} (wide : table.RowsWide)
    (columns : List (CatalogColumn × Value)) : (table.appendColumns columns).RowsWide := by
  intro row member
  obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
  simp [Row.appendValues, Table.appendColumns, wide original oldMember]

/-- For every table and list of columns with values: if the table satisfies {name}`Table.RowsWide`
and {name}`Table.RowsStored`, the table after {name}`Table.appendColumns` satisfies
{name}`Table.RowsStored`. Without {name}`Table.RowsWide` the claim is not made. Proof sketch: an
old position reads the old column and the old cell, which are stored; a new position reads the
new column and its value stored with its own affinity ({name}`Value.store_store`). -/
theorem Table.RowsStored.appendColumns {table : Table} (wide : table.RowsWide) (stored : table.RowsStored)
    (columns : List (CatalogColumn × Value)) : (table.appendColumns columns).RowsStored := by
  intro row member position column value columnAt cellAt
  obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
  have width := wide original oldMember
  simp only [Table.appendColumns, Row.appendValues] at columnAt cellAt
  by_cases old : position < original.values.length
  · rw [List.getElem?_append_left old] at cellAt
    rw [List.getElem?_append_left (width ▸ old)] at columnAt
    exact stored original oldMember position column value columnAt cellAt
  · rw [List.getElem?_append_right (by omega)] at cellAt
    rw [List.getElem?_append_right (by omega)] at columnAt
    rw [← width] at columnAt
    cases found : columns[position - original.values.length]? with
    | none => simp [List.getElem?_map, found] at cellAt
    | some pair =>
      simp [List.getElem?_map, found] at columnAt cellAt
      subst column
      subst value
      exact Value.store_store _ _

/-- For every table and list of columns with values: if the table satisfies {name}`Table.RowsAliased`,
the table after {name}`Table.appendColumns` does. Proof sketch: the alias cell is an old cell, and
appending keeps the cells below the old width. -/
theorem Table.RowsAliased.appendColumns {table : Table} (aliased : table.RowsAliased)
    (columns : List (CatalogColumn × Value)) : (table.appendColumns columns).RowsAliased := by
  intro row member position alias
  obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
  have cell := aliased original oldMember position alias
  have old : position < original.values.length := (List.getElem?_eq_some_iff.mp cell).1
  simpa [Table.appendColumns, Row.appendValues, List.getElem?_append_left old] using cell

end Belay.Sqlite.Model
