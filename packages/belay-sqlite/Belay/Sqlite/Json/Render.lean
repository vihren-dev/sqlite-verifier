import Belay.Sqlite.Json.Node
import Belay.Sqlite.Json.Bytes

set_option doc.verso true

/-! SQLite's rendering of a JSON node as minified JSON text ({lit}`jsonTranslateBlobToText`
in 3.51.0). Canonical numbers and strings keep their source bytes; JSON5 numbers and
strings become canonical JSON. A node that the reader makes never sets the
{lit}`JSTRING_MALFORMED` flag, so the model has no rendering error. -/

namespace Belay.Sqlite.Json

/-- The lowercase hexadecimal digit of a value below 16. -/
def hexDigitByte (value : Nat) : UInt8 := ("0123456789abcdef".toUTF8.toList).getD value 48

/-- The escape of a control byte ({lit}`jsonAppendControlChar`): {lit}`\b`, {lit}`\t`,
{lit}`\n`, {lit}`\f` and {lit}`\r`, else {lit}`\u00XX` with lowercase digits. -/
def controlEscape (byte : UInt8) : List UInt8 :=
  if byte == 8 then [92, 98] else if byte == 9 then [92, 116] else if byte == 10 then [92, 110]
  else if byte == 12 then [92, 102] else if byte == 13 then [92, 114]
  else [92, 117, 48, 48, hexDigitByte (byte.toNat / 16), hexDigitByte (byte.toNat % 16)]

/-- The body of SQL text quoted as a JSON string ({lit}`jsonAppendString`): a backslash
before {lit}`"` and {lit}`\`, the escape of a control byte, other bytes as they are. -/
def escapeSqlText : List UInt8 → List UInt8
  | [] => []
  | byte :: rest =>
    if byte == 34 || byte == 92 then 92 :: byte :: escapeSqlText rest
    else if byte < 0x20 then controlEscape byte ++ escapeSqlText rest
    else byte :: escapeSqlText rest

/-- The body of a JSON5 string as canonical JSON (the {lit}`JSONB_TEXT5` case): a raw
{lit}`"` and raw control bytes get escapes; {lit}`\'` becomes {lit}`'`; {lit}`\v`,
{lit}`\0` and {lit}`\xXX` become {lit}`\u` escapes; line continuations are removed;
other escapes stay as written. -/
def renderText5Body : List UInt8 → List UInt8
  | [] => []
  | 92 :: 39 :: rest => 39 :: renderText5Body rest
  | 92 :: 118 :: rest => "\\u000b".toUTF8.toList ++ renderText5Body rest
  | 92 :: 120 :: high :: low :: rest => "\\u00".toUTF8.toList ++ [high, low] ++ renderText5Body rest
  | 92 :: 48 :: rest => "\\u0000".toUTF8.toList ++ renderText5Body rest
  | 92 :: 13 :: 10 :: rest => renderText5Body rest
  | 92 :: 13 :: rest => renderText5Body rest
  | 92 :: 10 :: rest => renderText5Body rest
  | 92 :: 0xe2 :: 0x80 :: last :: rest =>
    if last == 0xa8 || last == 0xa9 then renderText5Body rest
    else [92, 0xe2] ++ renderText5Body (0x80 :: last :: rest)
  | 92 :: escape :: rest => [92, escape] ++ renderText5Body rest
  | byte :: rest =>
    if byte == 34 then [92, 34] ++ renderText5Body rest
    else if byte < 0x20 then controlEscape byte ++ renderText5Body rest
    else byte :: renderText5Body rest

/-- Read hexadecimal digits as {lit}`JSONB_INT5` rendering does: the value, and whether
a digit came when the value already used its top four bits. The value wraps at 64
bits; after an overflow the digits do not change it. -/
def hexAccumulate : List UInt8 → UInt64 → Bool → UInt64 × Bool
  | [], value, overflow => (value, overflow)
  | digit :: rest, value, overflow =>
    if value >>> 60 != 0 then hexAccumulate rest value Bool.true
    else hexAccumulate rest (value * 16 + (hexValue digit).toUInt64) overflow

/-- The decimal text of a hexadecimal JSON5 integer (the {lit}`JSONB_INT5` case): the
sign, then the value in decimal, or {lit}`9.0e999` when it has more than 64 bits. -/
def renderInt5 (payload : List UInt8) : List UInt8 :=
  let (sign, digits) : List UInt8 × List UInt8 := match payload with
    | 45 :: rest => ([45], rest.drop 2)
    | rest => ([], rest.drop 2)
  let (value, overflow) := hexAccumulate digits 0 Bool.false
  sign ++ (if overflow then "9.0e999".toUTF8.toList else (toString value.toNat).toUTF8.toList)

/-- The fraction bytes of a JSON5 float with a zero after a point that no digit
follows. -/
def renderFloat5Digits : List UInt8 → List UInt8
  | [] => []
  | 46 :: rest =>
    match rest with
    | next :: _ => if isAsciiDigit next then 46 :: renderFloat5Digits rest else 46 :: 48 :: renderFloat5Digits rest
    | [] => [46, 48]
  | byte :: rest => byte :: renderFloat5Digits rest

/-- The canonical text of a JSON5 float (the {lit}`JSONB_FLOAT5` case): a zero before a
point that starts the number, and a zero after a point that no digit follows. -/
def renderFloat5 (payload : List UInt8) : List UInt8 :=
  let (sign, body) : List UInt8 × List UInt8 := match payload with
    | 45 :: rest => ([45], rest)
    | rest => ([], rest)
  let lead : List UInt8 := match body with
    | 46 :: _ => [48]
    | _ => []
  sign ++ lead ++ renderFloat5Digits body

/-- A string body between double quotes. -/
def quoted (body : List UInt8) : List UInt8 := 34 :: body ++ [34]

mutual
/-- The minified JSON text of a node: the source bytes of canonical numbers and strings,
JSON5 forms made canonical, and arrays and objects without white space. -/
def renderNode : JsonNode → List UInt8
  | .null => "null".toUTF8.toList
  | .true => "true".toUTF8.toList
  | .false => "false".toUTF8.toList
  | .int payload | .float payload => payload
  | .int5 payload => renderInt5 payload
  | .float5 payload => renderFloat5 payload
  | .text payload | .textj payload => quoted payload
  | .text5 payload => quoted (renderText5Body payload)
  | .textraw payload => quoted (escapeSqlText payload)
  | .array items => 91 :: renderItems items ++ [93]
  | .object members => 123 :: renderMembers members ++ [125]

/-- The elements of an array, separated by commas. -/
def renderItems : List JsonNode → List UInt8
  | [] => []
  | [item] => renderNode item
  | item :: rest => renderNode item ++ 44 :: renderItems rest

/-- The members of an object as {lit}`label:value`, separated by commas. -/
def renderMembers : List (JsonNode × JsonNode) → List UInt8
  | [] => []
  | [(label, value)] => renderNode label ++ 58 :: renderNode value
  | (label, value) :: rest => renderNode label ++ 58 :: renderNode value ++ 44 :: renderMembers rest
end

end Belay.Sqlite.Json
