import Belay.Sqlite.Json.Validity
import Belay.Sqlite.Json.Extract

set_option doc.verso true

/-! The SQL function {lit}`json_valid(json [, flags])` (ADR 0012, amendment 5, slice 6c;
{lit}`jsonValidFunc` in 3.51.0) on TEXT, INTEGER, REAL and NULL arguments. The flags are
bits: 1 accepts RFC 8259 JSON text, 2 also JSON5 text, and 4 and 8 JSONB, which a text
argument never is. The function never fails on malformed JSON; it gives 0. -/

namespace Belay.Sqlite.Json

open Belay.Sqlite

/-- The integer value of the flags argument, as {lit}`sqlite3_value_int64` gives it: an
INTEGER as it is, a REAL truncated toward zero and saturated ({name}`realToI64`), the
leading integer of TEXT or of the bytes of a BLOB ({name}`atoi64`, so {lit}`'1e2'` is 1),
and 0 for NULL. -/
def flagsValue : Value → Int
  | .integer value => value
  | .real bits => realToI64 (Float.ofBits bits)
  | .text bytes | .blob bytes => (atoi64 bytes).1
  | .null => 0

/-- Whether SQLite accepts the flags of {lit}`json_valid`: 1 to 15, the values of its four
flag bits; any other value is the error {lit}`FLAGS parameter to json_valid() must be
between 1 and 15`. -/
def flagsAccepted (flags : Int) : Bool := 1 ≤ flags && flags ≤ 15

/-- Whether a text argument is valid JSON for the flags: false when the flags accept no
text (bits 1 and 2 clear) or the text is malformed; true for standard JSON
({name}`standardJson`); and true for JSON5 text only with bit 2. -/
def textValid (flags : Int) (bytes : List UInt8) : Bool :=
  if flags % 4 == 0 then Bool.false
  else if (parseJsonText bytes).isNone then Bool.false
  else standardJson bytes || flags / 2 % 2 == 1

/-- {lit}`json_valid(json, flags)`: the flags error for flags that SQLite does not accept
({name}`flagsAccepted`), checked first; then NULL for a NULL argument, and 1 or 0 for a text, INTEGER or REAL argument,
read as its text. A BLOB argument is not modelled. -/
def jsonValid (json flags : Value) : Except JsonError Value :=
  let flags := flagsValue flags
  if !flagsAccepted flags then .error .badFlags
  else match json with
    | .null => .ok .null
    | .blob _ => .error .blobArgument
    | .integer _ | .real _ | .text _ =>
      .ok (.integer (if (valueText json).any (textValid flags ·) then 1 else 0))

end Belay.Sqlite.Json
