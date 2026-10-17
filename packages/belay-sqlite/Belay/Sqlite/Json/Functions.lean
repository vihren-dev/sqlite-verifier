import Belay.Sqlite.Json.Extract

set_option doc.verso true

/-! The SQL functions {lit}`json_type`, {lit}`json_array_length` and {lit}`json` (ADR 0012,
amendment 5, slice 6c; {lit}`jsonTypeFunc`, {lit}`jsonArrayLengthFunc` and
{lit}`jsonRemoveFunc` with one argument in 3.51.0). Each parses its JSON argument first,
then looks up the optional path as {lit}`json_extract` does; a NULL argument, a NULL path
and a path that selects nothing give NULL. -/

namespace Belay.Sqlite.Json

open Belay.Sqlite

/-- The JSON type name of a node ({lit}`jsonbType`): {lit}`integer` for a number without a
fraction or an exponent, also beyond 64 bits and in hexadecimal, and {lit}`real` for every
other number, {lit}`9e999` of an infinity included. -/
def JsonNode.typeName : JsonNode → String
  | .null => "null"
  | .true => "true"
  | .false => "false"
  | .int _ | .int5 _ => "integer"
  | .float _ | .float5 _ => "real"
  | .text _ | .textj _ | .text5 _ | .textraw _ => "text"
  | .array _ => "array"
  | .object _ => "object"

/-- The node that a JSON function reads: the parsed JSON argument, or the node at the
path when a path is given; {lit}`none` for NULL arguments and for a path that selects
nothing. -/
def selectNode (json : Value) (path : Option Value) : Except JsonError (Option JsonNode) :=
  match parseJsonArgument json with
  | .error error => .error error
  | .ok none => .ok none
  | .ok (some node) =>
    match path with
    | none => .ok (some node)
    | some path =>
      match valueText path with
      | none => .ok none
      | some pathBytes => lookupFullPath node pathBytes

/-- The value of a selected node, or NULL when nothing is selected. -/
def selectedValue (selected : Except JsonError (Option JsonNode)) (value : JsonNode → Value) :
    Except JsonError Value :=
  match selected with
  | .error error => .error error
  | .ok none => .ok .null
  | .ok (some node) => .ok (value node)

/-- {lit}`json_type(json [, path])`: the type name of the selected node as TEXT. -/
def jsonType (json : Value) (path : Option Value) : Except JsonError Value :=
  selectedValue (selectNode json path) fun node => .text node.typeName.toUTF8.toList

/-- {lit}`json_array_length(json [, path])`: the number of elements of the selected array,
and 0 for any other node. -/
def jsonArrayLength (json : Value) (path : Option Value) : Except JsonError Value :=
  selectedValue (selectNode json path) fun
    | .array items => .integer items.length
    | .null | .true | .false | .int _ | .int5 _ | .float _ | .float5 _ | .text _ | .textj _ | .text5 _
    | .textraw _ | .object _ => .integer 0

/-- {lit}`json(json)`: the rendered JSON text of the argument ({name}`renderNode`). -/
def jsonText (json : Value) : Except JsonError Value :=
  selectedValue (selectNode json none) fun node => .text (renderNode node)

end Belay.Sqlite.Json
