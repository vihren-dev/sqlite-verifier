import Belay.Sqlite.Json.ExampleSupport

set_option doc.verso true

/-! Checked examples of JSON structure, paths, arguments, the arrow operators and errors.
Each expected value is the result of the same call in the pinned native SQLite 3.51.0. -/

namespace Belay.Sqlite.Json.PathExamples

open Belay.Sqlite Belay.Sqlite.Json Belay.Sqlite.Json.ExampleSupport

-- Arrays and objects render without white space, as the SQL value too.
#guard givesText (extractRoot "{ \"a\" : [ 1 , 2 ] , \"b\" : { } }") "{\"a\":[1,2],\"b\":{}}"
#guard givesText (arrowValue (sqlText "{\"a\":{\"b\":1}}") (sqlText "a")) "{\"b\":1}"
-- JSON5: comments, unquoted labels, trailing commas, single quotes.
#guard givesText (renderRoot "/* c */ {a: 1, // x\n b: [1,2,],}") "{\"a\":1,\"b\":[1,2]}"
#guard givesText (renderRoot "{'a b': 'x\"y'}") "{\"a b\":\"x\\\"y\"}"
#guard givesText (renderRoot "{$a_1:1, é:2}") "{\"$a_1\":1,\"é\":2}"
#guard givesText (renderRoot "{\\u0061b:1}") "{\"\\u0061b\":1}" && gives (extractAt "{\\u0061b:1}" "$.ab") (.integer 1)
#guard givesText (renderRoot "\u00a0[1\u000b,2]\ufeff") "[1,2]"
-- A label that reads as another value is malformed: inf, null and NaN_ are values.
#guard fails (renderRoot "{inf:1}") .malformed && givesText (renderRoot "{info:1}") "{\"info\":1}"
#guard fails (renderRoot "{NaN_:1}") .malformed && fails (renderRoot "{null:1}") .malformed
#guard fails (renderRoot "{1:1}") .malformed && fails (renderRoot "{a b:1}") .malformed
-- Bad separators are malformed.
#guard fails (renderRoot "[,1]") .malformed && fails (renderRoot "[1,,2]") .malformed
#guard fails (renderRoot "[1 2]") .malformed && fails (renderRoot "{,}") .malformed
-- Text after the value, an unclosed comment and empty text are malformed.
#guard fails (extractRoot "[1] x") .malformed && fails (extractRoot "1 /*") .malformed
#guard fails (extractRoot "") .malformed && fails (extractRoot " ") .malformed
#guard givesText (renderRoot "[1]//x") "[1]"
-- The reader stops at a NUL byte: bytes after it do not count.
#guard gives (extractRoot "1\x00x") (.integer 1) && fails (extractRoot "[1\x00]") .malformed
-- Numbers: leading zeros, a lone sign or point, and a bad exponent are malformed.
#guard fails (extractRoot "01") .malformed && fails (extractRoot "-01") .malformed
#guard fails (extractRoot "1e") .malformed && fails (extractRoot "1.2.3") .malformed
#guard fails (extractRoot "-") .malformed && fails (extractRoot ".") .malformed
#guard fails (extractRoot "1x") .malformed && fails (extractRoot "truex") .malformed
-- Nesting: depth 1000 is accepted, depth 1001 is malformed.
#guard gives (extractAt (String.ofList (List.replicate 1000 '[' ++ List.replicate 1000 ']')) "$[0][0][0]")
  (sqlText (String.ofList (List.replicate 997 '[' ++ List.replicate 997 ']')))
