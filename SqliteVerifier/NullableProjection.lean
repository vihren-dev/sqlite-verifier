import SqliteVerifier.Library
import SqliteVerifier.ModelProjection

set_option doc.verso true

/-! Application observations combine old fields with an optional nullable-field projection. -/

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


end SqliteVerifier
