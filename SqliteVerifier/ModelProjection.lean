import SqliteVerifier.Model

set_option doc.verso true

/-! NULL extension is a structural projection fact, independent of observation contracts. -/

namespace SqliteVerifier

/-- Retain rowids and row order, replacing each row's cells with one observed
{name}`Value.null`. Use this for the expected projection of a new nullable field;
{assert}`nullExtension [] = []`. The input cells do not affect the result. -/
def nullExtension (rows : List (Int × List (Option Value))) : List (Int × List (Option Value)) :=
  rows.map fun row => (row.1, [some .null])

/-- For every table, column and requested old-field list, assume:
* Every stored row has one cell per original column.
* Lookup of the added column's name finds no original column.
Then projecting that name after {name}`Table.appendColumns` equals
{name}`nullExtension` of the original old-field projection. Thus every old
row contributes its physical rowid and one observed NULL. The old-field list
has no membership requirement: only its projection's rowids are used.
With no rows, the width assumption is vacuous and both projections are empty;
the fresh-name assumption remains. Use this theorem to establish the new-field
observation from row widths and name freshness.

The proof unfolds the projections and compares each stored row. Freshness
places the new field after the original columns, and row width makes its
selected cell the appended NULL. -/
theorem Table.project_newNullable {table : Table} {column : Column}
    (width : ∀ row ∈ table.rows, row.values.length = table.columns.length)
    (fresh : table.columns.findIdx? (fun old => old.name == column.name) = none) :
    (table.appendColumns [column]).project [column.name] =
      nullExtension (table.project fields) := by
  simp only [Table.project, Table.appendColumns, nullExtension, List.map_map]
  apply List.map_congr_left
  intro row member
  simp [fresh, Row.appendNulls, ← width row member]

end SqliteVerifier
