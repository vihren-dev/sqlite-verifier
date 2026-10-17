import Belay.Sqlite.Json.Bytes

set_option doc.verso true

/-! SQLite's decoding of JSON string escapes ({lit}`jsonUnescapeOneChar`,
{lit}`jsonBytesToBypass` and {lit}`sqlite3Utf8ReadLimited` in 3.51.0), its conversion of
an escaped string to SQL text (the {lit}`JSONB_TEXTJ` and {lit}`JSONB_TEXT5` case of
{lit}`jsonReturnFromBlob`) and its comparison of object labels
({lit}`jsonLabelCompare`). -/

namespace Belay.Sqlite.Json

/-- The code point that {lit}`jsonUnescapeOneChar` gives for a bad escape
({lit}`JSON_INVALID_CHAR`). -/
def invalidChar : UInt32 := 0x99999

/-- The payload bits of a UTF-8 lead byte from {lit}`0xc0` up ({lit}`sqlite3Utf8Trans1`). -/
def utf8LeadBits (byte : UInt8) : UInt32 :=
  let index := byte.toNat - 0xc0
  UInt32.ofNat (if index < 32 then index else if index < 48 then index - 32
    else if index < 56 then index - 48 else if index < 60 then index - 56
    else if index < 62 then index - 60 else 0)

/-- Add continuation bytes to a code point while they are {lit}`10xxxxxx` bytes, at most
{lit}`limit` of them: the code point and the number of bytes read. -/
def utf8Continue : Nat → List UInt8 → UInt32 → UInt32 × Nat
  | 0, _, code => (code, 0)
  | limit + 1, byte :: rest, code =>
    if byte &&& 0xc0 == 0x80 then
      let (code, count) := utf8Continue limit rest ((code <<< 6) + (byte &&& 0x3f).toUInt32)
      (code, count + 1)
    else (code, 0)
  | _ + 1, [], code => (code, 0)

/-- Read one UTF-8 character of at most four bytes ({lit}`sqlite3Utf8ReadLimited`): the
code point and the number of bytes, at least one. Bad UTF-8 gives some code point; SQLite
does not check it. -/
def utf8ReadLimited : List UInt8 → UInt32 × Nat
  | [] => (0, 1)
  | byte :: rest =>
    if byte ≥ 0xc0 then
      let (code, count) := utf8Continue 3 rest (utf8LeadBits byte)
      (code, count + 1)
    else (byte.toUInt32, 1)

/-- The value of the four hexadecimal digits at an index of a list. -/
def hex4At (bytes : List UInt8) (index : Nat) : UInt32 :=
  (hexValue (bytes.getD index 0) <<< 12) + (hexValue (bytes.getD (index + 1) 0) <<< 8)
    + (hexValue (bytes.getD (index + 2) 0) <<< 4) + hexValue (bytes.getD (index + 3) 0)

/-- The length of the line continuations at the start of an escape
({lit}`jsonBytesToBypass`): a backslash before a line feed, a carriage return, a carriage
return and a line feed, or U+2028 or U+2029. -/
def bypassLength : List UInt8 → Nat
  | 92 :: 13 :: 10 :: rest => 3 + bypassLength rest
  | 92 :: 13 :: rest => 2 + bypassLength rest
  | 92 :: 10 :: rest => 2 + bypassLength rest
  | 92 :: 0xe2 :: 0x80 :: last :: rest => if last == 0xa8 || last == 0xa9 then 4 + bypassLength rest else 0
  | _ => 0

