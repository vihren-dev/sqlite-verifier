import Belay.Sqlite.Declarations

set_option doc.verso true

/-! The values of {lit}`CURRENT_TIME`, {lit}`CURRENT_DATE` and {lit}`CURRENT_TIMESTAMP`,
ported from the pinned SQLite 3.51.0 {lit}`date.c`. Each keyword calls
{lit}`timeFunc`, {lit}`dateFunc` or {lit}`datetimeFunc` with no arguments. Then
{lit}`isDate` calls {lit}`setDateTimeToCurrent`, which reads the statement's clock: the
value of the VFS method {lit}`xCurrentTimeInt64` in Julian-day milliseconds, read once
per statement run ({lit}`sqlite3StmtCurrentTime`).

{lit}`setDateTimeToCurrent` fails for a clock of zero or less, and the keyword is NULL.
With no arguments, {lit}`isDate` returns before its {lit}`validJulianDay` check, so a
clock above 9999-12-31 23:59:59.999 still gives text: {lit}`computeYMD` clears the date
to zeros ({lit}`0000-00-00`), and {lit}`computeHMS` uses the time of day of the clock.
For a clock near {lit}`2^63` the sum {lit}`iJD + 43200000` wraps, the remainder is
negative and the time digits are bytes below {lit}`'0'`.

{lit}`computeYMD` uses doubles. The integer formulas here give the same result for every
day number in the valid range; a check over all 5373486 day numbers confirmed it. -/

namespace Belay.Sqlite

/-- The three time keywords. -/
inductive TimeKeyword where
  /-- {lit}`CURRENT_TIME`: {lit}`HH:MM:SS`. -/
  | time
  /-- {lit}`CURRENT_DATE`: {lit}`YYYY-MM-DD`. -/
  | date
  /-- {lit}`CURRENT_TIMESTAMP`: {lit}`YYYY-MM-DD HH:MM:SS`. -/
  | timestamp
  deriving Repr, DecidableEq

/-- Whether {lit}`validJulianDay` accepts a clock: from 0 to {lit}`INT_464269060799999`
Julian-day milliseconds, that is 9999-12-31 23:59:59.999. -/
def validJulianDay (clock : Int) : Bool := 0 ≤ clock && clock ≤ 464269060799999

/-- The clock of 2000-01-01 00:00:00. {lit}`computeJD` uses this date when the
{lit}`DateTime` has no valid date, as after {lit}`datetimeError`. -/
def defaultDateClock : Int := 211813444800000

/-- A calendar date as {lit}`computeYMD` stores it in {lit}`DateTime`: year, month
and day. The year is negative before 1 BC (year 0). -/
structure CivilDate where
  /-- The year ({lit}`p->Y`); 4713 BC is -4713. -/
  year : Int
  /-- The month 1 to 12 ({lit}`p->M`). -/
  month : Int
  /-- The day of the month 1 to 31 ({lit}`p->D`). -/
  day : Int
  deriving Repr, DecidableEq

/-- The date of a clock that {name}`validJulianDay` accepts, as {lit}`computeYMD`
computes it. SQLite divides by {lit}`36524.25`, {lit}`365.25` and {lit}`30.6001` in
double arithmetic and truncates; here each step is the exact rational division, scaled
to integers. All numerators are non-negative in the valid range, so floor division
equals C truncation. The mask {lit}`C&32767` has no effect because {lit}`C` is below
15000 there. -/
def civilDateOfValidClock (clock : Int) : CivilDate :=
  let dayNumber := (clock + 43200000) / 86400000
  let alpha := (4 * dayNumber + 128179) / 146097 - 52
  let a := dayNumber + 1 + alpha - (alpha + 100) / 4 + 25
  let b := a + 1524
  let c := (20 * b - 2442) / 7305
  let d := 36525 * c / 100
  let e := 10000 * (b - d) / 306001
  let x1 := 306001 * e / 10000
  let month := if e < 14 then e - 1 else e - 13
  { year := if month > 2 then c - 4716 else c - 4715, month, day := b - d - x1 }

