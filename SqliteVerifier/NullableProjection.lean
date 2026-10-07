import SqliteVerifier.Library

set_option doc.verso true

/-! Reusable observations for a newly added nullable field. Both old values and
new NULLs are read from the represented table, retaining physical row identities. -/

namespace SqliteVerifier

/-- Observations of selected old fields and an optional added field, retaining
physical rowids. Use {lean}`NullableView.mk [] none` before observing an added
field in an empty table. Absence differs from an observed empty projection. -/
structure NullableView where
  /-- Old-field projection, in stored row order with physical rowids. -/
  rows : LogicalRows
  /-- Added-field projection; {name}`Option.none` means it was not requested,
  whereas {lean}`(some [] : Option LogicalRows)` means an empty observed table. -/
  added : Option LogicalRows
  deriving Repr, DecidableEq

/-- Retain rowids and row order, replacing each row's cells with one observed
{name}`Value.null`. Use this for the expected projection of a new nullable field;
{assert}`nullExtension [] = []`. The input cells do not affect the result. -/
def nullExtension (rows : LogicalRows) : LogicalRows :=
  rows.map fun row => (row.1, [some .null])

/-- Observe selected old fields and optionally one added field from a stored
table. Use {lean}`(none : Option String)` when no added field is requested and
an empty field list when no old cells are needed. An absent table returns
{name}`Option.none`. A present table returns its old-field projection and,
if a field name was supplied, its projection of that name. Missing columns
produce missing cells under {name}`Table.project`; supplying a name does not
prove that the field exists or that its values are NULL. -/
def observeNullable (tableName : String) (fields : List String) (added : Option String)
    (database : Database) : Option NullableView :=
  (database tableName).map fun table =>
    ⟨table.project fields, added.map fun name => table.project [name]⟩

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
