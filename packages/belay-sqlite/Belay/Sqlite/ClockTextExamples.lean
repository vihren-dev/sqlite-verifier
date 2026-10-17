import Belay.Sqlite.ClockText

set_option doc.verso true

/-! Checked examples of {lit}`CURRENT_TIME`, {lit}`CURRENT_DATE` and
{lit}`CURRENT_TIMESTAMP`. Each expected value is the result of the pinned native SQLite
3.51.0 when its VFS method {lit}`xCurrentTimeInt64` returns the given clock in Julian-day
milliseconds. -/

namespace Belay.Sqlite.ClockTextExamples

open Belay.Sqlite

/-- The text value with the UTF-8 bytes of a string, to write expected results. -/
def textOf (text : String) : Value := .text text.toUTF8.toList

/-- The three keyword values for one clock, in the order time, date, timestamp. -/
def keywordValues (clock : Int) : List Value :=
  [TimeKeyword.time.value clock, TimeKeyword.date.value clock, TimeKeyword.timestamp.value clock]

-- A clock of zero or less is NULL for every keyword.
#guard keywordValues 0 == [.null, .null, .null]
#guard keywordValues (-1) == [.null, .null, .null]
#guard keywordValues (-9223372036854775808) == [.null, .null, .null]
-- The first positive clock: noon of Julian day 0, a negative year.
#guard keywordValues 1 == [textOf "12:00:00", textOf "-4713-11-24", textOf "-4713-11-24 12:00:00"]
#guard TimeKeyword.timestamp.value 43200000 == textOf "-4713-11-25 00:00:00"
#guard TimeKeyword.timestamp.value 86399999 == textOf "-4713-11-25 11:59:59"
-- Year 0 and year 1.
#guard TimeKeyword.timestamp.value 148731163199999 == textOf "0000-12-31 23:59:59"
#guard TimeKeyword.timestamp.value 148731163200000 == textOf "0001-01-01 00:00:00"
-- The output is the Gregorian calendar, also before 1582.
#guard TimeKeyword.date.value 198627768000000 == textOf "1582-03-01"
-- 1900 and 2100 are not leap years; 2000 and 2024 are.
#guard TimeKeyword.timestamp.value 208662868799999 == textOf "1900-02-28 23:59:59"
#guard TimeKeyword.date.value 208662868800000 == textOf "1900-03-01"
#guard TimeKeyword.date.value 211818542400000 == textOf "2000-02-29"
#guard TimeKeyword.timestamp.value 212576011199999 == textOf "2024-02-29 23:59:59"
#guard TimeKeyword.timestamp.value 214974302399999 == textOf "2100-02-28 23:59:59"
#guard TimeKeyword.date.value 214974302400000 == textOf "2100-03-01"
-- The Unix epoch, a year boundary, and seconds that are truncated, not rounded.
#guard keywordValues 210866760000000 == [textOf "00:00:00", textOf "1970-01-01", textOf "1970-01-01 00:00:00"]
#guard TimeKeyword.timestamp.value 211813444799999 == textOf "1999-12-31 23:59:59"
#guard TimeKeyword.timestamp.value 212602449599999 == textOf "2024-12-31 23:59:59"
#guard TimeKeyword.time.value 464269060798999 == textOf "23:59:58"
-- The last valid clock.
#guard TimeKeyword.timestamp.value 464269060799999 == textOf "9999-12-31 23:59:59"
-- Beyond the range the date is zeros, the timestamp's time is midnight, and the time
-- keeps the clock's time of day.
#guard keywordValues 464269060800000 == [textOf "00:00:00", textOf "0000-00-00", textOf "0000-00-00 00:00:00"]
#guard keywordValues 464269147199999 == [textOf "23:59:59", textOf "0000-00-00", textOf "0000-00-00 00:00:00"]
-- Just below the int64 wrap of iJD + 43200000, and above it: negative digit bytes.
#guard TimeKeyword.time.value 9223372036811575807 == textOf "07:12:55"
#guard TimeKeyword.time.value 9223372036811575808 == textOf "0):/.:++"
#guard keywordValues 9223372036854775807 == [textOf "/':/.:++", textOf "0000-00-00", textOf "0000-00-00 00:00:00"]

end Belay.Sqlite.ClockTextExamples
