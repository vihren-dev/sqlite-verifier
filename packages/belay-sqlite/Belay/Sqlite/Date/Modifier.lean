import Belay.Sqlite.Date.LocalTime
import Belay.Sqlite.Date.NumericModifier

set_option doc.verso true

/-! {lit}`parseModifier` of the pinned SQLite 3.51.0 {lit}`date.c` (ADR 0012,
amendment 5, slice 6g): the keyword modifiers and the dispatch on the first byte. A
modifier is the text of the argument up to its first zero byte. SQLite chooses a branch
by the ASCII lower case of the first byte, then compares the whole text without regard
to ASCII case. The modifiers {lit}`auto`, {lit}`julianday` and {lit}`unixepoch` must be
the first modifier. -/

namespace Belay.Sqlite

/-- The modifier keyword {lit}`auto` in lower-case ASCII bytes. -/
def autoKeyword : List UInt8 := [97, 117, 116, 111]

/-- The modifier keyword {lit}`ceiling` in lower-case ASCII bytes. -/
def ceilingKeyword : List UInt8 := [99, 101, 105, 108, 105, 110, 103]

/-- The modifier keyword {lit}`floor` in lower-case ASCII bytes. -/
def floorKeyword : List UInt8 := [102, 108, 111, 111, 114]

/-- The modifier keyword {lit}`julianday` in lower-case ASCII bytes. -/
def juliandayKeyword : List UInt8 := [106, 117, 108, 105, 97, 110, 100, 97, 121]

/-- The modifier keyword {lit}`localtime` in lower-case ASCII bytes. -/
def localtimeKeyword : List UInt8 := [108, 111, 99, 97, 108, 116, 105, 109, 101]

/-- The modifier keyword {lit}`unixepoch` in lower-case ASCII bytes. -/
def unixepochKeyword : List UInt8 := [117, 110, 105, 120, 101, 112, 111, 99, 104]

/-- The modifier keyword {lit}`utc` in lower-case ASCII bytes. -/
def utcKeyword : List UInt8 := [117, 116, 99]

/-- The modifier keyword {lit}`weekday` and its space in lower-case ASCII bytes. -/
def weekdayPrefix : List UInt8 := [119, 101, 101, 107, 100, 97, 121, 32]

/-- The modifier keyword {lit}`start of` and its space in lower-case ASCII bytes. -/
def startOfPrefix : List UInt8 := [115, 116, 97, 114, 116, 32, 111, 102, 32]

/-- The least raw number that {lit}`auto` reads as Unix seconds: -4713-11-24 12:00:00. -/
def autoUnixSecondsMinimum : Float := -210866760000.0

/-- The greatest raw number that {lit}`auto` reads as Unix seconds: 9999-12-31 23:59:59. -/
def autoUnixSecondsMaximum : Float := 253402300799.0

/-- The Julian day milliseconds of 10000-01-01 00:00:00, where {lit}`unixepoch` stops. -/
def julianMillisecondsLimit : Float := 464269060800000.0

/-- The Julian day of Unix seconds held as raw seconds: {lit}`s*1000.0 + 210866760000000.0`,
rounded to milliseconds, with the date, time and raw number cleared. -/
def DateTime.ofUnixSeconds (p : DateTime) (julianMilliseconds : Float) : DateTime :=
  { p.clearDateTimeZone with julianMilliseconds := doubleToInt64 (julianMilliseconds + 0.5),
                             validJulianMilliseconds := true, rawSeconds := false }

/-- {lit}`autoAdjustDate`: a raw number without a Julian day is read as Unix seconds when
it is from {name}`autoUnixSecondsMinimum` to {name}`autoUnixSecondsMaximum`; else the
structure does not change. A raw number that is a Julian day stays one. -/
def DateTime.autoAdjust (p : DateTime) : DateTime :=
  if !p.rawSeconds || p.validJulianMilliseconds then { p with rawSeconds := false }
  else if p.seconds ≥ autoUnixSecondsMinimum && p.seconds ≤ autoUnixSecondsMaximum then
    p.ofUnixSeconds (p.seconds * 1000.0 + Float.ofInt unixEpochJulianMilliseconds)
  else p

/-- The modifier {lit}`weekday N` for a whole number {lit}`N` from 0 (Sunday) to 6: move
the date forward by 0 to 6 days to that day of the week, at the same time. The number is
the text after {lit}`weekday ` that {name}`atof` reads in full. -/
def DateTime.applyWeekday (p : DateTime) (numberText : List UInt8) : Option DateTime :=
  let (number, code) := atof numberText
  let weekday := doubleToInt32 number
  if code ≤ 0 || number < 0 || number ≥ 7 || Float.ofInt weekday != number then none else
  let p := { p.computeCivilDate.computeTimeOfDay with timezoneMinutes := 0, validJulianMilliseconds := false }.computeJulianDay
  let current := ((p.julianMilliseconds + 129600000).tdiv 86400000).tmod 7
  let current := if current > weekday then current - 7 else current
  some { p with julianMilliseconds := wrapInt64 (p.julianMilliseconds + (weekday - current) * 86400000) }.clearDateTimeZone

