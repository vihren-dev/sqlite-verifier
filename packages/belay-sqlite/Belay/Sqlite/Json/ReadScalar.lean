import Belay.Sqlite.Json.Bytes
import Belay.Sqlite.Json.Node

set_option doc.verso true

/-! The scalar part of SQLite's JSON reader ({lit}`jsonTranslateTextToBlob` in 3.51.0):
strings, numbers, the literals and the JSON5 names of infinity and NaN. Each reader
starts at a position of the text and gives the node and the position after it. -/

namespace Belay.Sqlite.Json

/-- The escape class of a string so far. SQLite gives a string the type of its
strongest escape: none, canonical JSON escapes, or JSON5 escapes. -/
inductive StringKind where
  /-- No escapes: {lit}`JSONB_TEXT`. -/
  | plain
  /-- Canonical JSON escapes only: {lit}`JSONB_TEXTJ`. -/
  | json
  /-- A JSON5 escape, a raw control byte or a raw double quote: {lit}`JSONB_TEXT5`. -/
  | json5

/-- The string node of an escape class and a payload. -/
def StringKind.node : StringKind → List UInt8 → JsonNode
  | .plain, payload => .text payload
  | .json, payload => .textj payload
  | .json5, payload => .text5 payload

/-- The class after a canonical JSON escape: a plain string becomes {lit}`json`, and a
JSON5 string stays JSON5. -/
def StringKind.withJsonEscape : StringKind → StringKind
  | .plain => .json
  | .json => .json
  | .json5 => .json5

/-- The bytes of the text from {lit}`start` up to, not including, {lit}`stop`. -/
def slice (text : Array UInt8) (start stop : Nat) : List UInt8 :=
  (List.range (stop - start)).map fun offset => byteAt text (start + offset)

/-- Scan a string body from {lit}`position` to the closing {lit}`delimiter`: the position
of the delimiter and the escape class, or {lit}`none` for a syntax error. The escapes are
those of the reader: canonical {lit}`\"`, {lit}`\\`, {lit}`\/`, {lit}`\b`, {lit}`\f`,
{lit}`\n`, {lit}`\r`, {lit}`\t` and {lit}`\uXXXX`; JSON5 {lit}`\'`, {lit}`\v`, {lit}`\0`
not before a digit, {lit}`\xXX` and line continuations. A NUL byte is an error. -/
def scanString (text : Array UInt8) (delimiter : UInt8) : Nat → Nat → StringKind → Option (Nat × StringKind)
  | 0, _, _ => none
  | fuel + 1, position, kind =>
    let byte := byteAt text position
    if isJsonOk byte then scanString text delimiter fuel (position + 1) kind
    else if byte == delimiter then some (position, kind)
    else if byte == 92 then
      let escape := byteAt text (position + 1)
      let after := byteAt text (position + 2)
      if escape == 34 || escape == 92 || escape == 47 || escape == 98 || escape == 102
          || escape == 110 || escape == 114 || escape == 116
          || (escape == 117 && hasHexDigits text (position + 2) 4) then
        scanString text delimiter fuel (position + 2) kind.withJsonEscape
      else if escape == 39 || escape == 118 || escape == 10 || (escape == 48 && !isAsciiDigit after)
          || (escape == 0xe2 && after == 0x80
              && (byteAt text (position + 3) == 0xa8 || byteAt text (position + 3) == 0xa9))
          || (escape == 120 && hasHexDigits text (position + 2) 2) then
        scanString text delimiter fuel (position + 2) .json5
      else if escape == 13 then
        scanString text delimiter fuel (if after == 10 then position + 3 else position + 2) .json5
      else none
    else if byte == 0 then none
    else if byte ≤ 0x1f || byte == 34 then scanString text delimiter fuel (position + 1) .json5
    else scanString text delimiter fuel (position + 1) kind

/-- Read a string that starts with its delimiter at {lit}`position`: the node and the
position after the closing delimiter. -/
def readString (text : Array UInt8) (position : Nat) : Option (JsonNode × Nat) :=
  match scanString text (byteAt text position) (text.size + 1) (position + 1) .plain with
  | some (close, kind) => some (kind.node (slice text (position + 1) close), close + 1)
  | none => none

/-- The first position at or after {lit}`position` that is not a hexadecimal digit. -/
def hexDigitsEnd (text : Array UInt8) : Nat → Nat → Nat
  | 0, position => position
  | fuel + 1, position =>
    if isHexDigit (byteAt text position) then hexDigitsEnd text fuel (position + 1) else position

/-- Whether the byte before an exponent or the end of a number is a point after a
digit, which JSON5 allows. {lit}`start` is the first byte of the number. -/
def pointAfterDigit (text : Array UInt8) (start position : Nat) : Bool :=
  byteAt text (position - 1) == 46 && position ≥ start + 2 && isAsciiDigit (byteAt text (position - 2))

