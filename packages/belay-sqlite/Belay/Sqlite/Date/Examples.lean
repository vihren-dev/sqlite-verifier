import Belay.Sqlite.Date.Functions

set_option doc.verso true

/-! Checked examples of {name}`Belay.Sqlite.Resolved.DateFunction.value` for {lit}`date`,
{lit}`time`, {lit}`datetime`, {lit}`julianday` and {lit}`unixepoch`. Each expected
value is the result of the pinned native SQLite 3.51.0 for the same SQL arguments when
its VFS method {lit}`xCurrentTimeInt64` returns the given clock in Julian-day
milliseconds. A REAL result is written as its IEEE bits, with its decimal value in a
comment. -/

namespace Belay.Sqlite.DateExamples

open Belay.Sqlite

/-- The clock of most examples: 2000-01-01 00:00:00.123 in Julian-day milliseconds. -/
def exampleClock : Int := 211813444800123

/-- The text value with the UTF-8 bytes of a string, to write arguments and results. -/
def textOf (text : String) : Value := .text text.toUTF8.toList

/-- The REAL value with the given IEEE bits. -/
def realOf (bits : UInt64) : Value := .real bits

/-- The value of a function call with these arguments under a given clock. -/
def callAt (clock : Int) (function : Resolved.DateFunction) (arguments : List Value) : Value :=
  function.value clock arguments

/-- The value of a function call with these arguments under {name}`exampleClock`. -/
def call (function : Resolved.DateFunction) (arguments : List Value) : Value :=
  callAt exampleClock function arguments

