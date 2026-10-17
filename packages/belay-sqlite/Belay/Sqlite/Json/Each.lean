import Belay.Sqlite.Json.Functions
import Belay.Sqlite.Json.JsonbOffset

set_option doc.verso true

/-! The table-valued function {lit}`json_each(json [, path])` on TEXT, INTEGER, REAL and
NULL arguments ({lit}`jsonEachFilter`, {lit}`jsonEachColumn` and {lit}`jsonEachNext` in
3.51.0, without the recursion of {lit}`json_tree`). It gives one row per element of the
selected array, one row per member of the selected object, or one row for a selected
scalar. -/

namespace Belay.Sqlite.Json

open Belay.Sqlite

/-- The cells that are the same in every row of one call: the root path text, which is
the {lit}`path` column and the hidden {lit}`root` column, and the JSON text of the hidden
{lit}`json` column. -/
structure EachContext where
  /-- The root path as given, up to its first NUL byte, or {lit}`$` without one. -/
  rootPath : List UInt8
  /-- The JSON argument as {lit}`sqlite3_value_text` gives it, up to its first NUL byte. -/
  jsonText : List UInt8

/-- Whether a node is an array or an object; {lit}`jsonEachColumn` gives no {lit}`atom`
for these. -/
def JsonNode.isContainer : JsonNode → Bool
  | .array _ | .object _ => Bool.true
  | .null | .true | .false | .int _ | .int5 _ | .float _ | .float5 _ | .text _ | .textj _ | .text5 _
  | .textraw _ => Bool.false

/-- The path step of an object member that {lit}`jsonAppendPathName` prints: {lit}`.label`
when the stored label starts with an ASCII letter and has only ASCII letters and digits,
else {lit}`."label"` with the stored bytes as they are, escapes included. -/
def memberPathStep (label : List UInt8) : List UInt8 :=
  let plain := match label with
    | first :: _ => isAsciiAlpha first && label.all isAsciiAlnum
    | [] => Bool.false
  if plain then 46 :: label else [46, 34] ++ label ++ [34]

/-- The path step {lit}`[N]` of array element N, as {lit}`jsonAppendPathName` prints it. -/
def itemPathStep (index : Nat) : List UInt8 := [91] ++ (toString index).toUTF8.toList ++ [93]

/-- One row of {lit}`json_each` in column order {lit}`key`, {lit}`value`, {lit}`type`,
{lit}`atom`, {lit}`id`, {lit}`parent`, {lit}`fullkey`, {lit}`path`, {lit}`json`,
{lit}`root`. The {lit}`value` is the SQL value of the node as {lit}`json_extract` gives
it; {lit}`parent` is always NULL because {lit}`json_each` does not recurse. -/
def eachRow (context : EachContext) (key : Value) (node : JsonNode) (id : Nat) (fullKey : List UInt8) :
    Except JsonError (List Value) := do
  let value ← sqlValueOfNode node
  let atom := if node.isContainer then Value.null else value
  pure [key, value, .text node.typeName.toUTF8.toList, atom, .integer id, .null, .text fullKey,
    .text context.rootPath, .text context.jsonText, .text context.rootPath]

/-- The rows of the elements of an array from element {lit}`index`, whose JSONB starts at
{lit}`offset`: the key is the index and the id is the element's offset. -/
def itemRows (context : EachContext) : List JsonNode → Nat → Nat → Except JsonError (List (List Value))
  | [], _, _ => pure []
  | item :: rest, index, offset => do
    let row ← eachRow context (.integer index) item offset (context.rootPath ++ itemPathStep index)
    let others ← itemRows context rest (index + 1) (offset + jsonbSize item)
    pure (row :: others)

/-- The rows of the members of an object, whose JSONB starts at {lit}`offset`: the key is
the decoded label and the id is the offset of the label. A label that is not a string is
malformed JSONB; a parsed text never has one. -/
def memberRows (context : EachContext) : List (JsonNode × JsonNode) → Nat → Except JsonError (List (List Value))
  | [], _ => pure []
  | (label, value) :: rest, offset => do
    let some (text, _) := label.labelText | throw JsonError.malformed
    let key ← sqlValueOfNode label
    let row ← eachRow context key value offset (context.rootPath ++ memberPathStep text)
    let others ← memberRows context rest (offset + jsonbSize label + jsonbSize value)
    pure (row :: others)

/-- The rows for the node that the root path selects. A container gives a row per child.
A scalar gives one row with a NULL key, the root path as {lit}`fullkey`, and as id the
offset of its label when the path ends at an object member, else its own offset
({lit}`jsonEachFilter` sets {lit}`p->i` to {lit}`iLabel`). -/
def selectedRows (context : EachContext) (located : LocatedNode) : Except JsonError (List (List Value)) :=
  let start := jsonbChildrenStart located.node located.offset
  match located.node with
  | .array items => itemRows context items 0 start
  | .object members => memberRows context members start
  | .null | .true | .false | .int _ | .int5 _ | .float _ | .float5 _ | .text _ | .textj _ | .text5 _
  | .textraw _ =>
    (eachRow context .null located.node (located.labelOffset.getD located.offset) context.rootPath).map
      fun row => [row]

/-- The node at the root path of {lit}`json_each`, as {lit}`jsonEachFilter` finds it: the
path text up to its first NUL byte must start with {lit}`$`, else it is a bad path; a
path that selects nothing gives {lit}`none`. -/
def eachRoot (root : JsonNode) (path : List UInt8) : Except JsonError (Option LocatedNode) :=
  if path.head? == some 36 then
    match locatePath path root with
    | none => .error (.badPath path)
    | some located => .ok located
  else .error (.badPath path)

/-- The rows of the table-valued function {lit}`json_each(json [, path])`: one list of ten cells
per row, in the column order key, value, type, atom, id, parent, fullkey, path, json, root.
The JSON argument is parsed first, so malformed JSON is an error even with a NULL path. A
NULL argument, a NULL path and a path that selects nothing give no rows. -/
def eachRows (json : Value) (path : Option Value) : Except JsonError (List (List Value)) :=
  match parseJsonArgument json with
  | .error error => .error error
  | .ok none => .ok []
  | .ok (some root) =>
    let jsonText := cString ((valueText json).getD [])
    match path with
    | none => selectedRows ⟨[36], jsonText⟩ ⟨root, 0, none⟩
    | some pathValue =>
      match valueText pathValue with
      | none => .ok []
      | some pathBytes =>
        let rootPath := cString pathBytes
        match eachRoot root rootPath with
        | .error error => .error error
        | .ok none => .ok []
        | .ok (some located) => selectedRows ⟨rootPath, jsonText⟩ located

end Belay.Sqlite.Json
