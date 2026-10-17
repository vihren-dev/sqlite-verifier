import Belay.Sqlite.Json.Functions
import Belay.Sqlite.Json.Valid
import Belay.Sqlite.Resolution.QueryForm

set_option doc.verso true

/-! The JSON functions of a resolved expression (ADR 0012, amendment 5, slices 6b and 6c):
each {lit}`Resolved.JsonFunction` applied to the values of its arguments. -/

namespace Belay.Sqlite.Json

/-- The value of a JSON function over the values of its arguments, or its error.
{lit}`json_extract` takes the JSON and its paths ({name}`extract`); {lit}`->` and
{lit}`->>` take the JSON and one path ({name}`arrowJson`, {name}`arrowValue`);
{lit}`json_type` and {lit}`json_array_length` the JSON and an optional path
({name}`jsonType`, {name}`jsonArrayLength`); {lit}`json_valid` the JSON and optional
flags, 1 without them ({name}`jsonValid`); and {lit}`json` the JSON ({name}`jsonText`).
Resolution gives each function a number of arguments that SQLite accepts; any other count
is NULL. For example,
{lean}`apply .arrowValue [.text "[7]".toUTF8.toList, .integer 0]` is {lit}`.ok (.integer 7)`. -/
def apply (function : Resolved.JsonFunction) (arguments : List Value) : Except JsonError Value :=
  match function, arguments with
  | .extract, [] => .ok .null
  | .extract, json :: paths => extract json paths
  | .arrowJson, [json, path] => arrowJson json path
  | .arrowValue, [json, path] => arrowValue json path
  | .typeName, [json] => jsonType json none
  | .typeName, [json, path] => jsonType json (some path)
  | .valid, [json] => jsonValid json (.integer 1)
  | .valid, [json, flags] => jsonValid json flags
  | .arrayLength, [json] => jsonArrayLength json none
  | .arrayLength, [json, path] => jsonArrayLength json (some path)
  | .json, [json] => jsonText json
  | .arrowJson, _ | .arrowValue, _ | .typeName, _ | .valid, _ | .arrayLength, _ | .json, _ => .ok .null

#guard match apply .arrowValue [.text "[7]".toUTF8.toList, .integer 0] with
  | .ok value => value == .integer 7
  | .error _ => false

end Belay.Sqlite.Json