/-- Scan the digits, the point and the exponent of a decimal number from
{lit}`position` ({lit}`parse_number_2`). {lit}`flags` has bit 1 for JSON5 and bit 2 for a
fraction or an exponent. The result is the end position and the flags, or {lit}`none`
for a syntax error. -/
def scanDecimal (text : Array UInt8) (start : Nat) : Nat → Nat → Nat → Bool → Option (Nat × Nat)
  | 0, _, _, _ => none
  | fuel + 1, position, flags, seenExponent =>
    let byte := byteAt text position
    let finishFlags : Option Nat :=
      if byteAt text (position - 1) < 48 then
        (if pointAfterDigit text start position then some (flags ||| 1) else none)
      else some flags
    if isAsciiDigit byte then scanDecimal text start fuel (position + 1) flags seenExponent
    else if byte == 46 then
      if flags &&& 2 != 0 then none else scanDecimal text start fuel (position + 1) (flags ||| 2) seenExponent
    else if byte == 101 || byte == 69 then
      match finishFlags with
      | none => none
      | some flags =>
        if seenExponent then none
        else
          let sign := byteAt text (position + 1)
          let position := if sign == 43 || sign == 45 then position + 1 else position
          if isAsciiDigit (byteAt text (position + 1)) then
            scanDecimal text start fuel (position + 1) (flags ||| 2) Bool.true
          else none
    else finishFlags.map fun flags => (position, flags)

/-- The node of a number from its start, its end and its flags (bit 1 JSON5, bit 2
float); a leading plus sign is not part of the payload. -/
def numberNode (text : Array UInt8) (start stop flags : Nat) : JsonNode :=
  let first := if byteAt text start == 43 then start + 1 else start
  let payload := slice text first stop
  if flags == 0 then .int payload else if flags == 1 then .int5 payload
  else if flags == 2 then .float payload else .float5 payload

/-- Read a decimal number whose digits start after {lit}`start`. -/
def readDecimal (text : Array UInt8) (start flags : Nat) : Option (JsonNode × Nat) :=
  (scanDecimal text start (text.size + 1) (start + 1) flags Bool.false).map fun (stop, flags) =>
    (numberNode text start stop flags, stop)

/-- Read a hexadecimal JSON5 integer whose digits start at {lit}`digits`. -/
def readHex (text : Array UInt8) (start digits : Nat) : Option (JsonNode × Nat) :=
  let stop := hexDigitsEnd text (text.size + 1) digits
  some (numberNode text start stop 1, stop)

/-- Read a number that starts with a sign at {lit}`start`: a JSON5 infinity, a fraction
without leading digits, a hexadecimal integer or a decimal number. -/
def readSignedNumber (text : Array UInt8) (start : Nat) : Option (JsonNode × Nat) :=
  let next := byteAt text (start + 1)
  if !isAsciiDigit next then
    if (next == 73 || next == 105) && matchesIgnoringCase text (start + 1) "inf".toUTF8.toList then
      let payload := if byteAt text start == 45 then "-9e999" else "9e999"
      let length := if matchesIgnoringCase text (start + 4) "inity".toUTF8.toList then 9 else 4
      some (.float payload.toUTF8.toList, start + length)
    else if next == 46 then readDecimal text start 1
    else none
  else if next == 48 then
    let after := byteAt text (start + 2)
    if isAsciiDigit after then none
    else if (after == 120 || after == 88) && isHexDigit (byteAt text (start + 3)) then readHex text start (start + 4)
    else readDecimal text start 0
  else readDecimal text start 0

/-- Read a number at {lit}`start` (the {lit}`parse_number` case of the reader). A leading
zero is not followed by a digit; {lit}`0x` starts a hexadecimal integer. -/
def readNumber (text : Array UInt8) (start : Nat) : Option (JsonNode × Nat) :=
  let byte := byteAt text start
  if byte == 46 then
    if isAsciiDigit (byteAt text (start + 1)) then readDecimal text start 3 else none
  else if byte == 43 || byte == 45 then readSignedNumber text start
  else if byte == 48 then
    let next := byteAt text (start + 1)
    if (next == 120 || next == 88) && isHexDigit (byteAt text (start + 2)) then readHex text start (start + 3)
    else if isAsciiDigit next then none
    else readDecimal text start 0
  else readDecimal text start 0

/-- The extra names of the reader ({lit}`aNanInfName`), in SQLite's order: the name and
whether it is an infinity. The names match with case ignored. -/
def specialNames : List (List UInt8 × Bool) :=
  [("inf", Bool.true), ("infinity", Bool.true), ("nan", Bool.false), ("qnan", Bool.false), ("snan", Bool.false)].map
    fun (name, isInfinity) => (name.toUTF8.toList, isInfinity)

/-- Read a literal at {lit}`start`: {lit}`true`, {lit}`false` or {lit}`null` not followed
by a letter or digit, else the first name of {name}`specialNames` that matches and is
not followed by a letter or digit. An infinity is the float {lit}`9e999`; a NaN is null. -/
def readLiteral (text : Array UInt8) (start : Nat) : Option (JsonNode × Nat) :=
  let keyword (word : String) (node : JsonNode) : Option (JsonNode × Nat) :=
    let bytes := word.toUTF8.toList
    if matchesExactly text start bytes && !isAsciiAlnum (byteAt text (start + bytes.length)) then
      some (node, start + bytes.length)
    else none
  let special : Option (JsonNode × Nat) :=
    (specialNames.find? fun (name, _) =>
      matchesIgnoringCase text start name && !isAsciiAlnum (byteAt text (start + name.length))).map
      fun (name, isInfinity) => (if isInfinity then .float "9e999".toUTF8.toList else .null, start + name.length)
  match byteAt text start with
  | 116 => keyword "true" .true
  | 102 => keyword "false" .false
  | 110 => (keyword "null" .null).orElse fun _ => special
  | _ => special

end Belay.Sqlite.Json