/-- Decode the escape at the start of {lit}`bytes`, which starts with a backslash and
ends where the string ends ({lit}`jsonUnescapeOneChar`): the code point and the number of
bytes used. A surrogate pair is one code point. After a line continuation, the next
character is the result; at the end of the string it is 0. -/
def unescapeOneChar : Nat → List UInt8 → UInt32 × Nat
  | 0, bytes => (invalidChar, bytes.length)
  | fuel + 1, bytes =>
    let n := bytes.length
    let byteOf := fun index => bytes.getD index 0
    let escape := byteOf 1
    if n < 2 then (invalidChar, n)
    else if escape == 117 then
      if n < 6 then (invalidChar, n)
      else
        let high := hex4At bytes 2
        let low := hex4At bytes 8
        if high &&& 0xfc00 == 0xd800 && n ≥ 12 && byteOf 6 == 92 && byteOf 7 == 117 && low &&& 0xfc00 == 0xdc00 then
          (((high &&& 0x3ff) <<< 10) + (low &&& 0x3ff) + 0x10000, 12)
        else (high, 6)
    else if escape == 98 then (8, 2) else if escape == 102 then (12, 2)
    else if escape == 110 then (10, 2) else if escape == 114 then (13, 2)
    else if escape == 116 then (9, 2) else if escape == 118 then (11, 2)
    else if escape == 48 then (if n > 2 && isAsciiDigit (byteOf 2) then invalidChar else 0, 2)
    else if escape == 39 || escape == 34 || escape == 47 || escape == 92 then (escape.toUInt32, 2)
    else if escape == 120 then
      if n < 4 then (invalidChar, n) else ((hexValue (byteOf 2) <<< 4) ||| hexValue (byteOf 3), 4)
    else if escape == 0xe2 || escape == 13 || escape == 10 then
      let skip := bypassLength bytes
      if skip == 0 then (invalidChar, n)
      else if skip == n then (0, n)
      else if byteOf skip == 92 then
        let (code, used) := unescapeOneChar fuel (bytes.drop skip)
        (code, skip + used)
      else
        let (code, used) := utf8ReadLimited (bytes.drop skip)
        (code, skip + used)
    else (invalidChar, 2)

/-- The UTF-8 bytes that {lit}`jsonReturnFromBlob` writes for a decoded code point: one
to four bytes, and none for {name}`invalidChar`. A lone surrogate gets three bytes. -/
def encodeCodePoint (code : UInt32) : List UInt8 :=
  let byte : UInt32 → UInt8 := UInt32.toUInt8
  let tail : UInt32 → UInt8 := fun shift => byte ((0x80 : UInt32) ||| ((code >>> shift) &&& 0x3f))
  if code ≤ 0x7f then [byte code]
  else if code ≤ 0x7ff then [byte ((0xc0 : UInt32) ||| (code >>> 6)), tail 0]
  else if code < 0x10000 then [byte ((0xe0 : UInt32) ||| (code >>> 12)), tail 6, tail 0]
  else if code == invalidChar then []
  else [byte ((0xf0 : UInt32) ||| (code >>> 18)), tail 12, tail 6, tail 0]

/-- Decode the escapes of a string payload into SQL text; other bytes stay. -/
def decodeEscapes : Nat → List UInt8 → List UInt8
  | 0, _ => []
  | _ + 1, [] => []
  | fuel + 1, 92 :: rest =>
    let (code, used) := unescapeOneChar (rest.length + 1) (92 :: rest)
    encodeCodePoint code ++ decodeEscapes fuel ((92 :: rest).drop used)
  | fuel + 1, byte :: rest => byte :: decodeEscapes fuel rest

/-- The SQL text of an escaped string payload ({lit}`JSONB_TEXTJ`, {lit}`JSONB_TEXT5`). -/
def unescapeString (payload : List UInt8) : List UInt8 := decodeEscapes (payload.length + 1) payload

/-- The next character of a label for comparison: 0 at the end, a decoded escape when
the label has escapes, else a UTF-8 character; also the rest of the label. -/
def labelChar (bytes : List UInt8) (raw : Bool) : UInt32 × List UInt8 :=
  match bytes with
  | [] => (0, [])
  | byte :: rest =>
    if raw || byte != 92 then
      if byte ≥ 0xc0 then let (code, used) := utf8ReadLimited bytes; (code, bytes.drop used)
      else (byte.toUInt32, rest)
    else let (code, used) := unescapeOneChar bytes.length bytes; (code, bytes.drop used)

/-- Compare two labels character by character ({lit}`jsonLabelCompareEscaped`). The
comparison ends at the first code point 0, so a decoded {lit}`\u0000` ends a label. -/
def labelsMatchEscaped : Nat → List UInt8 → Bool → List UInt8 → Bool → Bool
  | 0, _, _, _, _ => Bool.true
  | fuel + 1, left, rawLeft, right, rawRight =>
    let (leftChar, left) := labelChar left rawLeft
    let (rightChar, right) := labelChar right rawRight
    if leftChar != rightChar then Bool.false
    else if leftChar == 0 then Bool.true
    else labelsMatchEscaped fuel left rawLeft right rawRight

/-- Whether two object labels are equal ({lit}`jsonLabelCompare`): byte equality when
neither has escapes, else the comparison of decoded characters. -/
def labelsMatch (left : List UInt8) (rawLeft : Bool) (right : List UInt8) (rawRight : Bool) : Bool :=
  if rawLeft && rawRight then left == right
  else labelsMatchEscaped (left.length + right.length + 1) left rawLeft right rawRight

end Belay.Sqlite.Json
