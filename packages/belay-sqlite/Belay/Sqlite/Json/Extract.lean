import Belay.Sqlite.RealText
import Belay.Sqlite.Json.Read
import Belay.Sqlite.Json.Path
import Belay.Sqlite.Json.SqlValue

set_option doc.verso true

/-! The SQL functions {lit}`json_extract`, {lit}`->` and {lit}`->>` ({lit}`jsonExtractFunc`
in 3.51.0) on TEXT, INTEGER, REAL and NULL arguments. The JSON argument is parsed first;
then each path is looked up in order, and the first error or NULL path ends the call. -/

namespace Belay.Sqlite.Json

open Belay.Sqlite

/-- The text of an SQL value as {lit}`sqlite3_value_text` gives it: the decimal digits of
an INTEGER, {name}`realText` of a REAL, the bytes of TEXT and BLOB, and {lit}`none` for
NULL. -/
def valueText : Value → Option (List UInt8)
  | .null => none
  | .integer value => some (toString value).toUTF8.toList
  | .real bits => some (realText (Float.ofBits bits)).toUTF8.toList
  | .text bytes | .blob bytes => some bytes

/-- The bytes of a text up to its first NUL byte, as a C string reads them. -/
def cString (bytes : List UInt8) : List UInt8 := bytes.takeWhile (· != 0)

/-- Parse the JSON argument ({lit}`jsonParseFuncArg`): {lit}`none` for NULL, the tree of
the value's text, or an error for malformed text. A BLOB is not modelled. -/
def parseJsonArgument (json : Value) : Except JsonError (Option JsonNode) :=
  match json with
  | .null => .ok none
  | .blob _ => .error .blobArgument
  | .integer _ | .real _ | .text _ =>
    match (valueText json).bind parseJsonText with
    | some node => .ok (some node)
    | none => .error .malformed

/-- Convert a lookup result for a path text into a node, {lit}`none` for "not found",
or the error of {lit}`jsonExtractFunc`. -/
def lookupOutcome (path : List UInt8) : LookupResult → Except JsonError (Option JsonNode)
  | .found node => .ok (some node)
  | .notFound => .ok none
  | .malformed => .error .malformed
  | .pathError => .error (.badPath path)

/-- Look up a full path text, which must start with {lit}`$`, as {lit}`json_extract`
does. -/
def lookupFullPath (node : JsonNode) (pathBytes : List UInt8) : Except JsonError (Option JsonNode) :=
  let path := cString pathBytes
  if path.head? == some 36 then lookupOutcome path (lookupPath path 1 node)
  else .error (.badPath path)

/-- Whether every byte is an ASCII letter, a digit or {lit}`_` ({lit}`jsonAllAlphanum`);
true for empty text. -/
def isAllAlphanumeric (bytes : List UInt8) : Bool := bytes.all fun byte => isAsciiAlnum byte || byte == 95

/-- The path that an arrow operator looks up for a right operand that does not start
with {lit}`$`: an INTEGER N is {lit}`[N]`, or {lit}`[#N]` when negative; a label of
letters, digits and {lit}`_` is {lit}`.label`; text like {lit}`[...]` stays; other text
is a quoted label. -/
def abbreviatedPath (isInteger : Bool) (path : List UInt8) : List UInt8 :=
  if isInteger then [91] ++ (if path.head? == some 45 then [35] else []) ++ path ++ [93]
  else if isAllAlphanumeric path then 46 :: path
  else if path.head? == some 91 && path.length ≥ 3 && path.getLast? == some 93 then path
  else [46, 34] ++ path ++ [34]

