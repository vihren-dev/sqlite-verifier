import Belay.Sqlite.Grammar
import Belay.Sqlite.ParseTree
import Belay.Sqlite.Translation
import Belay.Sqlite.Model.Codec.SyntaxJson

set_option doc.verso true

/-! The requests and answers of the translation program ({lit}`TranslationProgram.lean`), which
the conformance harness runs over a batch of SQL texts. A request is one JSON line with the
execution profile's release, a source name and the SQL text as hexadecimal bytes. The answer is
one JSON line, whose {lit}`result` tells which of these it is:

* {lit}`statements`: the statements, each with its value in the model's transport and its byte
  range, and the commands that the grammar found;
* {lit}`translationRefusal`: the translation's refusal, and the commands;
* {lit}`parseRefusal` or {lit}`limit`: the refusal of a text that SQLite's grammar rejects, or
  that exceeds the parser's limits;
* {lit}`noParser`: the parser library has no grammar for the profile.

A refusal has the status, the message, the source name and the range of the Python frontend's
diagnostic. The commands are what the harness's query diagnostic reads: the symbols of each
command's parts and the text of each {lit}`nm` part, or {lit}`null` when the grammar found a wrapper
such as EXPLAIN. -/

namespace Belay.Sqlite.TranslationRequest

open Belay.Sqlite.Model Belay.Sqlite.Translation Lean

/-- One request: the release whose grammar parses the text, the source name of the refusals and
the SQL text as bytes. -/
structure Request where
  /-- The release, the build and the compile options of the execution profile. -/
  release : Release
  /-- The name of the text in a refusal, for example {lit}`corpus-migration.sql`. -/
  source : String
  /-- The SQL text as bytes, which need not be UTF-8. -/
  sql : ByteArray

/-- The value of one hexadecimal digit, in lowercase or uppercase. -/
def hexDigit (digit : Char) : Except String UInt8 :=
  if '0' ≤ digit && digit ≤ '9' then pure (digit.toNat - '0'.toNat).toUInt8
  else if 'a' ≤ digit && digit ≤ 'f' then pure (digit.toNat - 'a'.toNat + 10).toUInt8
  else if 'A' ≤ digit && digit ≤ 'F' then pure (digit.toNat - 'A'.toNat + 10).toUInt8
  else throw s!"the character {repr digit} is not a hexadecimal digit"

/-- The bytes of a hexadecimal text, two digits for each byte. -/
def decodeHex (text : String) : Except String ByteArray := do
  let digits := text.toList.toArray
  unless digits.size % 2 == 0 do throw "the hexadecimal SQL has an odd number of digits"
  let mut bytes := ByteArray.emptyWithCapacity (digits.size / 2)
  for index in [0:digits.size / 2] do
    bytes := bytes.push ((← hexDigit digits[2 * index]!) * 16 + (← hexDigit digits[2 * index + 1]!))
  return bytes

/-- One request line: an object with {lit}`profile` ({lit}`version`, {lit}`sourceId` and
{lit}`compileOptions`), {lit}`source` and {lit}`sqlHex`. -/
def decodeRequest (line : String) : Except String Request := do
  let json ← Json.parse line
  let profile ← json.getObjVal? "profile"
  let release : Release := { version := ← profile.getObjValAs? String "version",
                             sourceId := ← profile.getObjValAs? String "sourceId",
                             compileOptions := ← profile.getObjValAs? (List String) "compileOptions" }
  return { release, source := ← json.getObjValAs? String "source", sql := ← decodeHex (← json.getObjValAs? String "sqlHex") }

/-- The symbols of a command's parts and the text of each {lit}`nm` part, such as a PRAGMA's name. -/
def commandJson (tree : SqlTree) (command : ParseNode) : Json :=
  let parts := tree.children command
  Json.mkObj [("symbols", toJson (parts.map (·.symbol))),
    ("names", toJson ((parts.filter (·.symbol == "nm")).map tree.text))]

/-- A statement's value in the model's transport and its byte range. -/
def statementJson (item : Located Syntax.Statement) : Json :=
  Json.mkObj [("value", toJson item.value), ("start", item.span.start), ("end", item.span.stop)]

/-- An answer with a refusal. -/
def refusalAnswer (result : String) (refusal : Refusal) (source : String) (more : List (String × Json) := []) : Json :=
  Json.mkObj ([("result", toJson result), ("refusal", refusal.toJson source)] ++ more)

/-- The answer for a parse result of the request's text. -/
def answer (request : Request) : ParseResult → Json
  | .inputError offset => refusalAnswer "parseRefusal" (inputError offset) request.source
  | .resourceLimit offset => refusalAnswer "limit" (resourceLimit offset) request.source
  | .parsed nodes root =>
    let tree : SqlTree := { sql := request.sql, nodes }
    let found := match (commands tree root).run' {} with
      | .ok items => toJson (items.map (commandJson tree))
      | .error _ => Json.null
    match (statements tree root).run' {} with
    | .ok items => Json.mkObj [("result", "statements"), ("statements", toJson (items.map (statementJson ·.statement))),
        ("commands", found)]
    | .error refusal => refusalAnswer "translationRefusal" refusal request.source [("commands", found)]

/-- The answer for a profile whose release has no grammar in the library, with the reason and
what the user can do ({name}`selectGrammar`). -/
def noParserAnswer (message : String) : Json :=
  Json.mkObj [("result", "noParser"), ("message", toJson message)]

/-- The answer for a request that the program cannot answer: a malformed line, or a parse document
of the library that is not usable. -/
def errorAnswer (message : String) : Json :=
  Json.mkObj [("result", "error"), ("message", toJson message)]

end Belay.Sqlite.TranslationRequest
