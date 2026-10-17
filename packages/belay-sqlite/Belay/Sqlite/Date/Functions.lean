import Belay.Sqlite.Arithmetic
import Belay.Sqlite.Date.Modifier
import Belay.Sqlite.Resolution.DateFunction

set_option doc.verso true

/-! The six date and time functions with their modifiers, ported from the pinned SQLite
3.51.0 {lit}`date.c` (ADR 0012, amendment 5, slices 6f and 6g): {lit}`isDate`, then
{lit}`juliandayFunc`, {lit}`unixepochFunc`, {lit}`datetimeFunc`, {lit}`timeFunc`,
{lit}`dateFunc` and {lit}`strftimeFunc`. The model calls these functions only where
SQLite's {lit}`sqlite3NotPureFunc` passes, so {lit}`now` always reads the clock. -/

namespace Belay.Sqlite

/-- The bytes before the first zero byte: the text that C reads through the pointer of
{lit}`sqlite3_value_text`. -/
def bytesBeforeNul (bytes : List UInt8) : List UInt8 := bytes.takeWhile (· != 0)

/-- The text of a value as {lit}`sqlite3_value_text` gives it to C code: NULL has none;
a number is its text; TEXT and BLOB are their bytes up to the first zero byte. -/
def Value.sqliteValueText? : Value → Option (List UInt8)
  | .null => none
  | value@(.integer _) | value@(.real _) => some (bytesBeforeNul value.textBytes)
  | .text bytes | .blob bytes => some (bytesBeforeNul bytes)

/-- The structure of the time value argument after {lit}`setRawDateNumber` or
{lit}`parseDateOrTime`, or {lit}`none` when it is NULL or SQLite cannot read it. An
INTEGER or a REAL is a Julian day number; TEXT and BLOB are parsed. -/
def DateTime.ofArgument (clock : Int) : Value → Option DateTime
  | .integer number => some (DateTime.ofRawNumber (Float.ofInt number))
  | .real bits => some (DateTime.ofRawNumber (Float.ofBits bits))
  | .text bytes | .blob bytes => parseDateOrTime clock (bytesBeforeNul bytes)
  | .null => none

/-- The modifier loop of {lit}`isDate`: apply each modifier in order by
{name}`DateTime.applyModifier`, with its position from {lit}`index`. A NULL modifier or
a refused modifier gives {lit}`none`. -/
def DateTime.applyModifiers : Nat → List Value → DateTime → Option DateTime
  | _, [], p => some p
  | index, modifier :: rest, p => match modifier.sqliteValueText? with
    | none => none
    | some text => match p.applyModifier index text with
      | none => none
      | some p => DateTime.applyModifiers (index + 1) rest p

/-- {lit}`isDate`: the date and time of the time value argument after its modifiers, or
{lit}`none`, which makes the function NULL. With no argument it is {lit}`now` and has no
range check, so a clock after 9999 still gives a value. Else, after the modifiers,
{name}`DateTime.computeJulianDay` must succeed and {name}`validJulianDay` must accept the
result. Without modifiers, a parsed date with a day after 28 is marked as not valid, so
that {name}`DateTime.computeCivilDate` normalizes it: {lit}`2023-02-31` is
{lit}`2023-03-03`. -/
def DateTime.ofArguments (clock : Int) : List Value → Option DateTime
  | [] => DateTime.current clock
  | argument :: modifiers => match DateTime.ofArgument clock argument with
    | none => none
    | some parsed => match DateTime.applyModifiers 1 modifiers parsed with
      | none => none
      | some modified =>
        let p := modified.computeJulianDay
        if p.isError || !validJulianDay p.julianMilliseconds then none
        else some (if modifiers.isEmpty && p.validDate && p.day > 28 then { p with validDate := false } else p)

/-- The time text {lit}`HH:MM:SS`, or {lit}`HH:MM:SS.SSS` with {lit}`subsec`, of
{lit}`timeFunc` and {lit}`datetimeFunc` after {lit}`computeHMS`. The seconds are
truncated, or rounded to milliseconds with {lit}`subsec`. -/
def DateTime.timeText (x : DateTime) : List UInt8 :=
  let secondsText :=
    if x.useSubsecond then
      let milliseconds := doubleToInt32 (1000.0 * x.seconds + 0.5)
      [lastDigitByte (milliseconds.tdiv 10000), lastDigitByte (milliseconds.tdiv 1000), 46,
        lastDigitByte (milliseconds.tdiv 100), lastDigitByte (milliseconds.tdiv 10), lastDigitByte milliseconds]
    else twoDigitBytes (doubleToInt32 x.seconds)
  twoDigitBytes x.hour ++ [58] ++ twoDigitBytes x.minute ++ [58] ++ secondsText

/-- The date text {lit}`YYYY-MM-DD` of {lit}`dateFunc` and {lit}`datetimeFunc` after
{lit}`computeYMD`, by {name}`dateText`. -/
def DateTime.dateText (x : DateTime) : List UInt8 := Belay.Sqlite.dateText ⟨x.year, x.month, x.day⟩

/-- {lit}`strftimeFunc`: the format text of the first argument with the date and time of
the rest, after {lit}`computeJD` and {lit}`computeYMD_HMS`. NULL when there is no
argument, the format is NULL, the time value or a modifier cannot be read, or the format
has an unknown specifier. An empty result is the empty text. -/
def strftimeValue (clock : Int) : List Value → Value
  | [] => .null
  | format :: timeValues => match format.sqliteValueText?, DateTime.ofArguments clock timeValues with
    | some formatBytes, some x =>
      match strftimeText x.computeJulianDay.computeCivilDate.computeTimeOfDay formatBytes with
      | some text => .text text
      | none => .null
    | some _, none | none, some _ | none, none => .null

/-- The value that SQLite 3.51.0 gives for a call of the date and time function with
these SQL argument values, when the statement's clock ({lit}`xCurrentTimeInt64`) is
{lit}`clock` Julian-day milliseconds. The arguments are, for {lit}`strftime`, the format
and then the time value and its modifiers; for the other functions, the time value and
its modifiers. No time value is {lit}`now`. Text results are TEXT, {lit}`julianday` is a REAL and
{lit}`unixepoch` is an INTEGER, or a REAL with {lit}`subsec`. A value that SQLite cannot
read, or a modifier that SQLite refuses, gives NULL. For example,
{lean}`Resolved.DateFunction.date.value 0 [.integer 2451545]` is the text
{lit}`2000-01-01`. -/
def Resolved.DateFunction.value (function : Resolved.DateFunction) (clock : Int) (arguments : List Value) : Value :=
  match function with
  | .strftime => strftimeValue clock arguments
  | .julianday | .unixepoch | .datetime | .time | .date =>
    match DateTime.ofArguments clock arguments with
    | none => .null
    | some x => match function with
      | .julianday => realValue (Float.ofInt x.computeJulianDay.julianMilliseconds / 86400000.0)
      | .unixepoch =>
        let x := x.computeJulianDay
        if x.useSubsecond then realValue (Float.ofInt (x.julianMilliseconds - unixEpochJulianMilliseconds) / 1000.0)
        else .integer (x.julianMilliseconds.tdiv 1000 - unixEpochJulianMilliseconds / 1000)
      | .datetime =>
        let x := x.computeCivilDate.computeTimeOfDay
        .text (x.dateText ++ [32] ++ x.timeText)
      | .time => .text x.computeTimeOfDay.timeText
      | .date => .text x.computeCivilDate.dateText
      | .strftime => strftimeValue clock arguments

end Belay.Sqlite
