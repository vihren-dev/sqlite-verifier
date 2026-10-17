import Belay.Sqlite.Json.ExampleSupport
import Belay.Sqlite.Json.Each

set_option doc.verso true

/-! Checked examples of {lit}`json_each(json [, path])`. Each result was checked on native
SQLite 3.51.0 with {lit}`SELECT key, value, type, atom, id, parent, fullkey, path, json,
root FROM json_each(...)`, one statement per line. -/

namespace Belay.Sqlite.Json.EachExamples

open Belay.Sqlite Belay.Sqlite.Json Belay.Sqlite.Json.ExampleSupport

/-- {lit}`json_each` on a TEXT argument and an optional TEXT path. -/
def each (json : String) (path : Option String) : Except JsonError (List (List Value)) :=
  eachRows (sqlText json) (path.map sqlText)

/-- One column of every row (0 is {lit}`key`, 9 is {lit}`root`), or {lit}`none` for an
error, so that a check can look at one column alone. -/
def column (index : Nat) (result : Except JsonError (List (List Value))) : Option (List Value) :=
  match result with
  | .ok rows => some (rows.map fun row => row.getD index .null)
  | .error _ => none

/-- Whether the call succeeds with exactly these rows. -/
def givesRows (result : Except JsonError (List (List Value))) (expected : List (List Value)) : Bool :=
  match result with
  | .ok rows => rows == expected
  | .error _ => false

/-- Whether the call fails with the expected error. -/
def failsWith (result : Except JsonError (List (List Value))) (expected : JsonError) : Bool :=
  match result with
  | .ok _ => false
  | .error error => error == expected

/-- The JSON of the {lit}`id` examples: an object with members of every kind. -/
def mixed : String := "{\"a\":1,\"b\":[2,3],\"c\":\"s\",\"d\":null,\"e\":true,\"f\":2.5}"

-- A whole row: key, value, type, atom, id, parent, fullkey, path, json and root.
#guard givesRows (each "[10,{\"x\":1},30]" none) [
  [.integer 0, .integer 10, sqlText "integer", .integer 10, .integer 1, .null, sqlText "$[0]", sqlText "$",
    sqlText "[10,{\"x\":1},30]", sqlText "$"],
  [.integer 1, sqlText "{\"x\":1}", sqlText "object", .null, .integer 4, .null, sqlText "$[1]", sqlText "$",
    sqlText "[10,{\"x\":1},30]", sqlText "$"],
  [.integer 2, .integer 30, sqlText "integer", .integer 30, .integer 9, .null, sqlText "$[2]", sqlText "$",
    sqlText "[10,{\"x\":1},30]", sqlText "$"]]
-- The id is the JSONB offset of the label of a member; a 12-byte payload needs a 2-byte header.
#guard column 4 (each mixed none) == some [.integer 2, .integer 6, .integer 13, .integer 17, .integer 20, .integer 23]
#guard column 2 (each mixed none) == some (["integer", "array", "text", "null", "true", "real"].map sqlText)
#guard column 3 (each mixed none) == some [.integer 1, .null, sqlText "s", .null, .integer 1, .real (2.5 : Float).toBits]
-- Header sizes 1, 2, 3 and 5 by payload size: the id of the element after a long string.
#guard column 4 (each "[\"xxxxxxxxxxxx\",1]" none) == some [.integer 2, .integer 16]
#guard column 4 (each ("[\"" ++ String.ofList (List.replicate 256 'x') ++ "\",1]") none) == some [.integer 3, .integer 262]
#guard column 4 (each ("[\"" ++ String.ofList (List.replicate 65536 'x') ++ "\",1]") none) == some [.integer 5, .integer 65546]
-- With a path, the ids are offsets in the whole document and the paths start with the root path.
#guard column 4 (each "{\"a\":{\"b\":[1,2]}}" (some "$.a.b")) == some [.integer 7, .integer 9]
#guard column 6 (each "{\"a\":{\"b\":[1,2]}}" (some "$.a.b")) == some [sqlText "$.a.b[0]", sqlText "$.a.b[1]"]
#guard column 7 (each "{\"a\":{\"b\":[1,2]}}" (some "$.a")) == some [sqlText "$.a"]
-- The root path is printed as given, in fullkey, path and root.
#guard column 6 (each "{\"x\":[5]}" (some "$.\"x\"")) == some [sqlText "$.\"x\"[0]"]
#guard column 9 (each "[1,[2]]" (some "$[#-1]")) == some [sqlText "$[#-1]"]
-- A label is quoted unless it starts with a letter and has only letters and digits.
#guard column 6 (each "{\"_\":1,\"\":2,\"a1\":3,\"a b\":4}" none) ==
  some [sqlText "$.\"_\"", sqlText "$.\"\"", sqlText "$.a1", sqlText "$.\"a b\""]
-- A quoted label keeps its escapes in fullkey; the key is the decoded label.
#guard column 6 (each "{\"a\\\"b\":1}" none) == some [sqlText "$.\"a\\\"b\""]
#guard column 0 (each "{\"a\\\"b\":1}" none) == some [sqlText "a\"b"]
-- Duplicate labels stay, in document order.
#guard column 1 (each "{\"a\":1,\"a\":2}" none) == some [.integer 1, .integer 2]
-- A scalar root: a NULL key, id 0 and fullkey $; through an object member, the id of its label.
#guard givesRows (each "5" none) [[.null, .integer 5, sqlText "integer", .integer 5, .integer 0, .null, sqlText "$",
  sqlText "$", sqlText "5", sqlText "$"]]
#guard column 4 (each "{\"a\":7}" (some "$.a")) == some [.integer 1]
#guard column 6 (each "{\"a\":7}" (some "$.a")) == some [sqlText "$.a"]
-- The json column is the argument text as given, white space included, also for a number.
#guard column 8 (each "[1]  " none) == some [sqlText "[1]  "]
#guard column 8 (eachRows (.integer 42) none) == some [sqlText "42"]
-- No rows for a NULL argument, a NULL path and a path that selects nothing.
#guard givesRows (each "[1]" (some "$.a")) []
#guard givesRows (eachRows (sqlText "[1]") (some .null)) []
#guard givesRows (eachRows .null (some (sqlText "x"))) []
-- Malformed JSON is checked before the path; a path must start with $.
#guard failsWith (eachRows (sqlText "[1") (some .null)) .malformed
#guard failsWith (each "[1]" (some "x")) (.badPath (utf8 "x"))
#guard failsWith (each "[1]" (some "$x")) (.badPath (utf8 "$x"))

end Belay.Sqlite.Json.EachExamples
