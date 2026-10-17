import Belay.Sqlite.Json.Read

set_option doc.verso true

/-! The test of {lit}`json_valid(X)` with the default flags 1 in SQLite 3.51.0
({lit}`jsonValidFunc`). SQLite reads the text with {lit}`jsonConvertTextToBlob`. The
result is 1 only when the read succeeds and {lit}`pParse->hasNonstd` stays false. The
reader of {lit}`jsonTranslateTextToBlob` sets that flag on every JSON5 form it meets.
So a text passes when SQLite reads it and it is also canonical JSON (RFC 8259) with
SQLite's four space bytes. This module gives a recognizer of canonical JSON. It does
not check the depth limit; {lit}`standardJson` takes that from the reader. -/

namespace Belay.Sqlite.Json

/-- The first position at or after {lit}`position` that is not a JSON space byte.
SQLite skips these bytes without the JSON5 flag ({lit}`jsonIsspace`, {lit}`jsonSpaces`);
all other white space and comments go through {lit}`json5Whitespace` and set it. -/
def canonicalSpaceEnd (text : Array UInt8) : Nat → Nat → Nat
  | 0, position => position
  | fuel + 1, position =>
    if isJsonSpace (byteAt text position) then canonicalSpaceEnd text fuel (position + 1) else position

/-- The first position at or after {lit}`position` that is not an ASCII digit. -/
def digitsEnd (text : Array UInt8) : Nat → Nat → Nat
  | 0, position => position
  | fuel + 1, position =>
    if isAsciiDigit (byteAt text position) then digitsEnd text fuel (position + 1) else position

/-- The position after one or more digits at {lit}`position`, or {lit}`none` when
there is no digit there. -/
def someDigitsEnd (text : Array UInt8) (position : Nat) : Option Nat :=
  let stop := digitsEnd text (text.size + 1) position
  if stop > position then some stop else none

/-- The position after a canonical number at {lit}`start`: an optional minus, then
{lit}`0` or a digit run that does not start with {lit}`0`, an optional point with
digits, and an optional exponent with digits. SQLite sets the JSON5 flag for a leading
{lit}`+`, a point with no digit on one side, hexadecimal digits, and the names of
infinity ({lit}`parse_number` of {lit}`jsonTranslateTextToBlob`). -/
def canonicalNumberEnd (text : Array UInt8) (start : Nat) : Option Nat := do
  let first := if byteAt text start == 45 then start + 1 else start
  let afterInteger ← if byteAt text first == 48 then some (first + 1) else someDigitsEnd text first
  let afterFraction ←
    if byteAt text afterInteger == 46 then someDigitsEnd text (afterInteger + 1) else some afterInteger
  let marker := byteAt text afterFraction
  if marker == 101 || marker == 69 then
    let sign := byteAt text (afterFraction + 1)
    someDigitsEnd text (if sign == 43 || sign == 45 then afterFraction + 2 else afterFraction + 1)
  else some afterFraction

/-- Whether a string escape at {lit}`position` (the byte after the backslash) is
canonical: one of {lit}`"\/bfnrt`, or {lit}`u` with four hexadecimal digits. Any
{lit}`\uXXXX` passes, also a lone surrogate. The JSON5 escapes {lit}`\'`, {lit}`\v`,
{lit}`\0`, {lit}`\xXX` and line continuations set the flag ({lit}`parse_string`). -/
def isCanonicalEscape (text : Array UInt8) (position : Nat) : Bool :=
  let escape := byteAt text position
  escape == 34 || escape == 92 || escape == 47 || escape == 98 || escape == 102
    || escape == 110 || escape == 114 || escape == 116
    || (escape == 117 && hasHexDigits text (position + 1) 4)

/-- The position after the closing double quote of a string body that starts at
{lit}`position`. Each byte is a byte of {name}`isJsonOk`, a single quote or a canonical
escape. A raw control byte sets the JSON5 flag in SQLite, so it fails here; bytes from
0x7f up pass as they are, also when they are not valid UTF-8. -/
def canonicalStringEnd (text : Array UInt8) : Nat → Nat → Option Nat
  | 0, _ => none
  | fuel + 1, position =>
    let byte := byteAt text position
    if byte == 34 then some (position + 1)
    else if isJsonOk byte || byte == 39 then canonicalStringEnd text fuel (position + 1)
    else if byte == 92 && isCanonicalEscape text (position + 1) then
      let width := if byteAt text (position + 1) == 117 then 6 else 2
      canonicalStringEnd text fuel (position + width)
    else none