/-- The date that {lit}`computeYMD` leaves in {lit}`DateTime` for a positive clock. When
{name}`validJulianDay` fails, {lit}`datetimeError` clears the structure, so year, month
and day are all zero. -/
def civilDateOfClock (clock : Int) : CivilDate :=
  if validJulianDay clock then civilDateOfValidClock clock else ⟨0, 0, 0⟩

/-- The value of a 64-bit signed sum after two's complement wrapping, as the compiled
SQLite gives for {lit}`p->iJD + 43200000` near {lit}`2^63`. -/
def wrapInt64 (number : Int) : Int := number.bmod (2 ^ 64)

/-- The time of day of a clock as {lit}`(hour, minute, second)`, as {lit}`computeHMS`
computes it with C's truncating {lit}`/` and {lit}`%`. SQLite stores the seconds as
the double {lit}`(day_ms % 60000)/1000.0` and the output truncates it with
{lit}`(int)x.s`; that equals the truncated integer quotient here. -/
def timeOfDayOfClock (clock : Int) : Int × Int × Int :=
  let dayMilliseconds := (wrapInt64 (clock + 43200000)).tmod 86400000
  let dayMinutes := dayMilliseconds.tdiv 60000
  (dayMinutes.tdiv 60, dayMinutes.tmod 60, (dayMilliseconds.tmod 60000).tdiv 1000)

/-- The byte {lit}`'0' + (n)%10` that SQLite writes for the last digit of a number.
C's {lit}`%` truncates, so a negative number gives a byte from {lit}`'0' - 9` to
{lit}`'0'`. -/
def lastDigitByte (number : Int) : UInt8 := (48 + number.tmod 10).toNat.toUInt8

/-- Two digits {lit}`(n/10)%10` and {lit}`n%10`, as {lit}`timeFunc`,
{lit}`dateFunc` and {lit}`datetimeFunc` write months, days, hours, minutes and seconds. -/
def twoDigitBytes (number : Int) : List UInt8 :=
  [lastDigitByte (number.tdiv 10), lastDigitByte number]

/-- The text {lit}`HH:MM:SS` of {lit}`timeFunc` without the {lit}`subsec` modifier. -/
def timeTextOfClock (clock : Int) : List UInt8 :=
  let (hour, minute, second) := timeOfDayOfClock clock
  twoDigitBytes hour ++ [58] ++ twoDigitBytes minute ++ [58] ++ twoDigitBytes second

/-- The text {lit}`YYYY-MM-DD` of {lit}`dateFunc`. The year is four digits of its
absolute value, with a leading {lit}`-` when it is negative (for example
{lit}`-4713-11-24`). -/
def dateText (date : CivilDate) : List UInt8 :=
  let year : Int := date.year.natAbs
  let sign : List UInt8 := if date.year < 0 then [45] else []
  sign ++ [lastDigitByte (year / 1000), lastDigitByte (year / 100),
    lastDigitByte (year / 10), lastDigitByte year] ++ [45] ++
    twoDigitBytes date.month ++ [45] ++ twoDigitBytes date.day

/-- The text {lit}`YYYY-MM-DD HH:MM:SS` of {lit}`datetimeFunc`, which calls
{lit}`computeYMD_HMS`. When {lit}`computeYMD` fails, {lit}`computeHMS` runs on the cleared
structure, so {lit}`computeJD` takes {name}`defaultDateClock` and the time is midnight. -/
def timestampTextOfClock (clock : Int) : List UInt8 :=
  dateText (civilDateOfClock clock) ++ [32] ++
    timeTextOfClock (if validJulianDay clock then clock else defaultDateClock)

/-- The value that SQLite gives for the keyword when the statement's clock, as the VFS
method {lit}`xCurrentTimeInt64` returns it (Julian-day milliseconds), is {lit}`clock`.
It is NULL for a clock of zero or less, where {lit}`setDateTimeToCurrent` fails, and
text otherwise. -/
def TimeKeyword.value (keyword : TimeKeyword) (clock : Int) : Value :=
  if clock ≤ 0 then .null else
    match keyword with
    | .time => .text (timeTextOfClock clock)
    | .date => .text (dateText (civilDateOfClock clock))
    | .timestamp => .text (timestampTextOfClock clock)

end Belay.Sqlite