/-- Look up the right operand of {lit}`->` or {lit}`->>` (the {lit}`JSON_ABPATH` form): a
full path when it starts with {lit}`$`, else {name}`abbreviatedPath`. A bad path error
reports the operand text. -/
def lookupArrowPath (node : JsonNode) (operand : Value) (pathBytes : List UInt8) :
    Except JsonError (Option JsonNode) :=
  let path := cString pathBytes
  if path.head? == some 36 then lookupOutcome path (lookupPath path 1 node)
  else
    let isInteger := match operand with
      | .integer _ => Bool.true
      | .null | .real _ | .text _ | .blob _ => Bool.false
    lookupOutcome path (lookupPath (abbreviatedPath isInteger path) 0 node)

/-- The JSON array text of the renderings of several paths; {lit}`null` for a path that
selects nothing. A NULL path makes the whole result NULL. -/
def extractSeveral (node : JsonNode) : List Value → List (List UInt8) → Except JsonError Value
  | [], parts => .ok (.text ([91] ++ (List.intercalate [44] parts.reverse) ++ [93]))
  | path :: rest, parts =>
    match valueText path with
    | none => .ok .null
    | some pathBytes =>
      match lookupFullPath node pathBytes with
      | .error error => .error error
      | .ok selected =>
        let part := match selected with
          | some found => renderNode found
          | none => "null".toUTF8.toList
        extractSeveral node rest (part :: parts)

/-- {lit}`json_extract(json, paths...)` with SQL values as arguments. With no path the
result is NULL and the JSON is not read. With one path, the SQL value of the selected
node, or NULL; with more, the JSON array text of the selected nodes. -/
def extract (json : Value) (paths : List Value) : Except JsonError Value :=
  match paths with
  | [] => .ok .null
  | [path] =>
    match parseJsonArgument json with
    | .error error => .error error
    | .ok none => .ok .null
    | .ok (some node) =>
      match valueText path with
      | none => .ok .null
      | some pathBytes =>
        match lookupFullPath node pathBytes with
        | .error error => .error error
        | .ok none => .ok .null
        | .ok (some found) => sqlValueOfNode found
  | _ :: _ :: _ =>
    match parseJsonArgument json with
    | .error error => .error error
    | .ok none => .ok .null
    | .ok (some node) => extractSeveral node paths []

/-- Select the node of an arrow operator: parse the JSON, then look up the operand;
{lit}`none` for a NULL argument or no node. -/
def arrowSelect (json : Value) (path : Value) : Except JsonError (Option JsonNode) :=
  match parseJsonArgument json with
  | .error error => .error error
  | .ok none => .ok none
  | .ok (some node) =>
    match valueText path with
    | none => .ok none
    | some pathBytes => lookupArrowPath node path pathBytes

/-- {lit}`json -> path`: the minified JSON text of the selected node, or NULL. -/
def arrowJson (json : Value) (path : Value) : Except JsonError Value :=
  match arrowSelect json path with
  | .error error => .error error
  | .ok none => .ok .null
  | .ok (some found) => .ok (.text (renderNode found))

/-- {lit}`json ->> path`: the SQL value of the selected node, or NULL. -/
def arrowValue (json : Value) (path : Value) : Except JsonError Value :=
  match arrowSelect json path with
  | .error error => .error error
  | .ok none => .ok .null
  | .ok (some found) => sqlValueOfNode found

/-- The bytes of a path in SQLite's {lit}`%Q` quoting: in single quotes, with each single
quote doubled. -/
def quoteSqlText (bytes : List UInt8) : List UInt8 :=
  39 :: (bytes.flatMap fun byte => if byte == 39 then [39, 39] else [byte]) ++ [39]

/-- The error message that SQLite reports, or {lit}`none` for a BLOB argument, which the
model does not describe. -/
def JsonError.message? : JsonError → Option (List UInt8)
  | .malformed => some "malformed JSON".toUTF8.toList
  | .badPath path => some ("bad JSON path: ".toUTF8.toList ++ quoteSqlText path)
  | .blobArgument => none
  | .badFlags => some "FLAGS parameter to json_valid() must be between 1 and 15".toUTF8.toList

end Belay.Sqlite.Json
