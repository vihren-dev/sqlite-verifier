import Belay.Sqlite.Date.DateTime
import Belay.Sqlite.Date.Printf

set_option doc.verso true

/-! The format specifiers of {lit}`strftimeFunc` in the pinned SQLite 3.51.0
{lit}`date.c` (ADR 0012, amendment 5, slice 6f, owner decision 3). Each specifier reads
a {name}`Belay.Sqlite.DateTime` after {lit}`computeJD` and {lit}`computeYMD_HMS`; the week and day
helpers {lit}`daysAfterJan01`, {lit}`daysAfterMonday` and {lit}`daysAfterSunday` follow
the C code. -/

namespace Belay.Sqlite

/-- The Julian day milliseconds of 1970-01-01 00:00:00, the Unix epoch. -/
def unixEpochJulianMilliseconds : Int := 210866760000000

/-- The milliseconds of one day. -/
def millisecondsPerDay : Int := 86400000

/-- {lit}`daysAfterJan01`: the days from January 1 of the year to the date, from 0.
SQLite computes the Julian day of January 1 with the same time of day by
{name}`DateTime.computeJulianDay`. -/
def DateTime.daysAfterJanuaryFirst (p : DateTime) : Int :=
  let januaryFirst := { p with validJulianMilliseconds := false, month := 1, day := 1 }.computeJulianDay
  (p.julianMilliseconds - januaryFirst.julianMilliseconds + 43200000).tdiv millisecondsPerDay

/-- {lit}`daysAfterMonday`: the day of the week, 0 for Monday to 6 for Sunday. -/
def DateTime.daysAfterMonday (p : DateTime) : Int :=
  ((p.julianMilliseconds + 43200000).tdiv millisecondsPerDay).tmod 7

/-- {lit}`daysAfterSunday`: the day of the week, 0 for Sunday to 6 for Saturday. -/
def DateTime.daysAfterSunday (p : DateTime) : Int :=
  ((p.julianMilliseconds + 129600000).tdiv millisecondsPerDay).tmod 7

/-- The Thursday of the ISO week of the date, as {lit}`%G`, {lit}`%g` and {lit}`%V`
compute it: the Julian day moved by {lit}`3 - daysAfterMonday` days, then
{name}`DateTime.computeCivilDate`. A move out of the valid range gives the cleared
structure of {name}`DateTime.error`. -/
def DateTime.isoWeekThursday (p : DateTime) : DateTime :=
  { p with julianMilliseconds := p.julianMilliseconds + (3 - p.daysAfterMonday) * millisecondsPerDay,
           validDate := false }.computeCivilDate

/-- The hour on a 12-hour clock, 12 for hour 0, as {lit}`%I` and {lit}`%l` write it. -/
def twelveHour (hour : Int) : Int :=
  let hour := if hour > 12 then hour - 12 else hour
  if hour == 0 then 12 else hour

/-- The format specifiers of {lit}`strftimeFunc`, each after a {lit}`%`. -/
inductive StrftimeSpecifier where
  /-- {lit}`%d`: the day of the month, {lit}`01` to {lit}`31`. -/
  | dayOfMonth
  /-- {lit}`%e`: the day of the month with a leading space. -/
  | dayOfMonthSpaced
  /-- {lit}`%f`: the seconds with milliseconds, {lit}`SS.SSS`. -/
  | fractionalSeconds
  /-- {lit}`%F`: the date {lit}`YYYY-MM-DD`. -/
  | isoDate
  /-- {lit}`%G`: the year of the ISO week. -/
  | isoYear
  /-- {lit}`%g`: the last two digits of the year of the ISO week. -/
  | isoYearShort
  /-- {lit}`%H`: the hour, {lit}`00` to {lit}`24`. -/
  | hour
  /-- {lit}`%k`: the hour with a leading space. -/
  | hourSpaced
  /-- {lit}`%I`: the hour on a 12-hour clock, {lit}`01` to {lit}`12`. -/
  | twelveHourPadded
  /-- {lit}`%l`: the hour on a 12-hour clock with a leading space. -/
  | twelveHourSpaced
  /-- {lit}`%j`: the day of the year, {lit}`001` to {lit}`366`. -/
  | dayOfYear
  /-- {lit}`%J`: the Julian day number. -/
  | julianDay
  /-- {lit}`%m`: the month, {lit}`01` to {lit}`12`. -/
  | month
  /-- {lit}`%M`: the minute. -/
  | minute
  /-- {lit}`%p`: {lit}`AM` or {lit}`PM`. -/
  | meridiemUpper
  /-- {lit}`%P`: {lit}`am` or {lit}`pm`. -/
  | meridiemLower
  /-- {lit}`%R`: {lit}`HH:MM`. -/
  | hourMinute
  /-- {lit}`%s`: the Unix time in seconds. -/
  | unixSeconds
  /-- {lit}`%S`: the whole seconds. -/
  | seconds
  /-- {lit}`%T`: {lit}`HH:MM:SS`. -/
  | timeOfDay
  /-- {lit}`%u`: the day of the week, 1 for Monday to 7 for Sunday. -/
  | weekdayFromMonday
  /-- {lit}`%w`: the day of the week, 0 for Sunday to 6 for Saturday. -/
  | weekdayFromSunday
  /-- {lit}`%U`: the week of the year; the first Sunday starts week 01. -/
  | weekFromSunday
  /-- {lit}`%V`: the ISO week of the year, {lit}`01` to {lit}`53`. -/
  | isoWeek
  /-- {lit}`%W`: the week of the year; the first Monday starts week 01. -/
  | weekFromMonday
  /-- {lit}`%Y`: the year. -/
  | year
  /-- {lit}`%%`: a percent sign. -/
  | percent
  deriving Repr, DecidableEq

