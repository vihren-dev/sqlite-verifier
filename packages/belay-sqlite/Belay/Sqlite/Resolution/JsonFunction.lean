import Belay.Sqlite.Declarations

set_option doc.verso true

/-! The JSON functions that a resolved expression calls (ADR 0012, amendment 5, slices 6b
and 6c). -/

namespace Belay.Sqlite.Resolved

/-- A JSON function of ADR 0012, amendment 5, slices 6b and 6c: {lit}`json_extract`, the
operators {lit}`->` and {lit}`->>`, which SQLite's parser makes calls of the functions
{lit}`->` and {lit}`->>`, {lit}`json_type`, {lit}`json_valid`, {lit}`json_array_length`
and {lit}`json`. -/
inductive JsonFunction where
  /-- {lit}`json_extract(json, path, ...)`. -/
  | extract
  /-- {lit}`json -> path`: the selection as JSON text. -/
  | arrowJson
  /-- {lit}`json ->> path`: the selection as an SQL value. -/
  | arrowValue
  /-- {lit}`json_type(json [, path])`: the JSON type name. -/
  | typeName
  /-- {lit}`json_valid(json [, flags])`: 1 or 0. -/
  | valid
  /-- {lit}`json_array_length(json [, path])`: the number of elements. -/
  | arrayLength
  /-- {lit}`json(json)`: the rendered JSON text. -/
  | json
  deriving Repr, DecidableEq

end Belay.Sqlite.Resolved