/-- The modifiers {lit}`start of month`, {lit}`start of year` and {lit}`start of day`,
with {lit}`unit` the text after {lit}`start of `: set the time to midnight, and the day
or the month and day to 1. A structure without a valid Julian day, date or time is
refused. -/
def DateTime.applyStartOf (p : DateTime) (unit : List UInt8) : Option DateTime :=
  if !p.validJulianMilliseconds && !p.validDate && !p.validTime then none else
  let p := { p.computeCivilDate with validTime := true, hour := 0, minute := 0, seconds := 0,
                                     rawSeconds := false, timezoneMinutes := 0, validJulianMilliseconds := false }
  if equalsKeyword unit TimeUnit.month.name then some { p with day := 1 }
  else if equalsKeyword unit TimeUnit.year.name then some { p with month := 1, day := 1 }
  else if equalsKeyword unit TimeUnit.day.name then some p
  else none

/-- Whether the text starts with a lower-case keyword without regard to ASCII case, as
{lit}`sqlite3_strnicmp` compares the length of the keyword. -/
def startsWithKeyword (text keyword : List UInt8) : Bool := (text.take keyword.length).map lowerAsciiByte == keyword

/-- The keyword modifiers that start with {lit}`s`: {lit}`start of ...`, or
{lit}`subsec` and {lit}`subsecond`, which show milliseconds. -/
def DateTime.applyStartOrSubsecond (p : DateTime) (text : List UInt8) : Option DateTime :=
  if startsWithKeyword text startOfPrefix then p.applyStartOf (text.drop startOfPrefix.length)
  else if equalsKeyword text subsecKeyword || equalsKeyword text subsecondKeyword then some { p with useSubsecond := true }
  else none

/-- The keyword modifiers that start with {lit}`u`: {lit}`unixepoch` reads a raw number
as Unix seconds below {name}`julianMillisecondsLimit`, only as the first modifier;
{lit}`utc` is {name}`DateTime.applyUtc`. -/
def DateTime.applyUnixepochOrUtc (p : DateTime) (index : Nat) (text : List UInt8) : Option DateTime :=
  if equalsKeyword text unixepochKeyword && p.rawSeconds then
    let julianMilliseconds := p.seconds * 1000.0 + Float.ofInt unixEpochJulianMilliseconds
    if index > 1 || julianMilliseconds < 0 || julianMilliseconds ≥ julianMillisecondsLimit then none
    else some (p.ofUnixSeconds julianMilliseconds)
  else if equalsKeyword text utcKeyword then some p.applyUtc
  else none

/-- {lit}`parseModifier`: apply the modifier text to the structure, or {lit}`none` when
SQLite refuses it. The {lit}`index` is the position of the modifier, from 1. The
keywords are {lit}`auto`, {lit}`ceiling`, {lit}`floor`, {lit}`julianday`,
{lit}`localtime`, {lit}`unixepoch`, {lit}`utc`, {lit}`weekday N`, {lit}`start of ...`,
{lit}`subsec` and {lit}`subsecond`; a text that starts with a sign or a digit is
{name}`DateTime.applyNumericModifier`. -/
def DateTime.applyModifier (p : DateTime) (index : Nat) (text : List UInt8) : Option DateTime :=
  match text with
  | [] => none
  | first :: _ =>
    let initial := lowerAsciiByte first
    if initial == 97 then
      if equalsKeyword text autoKeyword && index ≤ 1 then some p.autoAdjust else none
    else if initial == 99 then
      if equalsKeyword text ceilingKeyword then
        some { p.computeJulianDay.clearDateTimeZone with dayOverflow := 0 }
      else none
    else if initial == 102 then
      if equalsKeyword text floorKeyword then
        let p := p.computeJulianDay
        some { p with julianMilliseconds := wrapInt64 (p.julianMilliseconds - p.dayOverflow * 86400000) }.clearDateTimeZone
      else none
    else if initial == 106 then
      if equalsKeyword text juliandayKeyword && index ≤ 1 &&
        p.validJulianMilliseconds && p.rawSeconds then some { p with rawSeconds := false } else none
    else if initial == 108 then
      if equalsKeyword text localtimeKeyword then some p.applyLocaltime else none
    else if initial == 117 then p.applyUnixepochOrUtc index text
    else if initial == 119 then
      if startsWithKeyword text weekdayPrefix then p.applyWeekday (text.drop weekdayPrefix.length) else none
    else if initial == 115 then p.applyStartOrSubsecond text
    else if first == 43 || first == 45 || isDigitByte first then p.applyNumericModifier text
    else none

end Belay.Sqlite