#guard fails (extractRoot (String.ofList (List.replicate 1001 '[' ++ List.replicate 1001 ']'))) .malformed
-- Paths: labels, quoted labels, indexes, [#] and [#-N]; the first duplicate wins.
#guard gives (extractAt "{\"a\":1,\"a\":2}" "$.a") (.integer 1)
#guard gives (extractAt "{\"a b\":5}" "$.\"a b\"") (.integer 5)
#guard gives (extractAt "{\"a\":{\"b\":[10,20]}}" "$.a.b[1]") (.integer 20)
#guard gives (extractAt "[1,2,3]" "$[0]") (.integer 1) && gives (extractAt "[1,2,3]" "$[#-1]") (.integer 3)
#guard gives (extractAt "[1,2,3]" "$[#]") .null && gives (extractAt "[1,2,3]" "$[#-4]") .null
-- Escaped labels compare by character, up to the first decoded NUL.
#guard gives (extractAt "{\"é\":1}" "$.\"\\u00e9\"") (.integer 1)
#guard gives (extractAt "{\"a\\u0000b\":1}" "$.a") (.integer 1)
-- A missing path is NULL; a step that does not fit the node is "not found" first.
#guard gives (extractAt "{\"a\":1}" "$.b") .null && gives (extractAt "1" "$.a[") .null
-- Bad paths: the error has the path text, with single quotes doubled.
#guard fails (extractAt "[1,2,3]" "$[-1]") (.badPath (utf8 "$[-1]"))
#guard fails (extractAt "[1]" "$[0]x") (.badPath (utf8 "$[0]x"))
#guard fails (extractAt "{}" "a") (.badPath (utf8 "a")) && fails (extractAt "{}" "$.") (.badPath (utf8 "$."))
#guard (JsonError.badPath (utf8 "$x'y")).message? == some (utf8 "bad JSON path: '$x''y'")
#guard fails (extract (sqlText "[7]") [.integer 0]) (.badPath (utf8 "0"))
-- Several paths give a JSON array; a missing one is null; a NULL path gives NULL.
#guard givesText (extract (sqlText "{\"a\":1,\"b\":[2]}") [sqlText "$.a", sqlText "$.b", sqlText "$.c"]) "[1,[2],null]"
#guard givesText (extract (sqlText "{\"a\":\"x\"}") [sqlText "$.a", sqlText "$.a"]) "[\"x\",\"x\"]"
#guard gives (extract (sqlText "{\"a\":1}") [sqlText "$.a", .null]) .null
#guard gives (extract (sqlText "{\"a\":1}") [.null, sqlText "bad"]) .null
-- json_extract with one argument is NULL, also for bad JSON; NULL arguments give NULL.
#guard gives (extract (sqlText "x") []) .null
#guard gives (extract .null [sqlText "$"]) .null && gives (extract (sqlText "1") [.null]) .null
#guard fails (extract (sqlText "bad") [.null]) .malformed
-- INTEGER and REAL arguments are read as their text; Inf is 9e999.
#guard gives (extract (.integer 42) [sqlText "$"]) (.integer 42)
#guard gives (extract (.real 0x3ff8000000000000) [sqlText "$"]) (.real 0x3ff8000000000000)
#guard givesText (arrowJson (.integer (-7)) (sqlText "$")) "-7"
#guard givesText (arrowJson (.real 0x7ff0000000000000) (sqlText "$")) "9e999"
#guard givesText (arrowJson (.real 0xfff0000000000000) (sqlText "$")) "-9e999"
-- -> renders JSON; ->> gives the SQL value.
#guard givesText (arrowJson (sqlText "{\"a\":\"x\"}") (sqlText "a")) "\"x\""
#guard givesText (arrowValue (sqlText "{\"a\":\"x\"}") (sqlText "a")) "x"
#guard givesText (arrowJson (sqlText "[1,[2,3]]") (sqlText "$[1]")) "[2,3]"
-- An INTEGER right operand is an index, from the end when negative.
#guard givesText (arrowJson (sqlText "[1,2,3]") (.integer 1)) "2"
#guard givesText (arrowJson (sqlText "[1,2,3]") (.integer (-1))) "3"
#guard gives (arrowValue (sqlText "[1,2]") (.integer 0)) (.integer 1)
-- A bare label, a label with spaces, [N] text and a REAL operand as a label.
#guard givesText (arrowJson (sqlText "{\"a b\":2}") (sqlText "a b")) "2"
#guard givesText (arrowJson (sqlText "[1,[2,3]]") (sqlText "[1]")) "[2,3]"
#guard givesText (arrowJson (sqlText "{\"1.5\":7}") (.real 0x3ff8000000000000)) "7"
#guard fails (arrowJson (sqlText "{\"\":5}") (sqlText "")) (.badPath [])
#guard gives (arrowJson (sqlText "{\"a\":1}") (sqlText "x\"y")) .null
-- The JSON is read before the path: bad JSON with a NULL path is an error.
#guard fails (arrowJson (sqlText "bad") .null) .malformed
-- A BLOB JSON argument is outside the model.
#guard fails (extract (.blob [0x7b, 0x7d]) [sqlText "$"]) .blobArgument

end Belay.Sqlite.Json.PathExamples