-- Text formats: a date, then a time with minutes, seconds and milliseconds, a T separator.
#guard call .datetime [textOf "2023-06-15"] == textOf "2023-06-15 00:00:00"
#guard call .datetime [textOf "2023-06-15 13:45"] == textOf "2023-06-15 13:45:00"
#guard call .datetime [textOf "2023-06-15 13:45:30"] == textOf "2023-06-15 13:45:30"
#guard call .julianday [textOf "2023-06-15 13:45:30.125"] == realOf 0x4142C4E78960C22E  -- 2460111.0732653355
#guard call .datetime [textOf "2023-06-15T13:45:30"] == textOf "2023-06-15 13:45:30"
#guard call .datetime [textOf "2023-06-15TT  13:45"] == textOf "2023-06-15 13:45:00"
#guard call .datetime [textOf "2023-06-15T"] == textOf "2023-06-15 00:00:00"
-- A time only takes the date 2000-01-01.
#guard call .datetime [textOf "13:45"] == textOf "2000-01-01 13:45:00"
#guard call .datetime [textOf "13:45:30.999"] == textOf "2000-01-01 13:45:30"
#guard call .julianday [textOf "13:45:30.9999"] == realOf 0x4142B42C8961170A  -- 2451545.0732754515
-- Time zone suffixes move the time to UTC; Z and an offset of zero keep it.
#guard call .datetime [textOf "2023-06-15 13:45Z"] == textOf "2023-06-15 13:45:00"
#guard call .datetime [textOf "2023-06-15 13:45:30z"] == textOf "2023-06-15 13:45:30"
#guard call .datetime [textOf "2023-06-15 13:45+02:30"] == textOf "2023-06-15 11:15:00"
#guard call .datetime [textOf "2023-06-15 01:45:30 -05:00"] == textOf "2023-06-15 06:45:30"
#guard call .datetime [textOf "2023-06-15 13:45 +14:59 "] == textOf "2023-06-14 22:46:00"
#guard call .time [textOf "00:30-00:00"] == textOf "00:30:00"
-- Refused suffixes and shapes: an hour above 14, no colon, junk, a short field.
#guard call .datetime [textOf "2023-06-15 13:45+15:00"] == .null
#guard call .datetime [textOf "2023-06-15 13:45+0230"] == .null
#guard call .datetime [textOf "2023-06-15 13:45Zx"] == .null
#guard call .date [textOf "2023-6-15"] == .null
#guard call .date [textOf "2023-06-15 13"] == .null
#guard call .time [textOf "13:45:30."] == .null
-- Leading spaces are refused; trailing spaces are accepted.
#guard call .date [textOf " 2023-06-15"] == .null
#guard call .date [textOf "2023-06-15 "] == textOf "2023-06-15"
#guard call .time [textOf "13:45 "] == textOf "13:45:00"
-- now and its case variants read the clock; with spaces it is refused.
#guard call .datetime [textOf "now"] == textOf "2000-01-01 00:00:00"
#guard call .datetime [textOf "NoW"] == textOf "2000-01-01 00:00:00"
#guard call .datetime [textOf " now"] == .null
#guard call .datetime [] == textOf "2000-01-01 00:00:00"
-- A clock of zero gives NULL. Above 9999-12-31, no argument skips the range check.
#guard callAt 0 .date [] == .null
#guard callAt 0 .date [textOf "now"] == .null
#guard callAt 464269060800000 .datetime [] == textOf "0000-00-00 00:00:00"
#guard callAt 464269060800000 .datetime [textOf "now"] == .null
#guard callAt 464269060800000 .julianday [] == realOf 0x41547F8B20000000  -- 5373484.5
-- Numeric text, INTEGER and REAL values are Julian day numbers.
#guard call .datetime [textOf "2451545"] == textOf "2000-01-01 12:00:00"
#guard call .datetime [textOf " 2451545.5e0 "] == textOf "2000-01-02 00:00:00"
#guard call .datetime [textOf "2451545x"] == .null
#guard call .datetime [.integer 2460000] == textOf "2023-02-24 12:00:00"
#guard call .datetime [.integer 0] == textOf "-4713-11-24 12:00:00"
#guard call .datetime [.integer (-1)] == .null
#guard call .datetime [realOf 0x8000000000000000] == textOf "-4713-11-24 12:00:00"
#guard call .datetime [realOf 0x4142C4B060000000] == textOf "2023-02-25 06:00:00"
#guard call .datetime [realOf 0x41547F8B1FFFFF95] == textOf "9999-12-31 23:59:59"
#guard call .datetime [realOf 0x41547F8B20000000] == .null
#guard call .datetime [.integer 5373485] == .null
-- Invalid dates: a day after the month's end is normalized, month 13 and day 32 are refused.
#guard call .date [textOf "2023-02-31"] == textOf "2023-03-03"
#guard call .date [textOf "2023-02-29"] == textOf "2023-03-01"
#guard call .date [textOf "2024-02-29"] == textOf "2024-02-29"
#guard call .date [textOf "2023-04-31 10:00"] == textOf "2023-05-01"
#guard call .date [textOf "2023-13-01"] == .null
#guard call .date [textOf "2023-01-32"] == .null
#guard call .datetime [textOf "2023-01-01 24:00"] == textOf "2023-01-01 24:00:00"
#guard call .datetime [textOf "2023-01-01 24:30"] == textOf "2023-01-01 24:30:00"
-- Negative years, year 0 and the ends of the range.
#guard call .datetime [textOf "-4713-11-24 12:00"] == textOf "-4713-11-24 12:00:00"
#guard call .datetime [textOf "-4713-11-24 11:59:59.999"] == .null
#guard call .datetime [textOf "-0001-12-31"] == textOf "-0001-12-31 00:00:00"
#guard call .julianday [textOf "0000-01-01"] == realOf 0x413A42E380000000  -- 1721059.5
#guard call .datetime [textOf "9999-12-31 23:59:59.999"] == textOf "9999-12-31 23:59:59"
#guard call .date [textOf "9999-12-31 23:59:59.999-00:01"] == .null
-- NULL gives NULL; a BLOB is read as its bytes, up to a zero byte.
#guard call .date [.null] == .null
#guard call .date [.blob [50, 48, 50, 51, 45, 48, 54, 45, 49, 53]] == textOf "2023-06-15"
#guard call .date [.blob [50, 48, 50, 51, 45, 48, 54, 45, 49, 53, 0, 106, 117, 110, 107]] == textOf "2023-06-15"
#guard call .date [textOf "2023-06-15\x00junk"] == textOf "2023-06-15"
-- subsec and subsecond are now with milliseconds.
#guard call .time [textOf "subsec"] == textOf "00:00:00.123"
#guard call .datetime [textOf "SUBSECOND"] == textOf "2000-01-01 00:00:00.123"
#guard call .unixepoch [textOf "subsec"] == realOf 0x41CC36A1C00FBE77  -- 946684800.123
#guard call .unixepoch [textOf "subsecs"] == .null
-- julianday and unixepoch results.
#guard call .julianday [textOf "2000-01-01 12:00"] == realOf 0x4142B42C80000000  -- 2451545.0
#guard call .julianday [textOf "1970-01-01"] == realOf 0x41429EC5C0000000  -- 2440587.5
#guard call .julianday [] == realOf 0x4142B42C40000BF1  -- 2451544.5000014235
#guard call .unixepoch [textOf "1970-01-01"] == .integer 0
#guard call .unixepoch [textOf "1969-12-31 23:59:59.999"] == .integer (-1)
#guard call .unixepoch [textOf "2038-01-19 03:14:08"] == .integer 2147483648
#guard call .unixepoch [] == .integer 946684800
-- Modifiers: resolution refuses them until slice 6g. This is the model value, not the
-- value of native SQLite, which is 2023-06-16.
#guard call .date [textOf "2023-06-15", textOf "+1 day"] == .null

end Belay.Sqlite.DateExamples