/-- The position after a literal at {lit}`start` when the text there is exactly the
word. SQLite also reads the JSON5 names {lit}`Infinity` and {lit}`NaN` here and sets the
flag for them. -/
def wordEnd (text : Array UInt8) (start : Nat) (word : String) : Option Nat :=
  let bytes := word.toUTF8.toList
  if matchesExactly text start bytes then some (start + bytes.length) else none

mutual
/-- The position after a canonical value that starts at {lit}`position`, after JSON
space bytes. An array or object goes to {lit}`canonicalElementsEnd`. -/
def canonicalValueEnd (text : Array UInt8) : Nat → Nat → Option Nat
  | 0, _ => none
  | fuel + 1, position =>
    let start := canonicalSpaceEnd text (text.size + 1) position
    let byte := byteAt text start
    if byte == 91 then canonicalElementsEnd text fuel (start + 1) 93
    else if byte == 123 then canonicalElementsEnd text fuel (start + 1) 125
    else if byte == 34 then canonicalStringEnd text (text.size + 1) (start + 1)
    else if byte == 45 || isAsciiDigit byte then canonicalNumberEnd text start
    else if byte == 116 then wordEnd text start "true"
    else if byte == 102 then wordEnd text start "false"
    else if byte == 110 then wordEnd text start "null"
    else none

/-- The position after the elements and the closing {lit}`closer` of an array
({lit}`]`) or object ({lit}`}`) whose opening byte ends before {lit}`position`. An empty
container closes at once. SQLite sets the JSON5 flag when the closer follows a comma
({lit}`pParse->nBlob!=iStart`), so a trailing comma fails here. -/
def canonicalElementsEnd (text : Array UInt8) : Nat → Nat → UInt8 → Option Nat
  | 0, _, _ => none
  | fuel + 1, position, closer =>
    let start := canonicalSpaceEnd text (text.size + 1) position
    if byteAt text start == closer then some (start + 1) else canonicalMemberEnd text fuel start closer

/-- The position after one element at {lit}`position`, the elements after it and the
closing {lit}`closer`. An object element is a double-quoted label, a colon and a
value; unquoted and single-quoted labels are JSON5 in SQLite. -/
def canonicalMemberEnd (text : Array UInt8) : Nat → Nat → UInt8 → Option Nat
  | 0, _, _ => none
  | fuel + 1, position, closer =>
    let afterElement : Option Nat :=
      if closer == 125 then
        let labelStart := canonicalSpaceEnd text (text.size + 1) position
        if byteAt text labelStart != 34 then none
        else
          match canonicalStringEnd text (text.size + 1) (labelStart + 1) with
          | none => none
          | some afterLabel =>
            let colon := canonicalSpaceEnd text (text.size + 1) afterLabel
            if byteAt text colon == 58 then canonicalValueEnd text fuel (colon + 1) else none
      else canonicalValueEnd text fuel position
    match afterElement with
    | none => none
    | some after =>
      let separator := canonicalSpaceEnd text (text.size + 1) after
      let byte := byteAt text separator
      if byte == 44 then canonicalMemberEnd text fuel (separator + 1) closer
      else if byte == closer then some (separator + 1)
      else none
end

/-- The bytes of a text up to its first NUL byte. SQLite reads the JSON text as a C
string, so the reader stops at the first NUL. -/
def bytesBeforeNul (bytes : List UInt8) : List UInt8 := bytes.takeWhile (· != 0)

/-- Whether a text is one canonical JSON value with only JSON space bytes around it,
read up to the first NUL byte. After the value, {lit}`jsonConvertTextToBlob` sets the
JSON5 flag for any other white space or comment. -/
def canonicalJsonText (bytes : List UInt8) : Bool :=
  let text := (bytesBeforeNul bytes).toArray
  match canonicalValueEnd text (4 * text.size + 8) 0 with
  | some after => canonicalSpaceEnd text (text.size + 1) after == text.size
  | none => Bool.false

/-- Whether SQLite's reader accepts the text and meets no JSON5 form on the way:
{lit}`json_valid(text)` (flags 1) is 1 exactly when this is true. The reader part is
{name}`parseJsonText`, which also applies the depth limit {name}`maxDepth`; the JSON5
part is {name}`canonicalJsonText`. -/
def standardJson (bytes : List UInt8) : Bool :=
  (parseJsonText bytes).isSome && canonicalJsonText bytes

end Belay.Sqlite.Json
