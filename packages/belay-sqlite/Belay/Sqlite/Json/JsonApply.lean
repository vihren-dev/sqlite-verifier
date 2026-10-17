import Belay.Sqlite.Json.Extract
import Belay.Sqlite.Resolution.QueryForm

set_option doc.verso true

/-! The JSON functions of a resolved expression (ADR 0012, amendment 5, slice 6b): each
{lit}`Resolved.JsonFunction` applied to the values of its arguments. -/

namespace Belay.Sqlite.Json

/-- The value of a JSON function over the values of its arguments, or its error.
{lit}`json_extract` takes the JSON and its paths ({name}`extract`); {lit}`->` and
{lit}`->>` take the JSON and one path ({name}`arrowJson`, {name}`arrowValue`). Resolution
gives an arrow exactly two arguments; any other count is NULL. For example,
{lean}`apply .arrowValue [.text "[7]".toUTF8.toList, .integer 0]` is {lit}`.ok (.integer 7)`. -/
def apply (function : Resolved.JsonFunction) (arguments : List Value) : Except JsonError Value :=
  match function, arguments with
  | .extract, [] => .ok .null
  | .extract, json :: paths => extract json paths
  | .arrowJson, [json, path] => arrowJson json path
  | .arrowValue, [json, path] => arrowValue json path
  | .arrowJson, _ | .arrowValue, _ => .ok .null

#guard match apply .arrowValue [.text "[7]".toUTF8.toList, .integer 0] with
  | .ok value => value == .integer 7
  | .error _ => false

end Belay.Sqlite.Json
