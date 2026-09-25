import SqliteVerifier.Library

/-! Reusable observations for a newly added nullable field. Both old values and
new NULLs are read from the represented table, retaining physical row identities. -/

namespace SqliteVerifier

/-- A logical extension records protected old fields and the newly exposed field. -/
structure NullableView where
  rows : LogicalRows
  added : Option LogicalRows
  deriving Repr, DecidableEq

/-- Expected NULL extension preserves each protected row's actual physical identity. -/
def nullExtension (rows : LogicalRows) : LogicalRows :=
  rows.map fun row => (row.1, [some .null])

/-- Before addition there is no field; afterward its values are read from storage. -/
def observeNullable (tableName : String) (fields : List String) (added : Option String)
    (database : Database) : Option NullableView :=
  (database tableName).map fun table =>
    ⟨table.project fields, added.map fun name => table.project [name]⟩

/-- The visible new column of every old row is exactly NULL, not absent or invented. -/
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
