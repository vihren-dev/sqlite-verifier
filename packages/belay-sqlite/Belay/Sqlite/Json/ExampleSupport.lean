import Belay.Sqlite.Json.Extract

set_option doc.verso true

/-! Short helpers for the checked examples of the JSON functions. They turn Lean
strings into SQL values and compare results without a {lit}`BEq` instance on
{lit}`Except`. -/

namespace Belay.Sqlite.Json.ExampleSupport

open Belay.Sqlite Belay.Sqlite.Json

/-- The UTF-8 bytes of a string. -/
def utf8 (text : String) : List UInt8 := text.toUTF8.toList

/-- A TEXT value with the UTF-8 bytes of a string. -/
def sqlText (text : String) : Value := .text (utf8 text)

/-- Whether a result is the value {lit}`expected`. -/
def gives (result : Except JsonError Value) (expected : Value) : Bool :=
  match result with
  | .ok value => value == expected
  | .error _ => Bool.false

/-- Whether a result is TEXT with the UTF-8 bytes of a string. -/
def givesText (result : Except JsonError Value) (expected : String) : Bool := gives result (sqlText expected)

/-- Whether a result is the error {lit}`expected`. -/
def fails (result : Except JsonError Value) (expected : JsonError) : Bool :=
  match result with
  | .ok _ => Bool.false
  | .error error => error == expected

/-- {lit}`json_extract(json, '$')` on a TEXT argument. -/
def extractRoot (json : String) : Except JsonError Value := extract (sqlText json) [sqlText "$"]

/-- {lit}`json -> '$'` on a TEXT argument: the rendering of the whole value. -/
def renderRoot (json : String) : Except JsonError Value := arrowJson (sqlText json) (sqlText "$")

/-- {lit}`json_extract(json, path)` on TEXT arguments. -/
def extractAt (json path : String) : Except JsonError Value := extract (sqlText json) [sqlText path]

end Belay.Sqlite.Json.ExampleSupport
