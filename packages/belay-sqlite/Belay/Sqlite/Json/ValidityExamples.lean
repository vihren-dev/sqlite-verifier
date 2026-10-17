import Belay.Sqlite.Json.Validity
import Belay.Sqlite.Json.ExampleSupport

set_option doc.verso true

/-! Checked examples of {lit}`json_valid(X)` with the default flags. Each expected value
is the result of {lit}`json_valid(CAST(X'..' AS TEXT))` in the pinned native SQLite
3.51.0. A {lit}`#guard` with {lit}`!` is a text that SQLite reads but marks as JSON5, or
a text that it does not read. -/

namespace Belay.Sqlite.Json.ValidityExamples

open Belay.Sqlite.Json Belay.Sqlite.Json.ExampleSupport

-- Canonical JSON with the four JSON space bytes passes.
#guard standardJson (utf8 "{\"a\":[1,-2.5e3,true,null],\"b\":{}}")
#guard standardJson (utf8 " \t\r\n[ 1 , \"x\" ] \n")
#guard standardJson (utf8 "\"it's\"") && standardJson (utf8 "\"\\/\\b\\f\\n\\r\\t\\\"\\\\\"")
-- Any four-digit escape passes, also a lone surrogate.
#guard standardJson (utf8 "\"\\uD800\"") && standardJson (utf8 "\"\\u00e9\"")
-- Bytes from 0x7f up pass as they are, also invalid UTF-8.
#guard standardJson [0x22, 0x7f, 0xff, 0xc3, 0x22]
-- Large numbers pass: they are canonical JSON.
#guard standardJson (utf8 "1E400") && standardJson (utf8 "123456789012345678901234567890")
-- The text stops at the first NUL byte.
#guard standardJson [0x31, 0x00, 0x78]
#guard !standardJson [0x00, 0x31]
#guard !standardJson [] && !standardJson (utf8 " ")
-- Leading zeros and incomplete numbers are malformed.
#guard !standardJson (utf8 "01") && !standardJson (utf8 "-01")
#guard !standardJson (utf8 "1e") && !standardJson (utf8 "-")
-- JSON5 numbers: a point with no digit on one side, a plus sign, hexadecimal.
#guard !standardJson (utf8 "1.") && !standardJson (utf8 ".1") && !standardJson (utf8 "1.e5")
#guard !standardJson (utf8 "+1") && !standardJson (utf8 "0x1F")
-- JSON5 names of infinity and NaN.
#guard !standardJson (utf8 "Infinity") && !standardJson (utf8 "-inf") && !standardJson (utf8 "NaN")
-- JSON5 white space: vertical tab, form feed, U+00A0 and U+FEFF.
#guard !standardJson (utf8 "\x0b1") && !standardJson (utf8 "1\x0c")
#guard !standardJson (utf8 "\u00a01") && !standardJson (utf8 "\ufeff[]")
-- Comments of both kinds, before, inside and after the value.
#guard !standardJson (utf8 "/**/1") && !standardJson (utf8 "[1//x\n]")
#guard !standardJson (utf8 "{\"a\":1}/* c */")
-- Trailing commas; an empty container is canonical.
#guard !standardJson (utf8 "[1,]") && !standardJson (utf8 "{\"a\":1,}")
#guard standardJson (utf8 "[ ]") && standardJson (utf8 "{ }")
-- Unquoted and single-quoted labels and strings.
#guard !standardJson (utf8 "{a:1}") && !standardJson (utf8 "{'a':1}") && !standardJson (utf8 "'a'")
-- JSON5 escapes.
#guard !standardJson (utf8 "\"\\x41\"") && !standardJson (utf8 "\"\\v\"") && !standardJson (utf8 "\"\\0\"")
#guard !standardJson (utf8 "\"\\'\"") && !standardJson (utf8 "\"\\\n\"")
-- A bad escape is malformed.
#guard !standardJson (utf8 "\"\\u12g4\"") && !standardJson (utf8 "\"\\a\"")
-- A raw control byte in a string is JSON5; a raw tab too.
#guard !standardJson (utf8 "\"a\x01b\"") && !standardJson (utf8 "\"\t\"")
-- The depth limit is 1000 arrays or objects.
#guard standardJson (List.replicate 1000 (91 : UInt8) ++ List.replicate 1000 93)
#guard !standardJson (List.replicate 1001 (91 : UInt8) ++ List.replicate 1001 93)
-- A literal must be the whole word.
#guard !standardJson (utf8 "truex") && !standardJson (utf8 "[1 2]")

end Belay.Sqlite.Json.ValidityExamples
