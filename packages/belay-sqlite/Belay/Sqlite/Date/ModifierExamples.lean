import Belay.Sqlite.Date.Examples

set_option doc.verso true

/-! Checked examples of the modifiers of {name}`Belay.Sqlite.Resolved.DateFunction.value`:
each modifier kind of SQLite 3.51.0, its bounds and its refusals, month ends and leap
days, and modifiers in order. Each expected value is the result of the pinned native
SQLite 3.51.0 for the same SQL arguments, with the time zone {lit}`UTC0` and the clock
{name}`Belay.Sqlite.DateExamples.exampleClock`. -/

namespace Belay.Sqlite.DateExamples

open Belay.Sqlite

-- Units: days, hours, minutes and seconds, with or without the final s, any case, fractions.
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1 day"] == textOf "2024-03-11 12:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "-3 DAYS"] == textOf "2024-03-07 12:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1.5 hours"] == textOf "2024-03-10 13:30:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "90 minutes"] == textOf "2024-03-10 13:30:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+0.0005 seconds", textOf "subsec"] == textOf "2024-03-10 12:00:00.001"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "1e2 days"] == textOf "2024-06-18 12:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1  day"] == textOf "2024-03-11 12:00:00"
-- Refused units: no space, a trailing space, two final s, an unknown unit.
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1day"] == .null
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1 day "] == .null
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1 dayss"] == .null
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1 week"] == .null
-- Amount bounds: each unit refuses an amount at its bound, and a result after 9999 is NULL.
#guard call .datetime [textOf "2000-01-01", textOf "+5373484 days"] == .null
#guard call .datetime [textOf "2000-01-01", textOf "+5373485 days"] == .null
#guard call .datetime [textOf "2000-01-01", textOf "-14712 years"] == .null
#guard call .datetime [textOf "2000-01-01", textOf "-14713 years"] == .null
#guard call .datetime [textOf "2000-01-01", textOf "+464269992787967 seconds"] == .null
-- Months and years change the date fields, then a day past the month's end rolls over.
#guard call .date [textOf "2024-01-31", textOf "+1 month"] == textOf "2024-03-02"
#guard call .date [textOf "2023-01-31", textOf "+1 month"] == textOf "2023-03-03"
#guard call .date [textOf "2024-02-29", textOf "+1 year"] == textOf "2025-03-01"
#guard call .date [textOf "2024-03-31", textOf "-1 month"] == textOf "2024-03-02"
#guard call .date [textOf "2024-01-31", textOf "+13 months"] == textOf "2025-03-03"
#guard call .date [textOf "2024-01-15", textOf "+1.5 months"] == textOf "2024-03-01"
#guard call .date [textOf "2024-01-15", textOf "-0.5 years"] == textOf "2023-07-16"
-- floor moves back to the end of the month; ceiling keeps the roll-over.
#guard call .date [textOf "2024-01-31", textOf "+1 month", textOf "floor"] == textOf "2024-02-29"
#guard call .date [textOf "2023-01-31", textOf "+1 month", textOf "floor"] == textOf "2023-02-28"
#guard call .date [textOf "2024-01-31", textOf "+1 month", textOf "ceiling"] == textOf "2024-03-02"
#guard call .date [textOf "2023-02-31", textOf "floor"] == textOf "2023-02-28"
#guard call .date [textOf "2023-02-31", textOf "+0 days", textOf "floor"] == textOf "2023-03-03"
-- Without the normalization rule of one argument, a parsed day after 28 stays.
#guard call .date [textOf "2023-02-31", textOf "subsec"] == textOf "2023-02-31"
-- Time offsets: +HH:MM, -HH:MM:SS.SSS, no sign, 24:00, and a time zone in the offset.
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+01:30"] == textOf "2024-03-10 13:30:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "-01:30:15.5", textOf "subsec"] == textOf "2024-03-10 10:29:44.500"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "10:00"] == textOf "2024-03-10 22:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+24:00"] == textOf "2024-03-10 12:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+01:00+02:00"] == textOf "2024-03-11 11:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "+1:30"] == .null
-- Date offsets: years, months 0 to 11 and days 0 to 30, with an optional time.
#guard call .datetime [textOf "2024-01-31 12:00", textOf "+0001-01-01"] == textOf "2025-03-04 12:00:00"
#guard call .datetime [textOf "2024-01-31 12:00", textOf "-0000-01-00"] == textOf "2023-12-31 12:00:00"
#guard call .datetime [textOf "2024-01-31 12:00", textOf "+00001-00-30 01:02:03"] == textOf "2025-03-02 13:02:03"
#guard call .datetime [textOf "2024-01-31 12:00", textOf "-0001-00-00 12:00"] == textOf "2023-01-31 00:00:00"
#guard call .datetime [textOf "2024-01-31 12:00", textOf "+0000-12-00"] == .null
#guard call .datetime [textOf "2024-01-31 12:00", textOf "+0000-00-31"] == .null
#guard call .datetime [textOf "2024-01-31 12:00", textOf "0001-00-00"] == .null
#guard call .datetime [textOf "2024-01-31 12:00", textOf "+0001-00-00x"] == .null
-- start of month, year and day; start of week does not exist.
#guard call .datetime [textOf "2024-03-10 12:34:56", textOf "start of month"] == textOf "2024-03-01 00:00:00"
#guard call .datetime [textOf "2024-03-10 12:34:56", textOf "START OF YEAR"] == textOf "2024-01-01 00:00:00"
#guard call .datetime [textOf "2024-03-10 12:34:56", textOf "start of day"] == textOf "2024-03-10 00:00:00"
#guard call .datetime [textOf "2024-03-10 12:34:56", textOf "start of week"] == .null
#guard call .datetime [.integer 1, textOf "start of day"] == textOf "-4713-11-25 00:00:00"
-- weekday N moves forward to the day; on the same day it does nothing.
#guard call .date [textOf "2024-03-10", textOf "weekday 0"] == textOf "2024-03-10"
#guard call .date [textOf "2024-03-10", textOf "weekday 1"] == textOf "2024-03-11"
#guard call .date [textOf "2024-03-10", textOf "weekday 6"] == textOf "2024-03-16"
#guard call .date [textOf "2024-03-10", textOf "weekday 1.0"] == textOf "2024-03-11"
#guard call .date [textOf "2024-03-10", textOf "weekday 1.5"] == .null
#guard call .date [textOf "2024-03-10", textOf "weekday 7"] == .null
-- unixepoch, julianday and auto read a number; each must be the first modifier.
#guard call .datetime [.integer 1700000000, textOf "unixepoch"] == textOf "2023-11-14 22:13:20"
#guard call .datetime [realOf 0x41D954FC40200000, textOf "unixepoch", textOf "subsec"] == textOf "2023-11-14 22:13:20.500"
#guard call .datetime [textOf "1700000000", textOf "unixepoch"] == textOf "2023-11-14 22:13:20"
#guard call .datetime [textOf "2024-03-10", textOf "unixepoch"] == .null
#guard call .datetime [.integer 1700000000, textOf "+1 day", textOf "unixepoch"] == .null
#guard call .datetime [.integer 2460000, textOf "julianday"] == textOf "2023-02-24 12:00:00"
#guard call .datetime [.integer 1700000000, textOf "julianday"] == .null
#guard call .datetime [.integer 2460000, textOf "auto"] == textOf "2023-02-24 12:00:00"
#guard call .datetime [.integer 1700000000, textOf "auto"] == textOf "2023-11-14 22:13:20"
#guard call .datetime [.integer 253402300800, textOf "auto"] == .null
#guard call .datetime [.integer (-1), textOf "auto"] == textOf "1969-12-31 23:59:59"
-- localtime and utc in UTC: no offset; both clear an earlier error, and utc clears subsec.
#guard call .datetime [textOf "2024-03-10 12:00:00.250", textOf "localtime", textOf "subsec"] == textOf "2024-03-10 12:00:00.250"
#guard call .datetime [textOf "1600-03-10 12:00", textOf "localtime"] == textOf "1600-03-10 12:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "utc"] == textOf "2024-03-10 12:00:00"
#guard call .datetime [textOf "2024-03-10 12:00", textOf "subsec", textOf "utc"] == textOf "2024-03-10 12:00:00"
#guard call .datetime [textOf "now", textOf "subsec", textOf "utc"] == textOf "2000-01-01 00:00:00.123"
#guard call .datetime [.integer (-1), textOf "localtime"] == textOf "2000-01-01 00:00:00"
#guard call .datetime [.integer (-1), textOf "utc"] == textOf "-4713-11-24 12:00:00"
-- subsec and subsecond show milliseconds.
#guard call .unixepoch [textOf "2024-03-10 12:00:00.250", textOf "subsec"] == realOf 0x41D97B6830100000  -- 1710072000.25
#guard call .strftime [textOf "%s", textOf "2024-03-10 12:00:00.250", textOf "SUBSECOND"] == textOf "1710072000.250"
-- A NULL modifier, a refused modifier and an empty modifier give NULL.
#guard call .date [textOf "2024-03-10", .null] == .null
#guard call .date [textOf "2024-03-10", textOf "+1 day", textOf "bogus"] == .null
#guard call .date [textOf "2024-03-10", textOf ""] == .null
#guard call .date [textOf "2024-03-10", .integer 5] == .null
-- Several modifiers apply from left to right.
#guard call .date [textOf "2024-03-10", textOf "start of month", textOf "+1 month", textOf "-1 day"] == textOf "2024-03-31"
#guard call .date [textOf "2024-03-10", textOf "-1 day", textOf "+1 month", textOf "start of month"] == textOf "2024-04-01"
#guard call .strftime [textOf "%F %T", textOf "now", textOf "start of year", textOf "+6 months", textOf "weekday 5"] == textOf "2000-07-07 00:00:00"

end Belay.Sqlite.DateExamples
