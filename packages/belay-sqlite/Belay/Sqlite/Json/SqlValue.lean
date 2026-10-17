import Belay.Sqlite.Declarations
import Belay.Sqlite.NumberConvert
import Belay.Sqlite.Json.Render
import Belay.Sqlite.Json.Unescape

set_option doc.verso true

/-! The SQL value of a JSON node ({lit}`jsonReturnFromBlob` in 3.51.0, text mode): an
integer, a REAL by SQLite's own {lit}`sqlite3AtoF`, text with its escapes decoded, or
the JSON text of an array or an object. -/

namespace Belay.Sqlite.Json

open Belay.Sqlite

/-- The digits and the end of a hexadecimal integer after {lit}`0x` and its leading
zeros: the value modulo {lit}`2^64` and the digit count. -/
def hexIntegerDigits : List UInt8 → Nat → Nat → Nat × Nat × List UInt8
  | byte :: rest, value, count =>
    if isHexDigit byte then hexIntegerDigits rest ((value * 16 + (hexValue byte).toNat) % 2 ^ 64) (count + 1)
    else (value, count, byte :: rest)
  | [], value, count => (value, count, [])

/-- SQLite's {lit}`sqlite3DecOrHexToI64`: the signed 64-bit value and the code. The code
is 0 when the integer fits, 1 with text after it, 2 when it is too large and 3 for
{lit}`9223372036854775808`. A hexadecimal integer of 16 digits can give a negative
value; one of more than 16 significant digits has code 2. -/
def decOrHexToI64 (bytes : List UInt8) : Int × Int :=
  match bytes with
  | 48 :: marker :: rest =>
    if marker == 120 || marker == 88 then
      let (value, count, tail) := hexIntegerDigits (rest.dropWhile (· == 48)) 0 0
      let signed : Int := if value ≥ 2 ^ 63 then (value : Int) - 2 ^ 64 else value
      (signed, if count > 16 then 2 else if !tail.isEmpty then 1 else 0)
    else atoi64 bytes
  | _ => atoi64 bytes

/-- The REAL that {lit}`sqlite3AtoF` reads from a whole number payload, or malformed JSON
when the payload is not a whole number. -/
def payloadReal (payload : List UInt8) : Except JsonError Value :=
  let (value, code) := atof payload
  if code ≤ 0 then .error .malformed else .ok (.real value.toBits)

/-- The SQL value of an integer payload (the {lit}`JSONB_INT` and {lit}`JSONB_INT5` case):
an INTEGER when it fits in 64 bits, the smallest integer for
{lit}`-9223372036854775808`, else the REAL of the whole payload. A hexadecimal value with
the top bit set is the unsigned value as a REAL. -/
def integerValue (payload : List UInt8) : Except JsonError Value :=
  let (negative, digits) := match payload with
    | 45 :: rest => (Bool.true, rest)
    | rest => (Bool.false, rest)
  if digits.isEmpty then .error .malformed
  else
    let (value, code) := decOrHexToI64 digits
    if code == 0 then
      if value < 0 then
        let magnitude := (UInt64.ofInt value).toFloat
        .ok (.real (if negative then -magnitude else magnitude).toBits)
      else .ok (.integer (if negative then -value else value))
    else if code == 3 && negative then .ok (.integer (-(2 ^ 63)))
    else if code == 1 then .error .malformed
    else payloadReal payload

/-- The SQL value of a node: NULL, 1 and 0 for the literals, a number, decoded text, or
the minified JSON text of an array or an object. -/
def sqlValueOfNode (node : JsonNode) : Except JsonError Value :=
  match node with
  | .null => .ok .null
  | .true => .ok (.integer 1)
  | .false => .ok (.integer 0)
  | .int payload | .int5 payload => integerValue payload
  | .float payload | .float5 payload => if payload.isEmpty then .error .malformed else payloadReal payload
  | .text payload | .textraw payload => .ok (.text payload)
  | .textj payload | .text5 payload => .ok (.text (unescapeString payload))
  | .array _ | .object _ => .ok (.text (renderNode node))

end Belay.Sqlite.Json
