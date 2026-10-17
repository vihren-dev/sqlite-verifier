import Belay.Sqlite.Json.ExampleSupport
import Belay.Sqlite.Json.Functions
import Belay.Sqlite.Json.Valid

set_option doc.verso true

/-! Checked examples of {lit}`json_type`, {lit}`json_array_length`, {lit}`json` and
{lit}`json_valid` (ADR 0012, amendment 5, slice 6c). Each result was checked on native
SQLite 3.51.0, one statement per line. -/

namespace Belay.Sqlite.Json.FunctionExamples

open Belay.Sqlite Belay.Sqlite.Json Belay.Sqlite.Json.ExampleSupport

/-- {lit}`json_type(json, path)` on TEXT arguments. -/
def typeAt (json path : String) : Except JsonError Value := jsonType (sqlText json) (some (sqlText path))

-- Each type name; a number without a fraction or an exponent is an integer at any size.
#guard givesText (jsonType (sqlText "{\"a\":[1]}") none) "object"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[0]") "integer"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[1]") "real"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[2]") "text"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[3]") "true"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[4]") "false"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[5]") "null"
#guard givesText (typeAt "[1,2.5,\"x\",true,false,null,[]]" "$[6]") "array"
#guard givesText (jsonType (sqlText "9223372036854775808") none) "integer"
#guard givesText (jsonType (sqlText "0x1F") none) "integer"
#guard givesText (jsonType (sqlText "1e400") none) "real"
#guard givesText (jsonType (.integer 12) none) "integer"
#guard givesText (jsonType (.real (1.5 : Float).toBits) none) "real"
-- NULL for a missing path, a NULL argument and a NULL path; the errors of slice 6b.
#guard gives (typeAt "{\"a\":1}" "$.b") .null
#guard gives (jsonType .null none) .null
#guard gives (jsonType (sqlText "[1]") (some .null)) .null
#guard fails (jsonType (sqlText "{bad") none) .malformed
#guard fails (typeAt "[1]" "x") (.badPath (utf8 "x"))

-- The length of an array, and 0 for every other value.
#guard gives (jsonArrayLength (sqlText "[1,2,3]") none) (.integer 3)
#guard gives (jsonArrayLength (sqlText "{\"a\":1}") none) (.integer 0)
#guard gives (jsonArrayLength (sqlText "1") none) (.integer 0)
#guard gives (jsonArrayLength (sqlText "{\"a\":[1,2]}") (some (sqlText "$.a"))) (.integer 2)
#guard gives (jsonArrayLength (sqlText "[1]") (some (sqlText "$.x"))) .null

-- json: no white space, numbers and escapes as written, JSON5 normalized, duplicates kept.
#guard givesText (jsonText (sqlText " { \"a\" : [1, 2.50] } ")) "{\"a\":[1,2.50]}"
#guard givesText (jsonText (sqlText "{a:0x1F, b:.5,}")) "{\"a\":31,\"b\":0.5}"
#guard givesText (jsonText (sqlText "[\"x\\u0041\"]")) "[\"x\\u0041\"]"
#guard givesText (jsonText (sqlText "{\"a\":1,\"a\":2}")) "{\"a\":1,\"a\":2}"
#guard givesText (jsonText (sqlText "[Infinity,NaN,-0,1E400]")) "[9e999,null,-0,1E400]"
#guard gives (jsonText .null) .null
#guard fails (jsonText (sqlText "{bad")) .malformed

-- json_valid: the flags are the integer value of the argument; 1 to 15 only.
#guard flagsValue (sqlText "1e2") == 1 && flagsValue (sqlText " 2x") == 2 && flagsValue (sqlText "+3") == 3
#guard flagsValue (.real (15.9 : Float).toBits) == 15 && flagsValue .null == 0
#guard fails (jsonValid (sqlText "[1]") (.integer 0)) .badFlags
#guard fails (jsonValid (sqlText "[1]") (.integer 16)) .badFlags
#guard fails (jsonValid .null .null) .badFlags
#guard fails (jsonValid (sqlText "[1]") (sqlText "0x2")) .badFlags
-- Malformed text is 0, never an error; flags 4 and 8 accept no text; NULL gives NULL.
#guard gives (jsonValid (sqlText "{bad") (.integer 1)) (.integer 0)
#guard gives (jsonValid (sqlText "[1]") (.integer 4)) (.integer 0)
#guard gives (jsonValid (sqlText "[1]") (.integer 5)) (.integer 1)
#guard gives (jsonValid .null (.integer 2)) .null
#guard gives (jsonValid (.integer 12) (.integer 1)) (.integer 1)
-- JSON5 text needs flag 2.
#guard gives (jsonValid (sqlText "{a:1}") (.integer 2)) (.integer 1)
#guard gives (jsonValid (sqlText "{a:1}") (.integer 10)) (.integer 1)

end Belay.Sqlite.Json.FunctionExamples
