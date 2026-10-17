import Belay.Sqlite.ClockText

set_option doc.verso true

/-! The {lit}`DateTime` structure of the pinned SQLite 3.51.0 {lit}`date.c` and its three
conversions {lit}`computeJD`, {lit}`computeYMD` and {lit}`computeHMS` (ADR 0012,
amendment 5, slices 6f and 6g). Each function returns the new structure in place of the C
mutation. The arithmetic follows the C code step by step: 64-bit integers wrap as the
compiled x86-64 SQLite gives, and the seconds are a double. -/

namespace Belay.Sqlite

/-- The fields of {lit}`DateTime`. The default value is the cleared structure of
{lit}`memset`. -/
structure DateTime where
  /-- {lit}`iJD`: the Julian day number times 86400000. -/
  julianMilliseconds : Int := 0
  /-- {lit}`Y`: the year; negative before 1 BC. -/
  year : Int := 0
  /-- {lit}`M`: the month. -/
  month : Int := 0
  /-- {lit}`D`: the day of the month. -/
  day : Int := 0
  /-- {lit}`h`: the hour. -/
  hour : Int := 0
  /-- {lit}`m`: the minute. -/
  minute : Int := 0
  /-- {lit}`tz`: the time zone offset in minutes that {lit}`computeJD` subtracts. -/
  timezoneMinutes : Int := 0
  /-- {lit}`s`: the seconds as a double, or the raw number of {lit}`setRawDateNumber`. -/
  seconds : Float := 0
  /-- {lit}`validJD`: the Julian day field is set. -/
  validJulianMilliseconds : Bool := false
  /-- {lit}`validYMD`: year, month and day are set. -/
  validDate : Bool := false
  /-- {lit}`validHMS`: hour, minute and seconds are set. -/
  validTime : Bool := false
  /-- {lit}`rawS`: the seconds field holds a raw number. -/
  rawSeconds : Bool := false
  /-- {lit}`isError`: {lit}`datetimeError` cleared the structure. -/
  isError : Bool := false
  /-- {lit}`useSubsec`: the output shows milliseconds. -/
  useSubsecond : Bool := false
  /-- {lit}`nFloor`: the days that the {lit}`floor` modifier subtracts to go back from a
  day after the end of the month to the last day of the month. -/
  dayOverflow : Int := 0
  /-- {lit}`isUtc`: the time is known to be UTC, so the {lit}`utc` modifier does
  nothing. -/
  isUtc : Bool := false
  /-- {lit}`isLocal`: the time is known to be local time, so the {lit}`localtime`
  modifier does nothing. -/
  isLocal : Bool := false

/-- The structure after {lit}`datetimeError`: all fields cleared, and the error flag set. -/
def DateTime.error : DateTime := { isError := true }

/-- The least 64-bit signed integer, which the x86-64 conversion instruction gives for
a double that is NaN or out of range. -/
def int64Indefinite : Int := -(2 ^ 63)

/-- The C conversion {lit}`(sqlite3_int64)value` as the compiled x86-64 SQLite does it:
truncation toward zero, and {name}`int64Indefinite` for a NaN or a value outside the
64-bit range. -/
def doubleToInt64 (value : Float) : Int :=
  if value.isNaN || value ≥ 9223372036854775808.0 || value < -9223372036854775808.0 then int64Indefinite
  else if value < 0 then -((-value).toUInt64.toNat : Int) else (value.toUInt64.toNat : Int)

/-- The C conversion {lit}`(int)value` as the compiled x86-64 SQLite does it: truncation
toward zero, and {lit}`-2^31` for a NaN or a value outside the 32-bit range. -/
def doubleToInt32 (value : Float) : Int :=
  if value.isNaN || value ≥ 2147483648.0 || value < -2147483648.0 then -(2 ^ 31)
  else if value < 0 then -((-value).toUInt64.toNat : Int) else (value.toUInt64.toNat : Int)

/-- The least year that {lit}`computeJD` accepts: 4714 BC. -/
def minimumYear : Int := -4713

/-- The greatest year that {lit}`computeJD` accepts. -/
def maximumYear : Int := 9999

/-- The Julian day milliseconds of the start of a day of the Gregorian calendar, as
{lit}`computeJD` computes it (Meeus, page 61). SQLite computes
{lit}`(X1 + X2 + D + B - 1524.5) * 86400000` in double arithmetic. The product is an
integer below {lit}`2^53` for every accepted date, so the double result is exact and
equals the integer formula here. -/
def julianMillisecondsOfDate (year month day : Int) : Int :=
  let (year, month) := if month ≤ 2 then (year - 1, month + 12) else (year, month)
  let a := (year + 4800).tdiv 100
  let b := 38 - a + a.tdiv 4
  let x1 := (36525 * (year + 4716)).tdiv 100
  let x2 := (306001 * (month + 1)).tdiv 10000
  (2 * (x1 + x2 + day + b) - 3049) * 43200000