/-- The specifier of the byte after a {lit}`%`, or {lit}`none` for a byte that
{lit}`strftimeFunc` does not know, which makes the result NULL. -/
def StrftimeSpecifier.ofByte (byte : UInt8) : Option StrftimeSpecifier :=
  match byte.toNat with
  | 100 => some .dayOfMonth | 101 => some .dayOfMonthSpaced | 102 => some .fractionalSeconds
  | 70 => some .isoDate | 71 => some .isoYear | 103 => some .isoYearShort
  | 72 => some .hour | 107 => some .hourSpaced | 73 => some .twelveHourPadded
  | 108 => some .twelveHourSpaced | 106 => some .dayOfYear | 74 => some .julianDay
  | 109 => some .month | 77 => some .minute | 112 => some .meridiemUpper
  | 80 => some .meridiemLower | 82 => some .hourMinute | 115 => some .unixSeconds
  | 83 => some .seconds | 84 => some .timeOfDay | 117 => some .weekdayFromMonday
  | 119 => some .weekdayFromSunday | 85 => some .weekFromSunday | 86 => some .isoWeek
  | 87 => some .weekFromMonday | 89 => some .year | 37 => some .percent
  | _ => none

/-- The greatest seconds that {lit}`%f` writes. -/
def maximumFractionalSeconds : Float := 59.999

/-- The bytes that a specifier writes for the date and time {lit}`x`. -/
def StrftimeSpecifier.text (x : DateTime) : StrftimeSpecifier → List UInt8
  | .dayOfMonth => formatInteger 2 true x.day
  | .dayOfMonthSpaced => formatInteger 2 false x.day
  | .fractionalSeconds =>
    formatFixed 6 true 3 (if x.seconds > maximumFractionalSeconds then maximumFractionalSeconds else x.seconds)
  | .isoDate => formatInteger 4 true x.year ++ [45] ++ formatInteger 2 true x.month ++ [45] ++ formatInteger 2 true x.day
  | .isoYear => formatInteger 4 true x.isoWeekThursday.year
  | .isoYearShort => formatInteger 2 true (x.isoWeekThursday.year.tmod 100)
  | .hour => formatInteger 2 true x.hour
  | .hourSpaced => formatInteger 2 false x.hour
  | .twelveHourPadded => formatInteger 2 true (twelveHour x.hour)
  | .twelveHourSpaced => formatInteger 2 false (twelveHour x.hour)
  | .dayOfYear => formatInteger 3 true (x.daysAfterJanuaryFirst + 1)
  | .julianDay => formatGeneric16 (Float.ofInt x.julianMilliseconds / 86400000.0)
  | .month => formatInteger 2 true x.month
  | .minute => formatInteger 2 true x.minute
  | .meridiemUpper => if x.hour ≥ 12 then [80, 77] else [65, 77]
  | .meridiemLower => if x.hour ≥ 12 then [112, 109] else [97, 109]
  | .hourMinute => formatInteger 2 true x.hour ++ [58] ++ formatInteger 2 true x.minute
  | .unixSeconds =>
    if x.useSubsecond then formatFixed 0 false 3 (Float.ofInt (x.julianMilliseconds - unixEpochJulianMilliseconds) / 1000.0)
    else formatInteger 0 false (x.julianMilliseconds.tdiv 1000 - unixEpochJulianMilliseconds / 1000)
  | .seconds => formatInteger 2 true (doubleToInt32 x.seconds)
  | .timeOfDay => formatInteger 2 true x.hour ++ [58] ++ formatInteger 2 true x.minute ++ [58] ++
      formatInteger 2 true (doubleToInt32 x.seconds)
  | .weekdayFromMonday => let day := x.daysAfterSunday; [lastDigitByte (if day == 0 then 7 else day)]
  | .weekdayFromSunday => [lastDigitByte x.daysAfterSunday]
  | .weekFromSunday => formatInteger 2 true ((x.daysAfterJanuaryFirst - x.daysAfterSunday + 7).tdiv 7)
  | .isoWeek => formatInteger 2 true (x.isoWeekThursday.daysAfterJanuaryFirst.tdiv 7 + 1)
  | .weekFromMonday => formatInteger 2 true ((x.daysAfterJanuaryFirst - x.daysAfterMonday + 7).tdiv 7)
  | .year => formatInteger 4 true x.year
  | .percent => [37]

/-- The loop of {lit}`strftimeFunc` over the format: other bytes are copied; a
{lit}`%` and the next byte write the specifier's text. An unknown specifier, or a
{lit}`%` at the end, gives {lit}`none`, which is NULL. -/
def strftimeText (x : DateTime) : List UInt8 → Option (List UInt8)
  | [] => some []
  | 37 :: code :: rest => match StrftimeSpecifier.ofByte code, strftimeText x rest with
    | some specifier, some text => some (specifier.text x ++ text)
    | some _, none | none, some _ | none, none => none
  | [37] => none
  | byte :: rest => (strftimeText x rest).map (byte :: ·)

end Belay.Sqlite
