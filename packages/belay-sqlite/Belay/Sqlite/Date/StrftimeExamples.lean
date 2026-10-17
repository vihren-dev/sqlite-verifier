import Belay.Sqlite.Date.Examples

set_option doc.verso true

/-! Checked examples of {lit}`strftime` by {name}`Belay.Sqlite.Resolved.DateFunction.value`:
each format specifier of SQLite 3.51.0, negative years, week numbers at year
boundaries, the rounding of {lit}`%f` and {lit}`%J`, {lit}`subsec`, unknown
specifiers and the format argument. Each expected value is the result of the pinned
native SQLite 3.51.0 for the same SQL arguments under the given clock. -/

namespace Belay.Sqlite.DateExamples

open Belay.Sqlite

-- Each specifier for a date with milliseconds in the afternoon.
#guard call .strftime [textOf "%d", textOf "2023-06-04 13:05:09.0625"] == textOf "04"
#guard call .strftime [textOf "%e", textOf "2023-06-04 13:05:09.0625"] == textOf " 4"
#guard call .strftime [textOf "%f", textOf "2023-06-04 13:05:09.0625"] == textOf "09.063"
#guard call .strftime [textOf "%F", textOf "2023-06-04 13:05:09.0625"] == textOf "2023-06-04"
#guard call .strftime [textOf "%G", textOf "2023-06-04 13:05:09.0625"] == textOf "2023"
#guard call .strftime [textOf "%g", textOf "2023-06-04 13:05:09.0625"] == textOf "23"
#guard call .strftime [textOf "%H", textOf "2023-06-04 13:05:09.0625"] == textOf "13"
#guard call .strftime [textOf "%k", textOf "2023-06-04 13:05:09.0625"] == textOf "13"
#guard call .strftime [textOf "%I", textOf "2023-06-04 13:05:09.0625"] == textOf "01"
#guard call .strftime [textOf "%l", textOf "2023-06-04 13:05:09.0625"] == textOf " 1"
#guard call .strftime [textOf "%j", textOf "2023-06-04 13:05:09.0625"] == textOf "155"
#guard call .strftime [textOf "%J", textOf "2023-06-04 13:05:09.0625"] == textOf "2460100.045243785"
#guard call .strftime [textOf "%m", textOf "2023-06-04 13:05:09.0625"] == textOf "06"
#guard call .strftime [textOf "%M", textOf "2023-06-04 13:05:09.0625"] == textOf "05"
#guard call .strftime [textOf "%p", textOf "2023-06-04 13:05:09.0625"] == textOf "PM"
#guard call .strftime [textOf "%P", textOf "2023-06-04 13:05:09.0625"] == textOf "pm"
#guard call .strftime [textOf "%R", textOf "2023-06-04 13:05:09.0625"] == textOf "13:05"
#guard call .strftime [textOf "%s", textOf "2023-06-04 13:05:09.0625"] == textOf "1685883909"
#guard call .strftime [textOf "%S", textOf "2023-06-04 13:05:09.0625"] == textOf "09"
#guard call .strftime [textOf "%T", textOf "2023-06-04 13:05:09.0625"] == textOf "13:05:09"
#guard call .strftime [textOf "%u", textOf "2023-06-04 13:05:09.0625"] == textOf "7"
#guard call .strftime [textOf "%w", textOf "2023-06-04 13:05:09.0625"] == textOf "0"
#guard call .strftime [textOf "%U", textOf "2023-06-04 13:05:09.0625"] == textOf "23"
#guard call .strftime [textOf "%V", textOf "2023-06-04 13:05:09.0625"] == textOf "22"
#guard call .strftime [textOf "%W", textOf "2023-06-04 13:05:09.0625"] == textOf "22"
#guard call .strftime [textOf "%Y", textOf "2023-06-04 13:05:09.0625"] == textOf "2023"
#guard call .strftime [textOf "%%", textOf "2023-06-04 13:05:09.0625"] == textOf "%"
-- A morning time, noon and midnight for the hour specifiers.
#guard call .strftime [textOf "%H %k %I %l %p %P", textOf "2023-06-04 09:05"] == textOf "09  9 09  9 AM am"
#guard call .strftime [textOf "%H %k %I %l %p %P", textOf "2023-06-04 12:00"] == textOf "12 12 12 12 PM pm"
#guard call .strftime [textOf "%H %k %I %l %p %P", textOf "2023-06-04 00:00"] == textOf "00  0 12 12 AM am"
-- Negative years: %Y, %F and %G pad the sign into the width; %g keeps a negative remainder.
#guard call .strftime [textOf "%Y|%F|%G|%g|%j|%V|%U|%W|%u|%w", textOf "-0044-03-15"] == textOf "-044|-044-03-15|-044|-44|075|11|11|11|4|4"
#guard call .strftime [textOf "%Y|%F|%G|%g|%J|%s", .integer 0] == textOf "-4713|-4713-11-24|-4713|-13|0|-210866760000"
#guard call .strftime [textOf "%Y|%F|%J|%s", realOf 0x41547F8B1FFE5C92] == textOf "9999|9999-12-31|5373484.4999|253402300791"
-- Week numbers at year boundaries and in leap years.
#guard call .strftime [textOf "%G-%V %U %W %j", textOf "2021-01-03"] == textOf "2020-53 01 00 003"
#guard call .strftime [textOf "%G-%V %U %W %j", textOf "2020-12-31"] == textOf "2020-53 52 52 366"
#guard call .strftime [textOf "%G-%V %U %W %j", textOf "2024-12-30"] == textOf "2025-01 52 53 365"
#guard call .strftime [textOf "%G-%V %U %W %j", textOf "2000-12-31"] == textOf "2000-52 53 52 366"
#guard call .strftime [textOf "%G-%V %U %W %j", textOf "1900-12-31"] == textOf "1901-01 52 53 365"
-- %G, %g and %V read the Thursday of the week; Julian day 0 is a Monday.
#guard call .strftime [textOf "%G|%g|%V", .integer 0] == textOf "-4713|-13|48"
-- %f rounds to milliseconds; a fraction above 0.999 is cut; %J has 16 digits.
#guard call .strftime [textOf "%f", textOf "12:00:07.9996"] == textOf "07.999"
#guard call .strftime [textOf "%f", textOf "12:00:07.0005"] == textOf "07.000"
#guard call .strftime [textOf "%J", textOf "2023-06-04 13:05:09.123"] == textOf "2460100.045244479"
#guard call .strftime [textOf "%J", realOf 0x3F1A36E2EB1C432D] == textOf "0.0001"
-- subsec gives %s with milliseconds.
#guard call .strftime [textOf "%s|%f", textOf "subsec"] == textOf "946684800.123|00.123"
#guard callAt 86400123 .strftime [textOf "%s", textOf "subsec"] == textOf "-210866673599.877"
-- Unknown specifiers and a % at the end give NULL; other bytes are copied.
#guard call .strftime [textOf "%q", textOf "2023-06-04"] == .null
#guard call .strftime [textOf "%Y%", textOf "2023-06-04"] == .null
#guard call .strftime [textOf "%Y %é", textOf "2023-06-04"] == .null
#guard call .strftime [textOf "year é %Y.", textOf "2023-06-04"] == textOf "year é 2023."
#guard call .strftime [textOf "", textOf "2023-06-04"] == textOf ""
#guard call .strftime [textOf "%Y\x00%q", textOf "2023-06-04"] == textOf "2023"
-- The format: NULL gives NULL, a number is its text, no time value is now.
#guard call .strftime [.null, textOf "2023-06-04"] == .null
#guard call .strftime [.integer 12, textOf "2023-06-04"] == textOf "12"
#guard call .strftime [textOf "%Y", .null] == .null
#guard call .strftime [textOf "%F %T"] == textOf "2000-01-01 00:00:00"
#guard call .strftime [] == .null

end Belay.Sqlite.DateExamples