/-- {lit}`computeJD`: set the Julian day field from the date and the time. Without a
valid date it takes 2000-01-01. A year outside {name}`minimumYear` to
{name}`maximumYear`, or a raw number, gives {name}`DateTime.error`. With a time zone
offset it moves the time to UTC, clears the date and the time, and marks the time as
UTC. -/
def DateTime.computeJulianDay (p : DateTime) : DateTime :=
  if p.validJulianMilliseconds then p else
  let (year, month, day) := if p.validDate then (p.year, p.month, p.day) else (2000, 1, 1)
  if year < minimumYear || year > maximumYear || p.rawSeconds then DateTime.error else
  let p := { p with julianMilliseconds := julianMillisecondsOfDate year month day,
                    validJulianMilliseconds := true }
  if !p.validTime then p else
  let withTime := wrapInt64 (p.julianMilliseconds + (p.hour * 3600000 + p.minute * 60000) +
    doubleToInt64 (p.seconds * 1000 + 0.5))
  if p.timezoneMinutes == 0 then { p with julianMilliseconds := withTime } else
    { p with julianMilliseconds := wrapInt64 (withTime - p.timezoneMinutes * 60000),
             validDate := false, validTime := false, timezoneMinutes := 0, isUtc := true, isLocal := false }

/-- {lit}`computeYMD`: set the date from the Julian day field by
{name}`civilDateOfValidClock`. Without a valid Julian day it takes 2000-01-01; a Julian
day that {name}`validJulianDay` refuses gives {name}`DateTime.error`. -/
def DateTime.computeCivilDate (p : DateTime) : DateTime :=
  if p.validDate then p
  else if !p.validJulianMilliseconds then { p with year := 2000, month := 1, day := 1, validDate := true }
  else if !validJulianDay p.julianMilliseconds then DateTime.error
  else
    let date := civilDateOfValidClock p.julianMilliseconds
    { p with year := date.year, month := date.month, day := date.day, validDate := true }

/-- {lit}`computeHMS`: set the time of day from the Julian day field, after
{name}`DateTime.computeJulianDay`. The seconds are the double
{lit}`(day_ms % 60000)/1000.0`, so they keep the milliseconds. The sum
{lit}`iJD + 43200000` wraps as in {name}`timeOfDayOfClock`. -/
def DateTime.computeTimeOfDay (p : DateTime) : DateTime :=
  if p.validTime then p else
  let p := p.computeJulianDay
  let dayMilliseconds := (wrapInt64 (p.julianMilliseconds + 43200000)).tmod 86400000
  let dayMinutes := dayMilliseconds.tdiv 60000
  { p with seconds := Float.ofInt (dayMilliseconds.tmod 60000) / 1000.0,
           minute := dayMinutes.tmod 60, hour := dayMinutes.tdiv 60,
           rawSeconds := false, validTime := true }

/-- The structure that {lit}`setDateTimeToCurrent` installs for the statement's clock in
Julian-day milliseconds, or {lit}`none` when the clock is zero or less and the call
fails. -/
def DateTime.current (clock : Int) : Option DateTime :=
  if clock > 0 then some { julianMilliseconds := clock, validJulianMilliseconds := true, isUtc := true } else none

/-- The Julian day number of 9999-12-31 24:00:00. {lit}`setRawDateNumber` accepts a
number below it as a Julian day number. -/
def julianDayNumberLimit : Float := 5373484.5

/-- {lit}`setRawDateNumber`: keep the number as raw seconds and, when it is from 0 to
below {name}`julianDayNumberLimit`, also as the Julian day field. A number outside that
range has no Julian day: {name}`DateTime.computeJulianDay` gives an error, unless a
modifier such as {lit}`unixepoch` reads the raw number first. -/
def DateTime.ofRawNumber (number : Float) : DateTime :=
  let raw : DateTime := { seconds := number, rawSeconds := true }
  if number ≥ 0 && number < julianDayNumberLimit then
    { raw with julianMilliseconds := doubleToInt64 (number * 86400000.0 + 0.5),
               validJulianMilliseconds := true }
  else raw

/-- {lit}`clearYMD_HMS_TZ`: mark the date and the time as not valid and clear the time
zone offset, so that later conversions start from the Julian day field. -/
def DateTime.clearDateTimeZone (p : DateTime) : DateTime :=
  { p with validDate := false, validTime := false, timezoneMinutes := 0 }

/-- The bit mask of the months with 31 days ({lit}`0x15aa`): bit {lit}`M` is set for
January, March, May, July, August, October and December. -/
def thirtyOneDayMonthMask : Nat := 0x15aa

/-- {lit}`computeFloor`: set {name}`DateTime.dayOverflow` to the days by which the day of
the month is past the end of the month, or 0. February has 28 days, or 29 in a leap
year of the Gregorian calendar. -/
def DateTime.computeFloor (p : DateTime) : DateTime :=
  let overflow :=
    if p.day ≤ 28 then 0
    else if (1 <<< p.month.toNat) &&& thirtyOneDayMonthMask != 0 then 0
    else if p.month != 2 then (if p.day == 31 then 1 else 0)
    else if p.year.tmod 4 != 0 || (p.year.tmod 100 == 0 && p.year.tmod 400 != 0) then p.day - 28
    else p.day - 29
  { p with dayOverflow := overflow }

end Belay.Sqlite
