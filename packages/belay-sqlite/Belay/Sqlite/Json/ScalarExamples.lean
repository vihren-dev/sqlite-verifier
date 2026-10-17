import Belay.Sqlite.Json.ExampleSupport

set_option doc.verso true

/-! Checked examples of JSON scalars, strings and rendering. Each expected value is the
result of the same call in the pinned native SQLite 3.51.0, read with {lit}`typeof`,
{lit}`quote` and {lit}`hex`. In the comments, {lit}`->` shows the rendered JSON text. -/

namespace Belay.Sqlite.Json.ScalarExamples

open Belay.Sqlite Belay.Sqlite.Json Belay.Sqlite.Json.ExampleSupport

-- Integers: 64-bit values are INTEGER; -0 is the integer 0; -2^63 fits.
#guard gives (extractRoot "1") (.integer 1) && gives (extractRoot "-5") (.integer (-5))
#guard gives (extractRoot "-0") (.integer 0)
#guard gives (extractRoot "9223372036854775807") (.integer 9223372036854775807)
#guard gives (extractRoot "-9223372036854775808") (.integer (-9223372036854775808))
-- Integers beyond 64 bits are REALs (native: = 12345678901234567890.0 is 1).
#guard gives (extractRoot "12345678901234567890") (.real 0x43e56a95319d63e1)
#guard gives (extractRoot "-12345678901234567890") (.real 0xc3e56a95319d63e1)
#guard gives (extractRoot "9223372036854775808") (.real 0x43e0000000000000)
-- Reals; 1E400 is Inf and -1e400 is -Inf.
#guard gives (extractRoot "1.5") (.real 0x3ff8000000000000)
#guard gives (extractRoot "1E400") (.real 0x7ff0000000000000)
#guard gives (extractRoot "-1e400") (.real 0xfff0000000000000)
-- Hexadecimal JSON5 integers: a 16-digit value with the top bit set is an unsigned
-- REAL; more than 16 significant digits is malformed for the SQL value.
#guard gives (extractRoot "0x1F") (.integer 31) && gives (extractRoot "-0x1f") (.integer (-31))
#guard gives (extractRoot "0xFFFFFFFFFFFFFFFF") (.real 0x43f0000000000000)
#guard gives (extractRoot "-0x8000000000000000") (.real 0xc3e0000000000000)
#guard fails (extractRoot "0x10000000000000000") .malformed
-- JSON5 floats as SQL values: 5. is 5.0, .5 is 0.5, 5.e3 is 5000.0.
#guard gives (extractRoot "5.") (.real 0x4014000000000000)
#guard gives (extractRoot ".5") (.real 0x3fe0000000000000)
#guard gives (extractRoot "5.e3") (.real 0x40b3880000000000)
#guard gives (extractRoot "+3") (.integer 3)
-- Canonical numbers render as written.
#guard givesText (renderRoot "[1.50, 1e2, -0, 1E400, 1E+2]") "[1.50,1e2,-0,1E400,1E+2]"
-- JSON5 numbers render as canonical JSON.
#guard givesText (renderRoot "[5.,.5,-.5,1.e5,+3,0x1F,-0x1f,Infinity,-Infinity,NaN,+inf,-inf]")
  "[5.0,0.5,-0.5,1.0e5,3,31,-31,9e999,-9e999,null,9e999,-9e999]"
#guard givesText (renderRoot "[0x10000000000000000,-0x10000000000000000,0xFFFFFFFFFFFFFFFF]")
  "[9.0e999,-9.0e999,18446744073709551615]"
#guard givesText (renderRoot "[QNaN, snan, INF, infinity]") "[null,null,9e999,9e999]"
-- Infinity as an SQL value; NaN is NULL.
#guard gives (extractRoot "Infinity") (.real 0x7ff0000000000000)
#guard gives (extractRoot "-Infinity") (.real 0xfff0000000000000)
#guard gives (extractRoot "NaN") .null
-- The literals: true is 1, false is 0, null is NULL; the arrow renders them.
#guard gives (extractRoot "true") (.integer 1) && gives (extractRoot "false") (.integer 0)
#guard gives (extractRoot "null") .null
#guard givesText (renderRoot "true") "true" && givesText (renderRoot "null") "null"
#guard givesText (renderRoot "false") "false"
-- Strings: escapes are decoded in the SQL value and kept in the rendering.
#guard givesText (extractRoot "\"a\\nb\"") "a\nb" && givesText (renderRoot "\"a\\nb\"") "\"a\\nb\""
#guard givesText (extractRoot "\"a\\\"b\"") "a\"b" && givesText (renderRoot "\"a\\\"b\"") "\"a\\\"b\""
#guard givesText (extractRoot "\"\\u00e9\"") "é" && givesText (renderRoot "\"\\u00e9\"") "\"\\u00e9\""
#guard givesText (extractRoot "\"\\b\\f\\r\\t\\/\\\\\"") "\x08\x0c\r\t/\\"
-- A surrogate pair is one character (F09F9880); a lone surrogate gets three bytes.
#guard givesText (extractRoot "\"\\ud83d\\ude00\"") "😀"
#guard gives (extractRoot "\"\\ud83d\"") (.text [0xed, 0xa0, 0xbd])
-- JSON5 escapes: \x41, \' and \v; the rendering uses \u escapes.
#guard givesText (extractRoot "'\\x41\\'\\v'") "A'\x0b"
#guard givesText (renderRoot "'\\x41\\'\\v\\0'") "\"\\u0041'\\u000b\\u0000\""
-- \0 is a NUL byte, and \0 before a digit is malformed.
#guard gives (extractRoot "'a\\0b'") (.text [0x61, 0, 0x62])
#guard fails (extractRoot "'a\\01'") .malformed
-- Line continuations are removed; one at the end of a string gives a NUL byte.
#guard givesText (extractRoot "\"a\\\nb\"") "ab" && givesText (renderRoot "\"x\\\r\ny\"") "\"xy\""
#guard givesText (extractRoot "\"a\\\u2028b\"") "ab"
#guard gives (extractRoot "\"ab\\\n\"") (.text [0x61, 0x62, 0])
-- Raw control bytes and quotes in JSON5 strings get escapes in the rendering.
#guard givesText (renderRoot "\"tab\there\"") "\"tab\\there\"" && givesText (renderRoot "\"c\x01d\"") "\"c\\u0001d\""
#guard givesText (renderRoot "'it\"s'") "\"it\\\"s\"" && givesText (renderRoot "\"it's\"") "\"it's\""
-- Bad escapes, a NUL byte and an unclosed string are malformed.
#guard fails (extractRoot "\"a\\qb\"") .malformed && fails (extractRoot "\"a\\x4\"") .malformed
#guard fails (extractRoot "\"a\x00b\"") .malformed && fails (extractRoot "\"unterminated") .malformed

end Belay.Sqlite.Json.ScalarExamples
