import Belay.Sqlite.Date.DateTime
import Belay.Sqlite.NumberConvert

set_option doc.verso true

/-! The parse of a time value text, ported from the pinned SQLite 3.51.0 {lit}`date.c`
(ADR 0012, amendment 5, slice 6f): {lit}`getDigits`, {lit}`parseTimezone`,
{lit}`parseHhMmSs`, {lit}`parseYyyyMmDd` and {lit}`parseDateOrTime`. The text is the
bytes before the first zero byte, as C reads it. A failed parse gives {lit}`none`. The C
parse can change the structure before it fails, but no later branch of
{lit}`parseDateOrTime` that succeeds reads those changes, so the port starts each branch
from the cleared structure. -/

namespace Belay.Sqlite

/-- Read exactly {lit}`count` decimal digits as a number, with the text after them, as
the digit loop of {lit}`getDigits` does. -/
def readDigitCount : Nat → Nat → List UInt8 → Option (Nat × List UInt8)
  | 0, value, bytes => some (value, bytes)
  | count + 1, value, byte :: rest =>
    if isDigitByte byte then readDigitCount count (value * 10 + digitValue byte) rest else none
  | _ + 1, _, [] => none

/-- One field of {lit}`getDigits`: {lit}`count` digits with a value from {lit}`minimum`
to {lit}`maximum`, then the separator byte if one is given. The result is the value and
the text after the separator. -/
def readDateField (count minimum maximum : Nat) (separator : Option UInt8) (bytes : List UInt8) :
    Option (Nat × List UInt8) :=
  match readDigitCount count 0 bytes with
  | none => none
  | some (value, rest) =>
    if value < minimum || value > maximum then none else
    match separator, rest with
    | none, rest => some (value, rest)
    | some expected, byte :: after => if byte == expected then some (value, after) else none
    | some _, [] => none

/-- The greatest year of the field format {lit}`40f` in {lit}`getDigits`. A field of
four digits never exceeds it. -/
def yearFieldMaximum : Nat := 14712

/-- The greatest month of a date field ({lit}`21a` in {lit}`getDigits`); a date offset
modifier also refuses this value. -/
def monthFieldMaximum : Nat := 12

/-- The greatest day of a date field ({lit}`21d`); a date offset modifier also refuses
this value. -/
def dayFieldMaximum : Nat := 31

/-- The greatest hour of a time field ({lit}`20c`): SQLite accepts {lit}`24`. -/
def hourFieldMaximum : Nat := 24

/-- The greatest minute or second of a time field ({lit}`20e`). -/
def minuteFieldMaximum : Nat := 59

/-- The greatest hour of a time zone suffix ({lit}`20b` in {lit}`parseTimezone`). -/
def timezoneHourMaximum : Nat := 14

/-- The text after trailing spaces is empty: the end check of {lit}`parseTimezone`. -/
def onlySpaces (bytes : List UInt8) : Bool := (dropSpaces bytes).isEmpty

/-- {lit}`parseTimezone`: the time zone offset in minutes after the time. Spaces come
first. {lit}`Z` or {lit}`z` is UTC; {lit}`+HH:MM` and {lit}`-HH:MM` with an hour to 14
and a minute to 59 give an offset; no text gives 0. Only spaces can follow. Other text
gives {lit}`none`. The flag is true when the text marks the time as UTC: {lit}`Z`, or
an offset of zero. -/
def parseTimezone (bytes : List UInt8) : Option (Int × Bool) :=
  match dropSpaces bytes with
  | [] => some (0, false)
  | marker :: rest =>
    if marker == 90 || marker == 122 then (if onlySpaces rest then some (0, true) else none)
    else if marker == 45 || marker == 43 then
      match readDateField 2 0 timezoneHourMaximum (some 58) rest with
      | none => none
      | some (hours, rest) => match readDateField 2 0 minuteFieldMaximum none rest with
        | none => none
        | some (minutes, rest) =>
          let offset : Int := (minutes : Int) + hours * 60
          if onlySpaces rest then some (if marker == 45 then -offset else offset, offset == 0) else none
    else none

/-- The fraction of the seconds in {lit}`parseHhMmSs`, digit by digit: the double
{lit}`ms*10.0 + *zDate - '0'`, which C computes from left to right, and the scale
{lit}`rScale`, each times ten. The result is the fraction, the scale and the rest. -/
def readFractionDigits (fraction scale : Float) : List UInt8 → Float × Float × List UInt8
  | byte :: rest =>
    if isDigitByte byte then readFractionDigits (fraction * 10.0 + Float.ofNat byte.toNat - 48.0) (scale * 10.0) rest
    else (fraction, scale, byte :: rest)
  | [] => (fraction, scale, [])

/-- The greatest fraction of a second that {lit}`parseHhMmSs` keeps; a greater fraction
is cut to it, so that rounding to milliseconds cannot reach the next second. -/
def maximumSecondFraction : Float := 0.999

/-- The seconds after {lit}`HH:MM` in {lit}`parseHhMmSs`: {lit}`:SS` with an optional
fraction, or 0 when no colon follows. A fraction is a point and one or more digits. -/
def parseSeconds : List UInt8 → Option (Float × List UInt8)
  | 58 :: rest => match readDateField 2 0 minuteFieldMaximum none rest with
    | none => none
    | some (seconds, 46 :: digit :: after) =>
      if isDigitByte digit then
        let (fraction, scale, after) := readFractionDigits 0 1 (digit :: after)
        let fraction := fraction / scale
        let fraction := if fraction > maximumSecondFraction then maximumSecondFraction else fraction
        some (Float.ofNat seconds + fraction, after)
      else some (Float.ofNat seconds, 46 :: digit :: after)
    | some (seconds, after) => some (Float.ofNat seconds, after)
  | bytes => some (0, bytes)

/-- {lit}`parseHhMmSs`: a time {lit}`HH:MM`, {lit}`HH:MM:SS` or {lit}`HH:MM:SS.FFF` with
an hour to 24, then {name}`parseTimezone`. The result has a valid time and no valid
Julian day. -/
def parseTimeOfDay (bytes : List UInt8) : Option DateTime :=
  match readDateField 2 0 hourFieldMaximum (some 58) bytes with
  | none => none
  | some (hour, rest) => match readDateField 2 0 minuteFieldMaximum none rest with
    | none => none
    | some (minute, rest) => match parseSeconds rest with
      | none => none
      | some (seconds, rest) => match parseTimezone rest with
        | none => none
        | some (offset, isUtc) => some { hour, minute, seconds, timezoneMinutes := offset, validTime := true, isUtc }

/-- Whether a byte is skipped between a date and its time: a space or {lit}`T`. -/
def isDateTimeSeparator (byte : UInt8) : Bool := isSpaceByte byte || byte == 84

/-- {lit}`parseYyyyMmDd`: a date {lit}`YYYY-MM-DD` with an optional minus, a month 1 to
12 and a day 1 to 31, then spaces and {lit}`T` bytes, then a time or the end. It sets
{name}`DateTime.dayOverflow` by {name}`DateTime.computeFloor`. With a time zone offset
it calls {name}`DateTime.computeJulianDay` at once. -/
def parseCalendarDate (bytes : List UInt8) : Option DateTime :=
  let (negative, body) := match bytes with
    | 45 :: rest => (true, rest)
    | _ => (false, bytes)
  match readDateField 4 0 yearFieldMaximum (some 45) body with
  | none => none
  | some (year, rest) => match readDateField 2 1 monthFieldMaximum (some 45) rest with
    | none => none
    | some (month, rest) => match readDateField 2 1 dayFieldMaximum none rest with
      | none => none
      | some (day, rest) =>
        let rest := rest.dropWhile isDateTimeSeparator
        let time? := match parseTimeOfDay rest with
          | some time => some time
          | none => if rest.isEmpty then some {} else none
        match time? with
        | none => none
        | some time =>
          let date := { time with year := if negative then -(year : Int) else year, month, day,
                                  validDate := true }.computeFloor
          some (if date.timezoneMinutes != 0 then date.computeJulianDay else date)

/-- The ASCII lower case of a byte, as {lit}`sqlite3UpperToLower` maps it. -/
def lowerAsciiByte (byte : UInt8) : UInt8 := if 65 ≤ byte && byte ≤ 90 then byte + 32 else byte

/-- Whether the text equals a lower-case keyword without regard to ASCII case, as
{lit}`sqlite3StrICmp` compares. -/
def equalsKeyword (bytes keyword : List UInt8) : Bool := bytes.map lowerAsciiByte == keyword

/-- The keyword {lit}`now` in lower-case ASCII bytes. -/
def nowKeyword : List UInt8 := [110, 111, 119]

/-- The keyword {lit}`subsec` in lower-case ASCII bytes. -/
def subsecKeyword : List UInt8 := [115, 117, 98, 115, 101, 99]

/-- The keyword {lit}`subsecond` in lower-case ASCII bytes. -/
def subsecondKeyword : List UInt8 := subsecKeyword ++ [111, 110, 100]

/-- {lit}`parseDateOrTime`: a date, a time, {lit}`now`, a number that
{name}`atof` reads in full (a Julian day number), or {lit}`subsec` or {lit}`subsecond`,
which is {lit}`now` with milliseconds shown. {lit}`now` reads the statement's clock in
Julian-day milliseconds. -/
def parseDateOrTime (clock : Int) (bytes : List UInt8) : Option DateTime :=
  match parseCalendarDate bytes with
  | some date => some date
  | none => match parseTimeOfDay bytes with
    | some time => some time
    | none =>
      if equalsKeyword bytes nowKeyword then DateTime.current clock else
      let (number, code) := atof bytes
      if code > 0 then some (DateTime.ofRawNumber number)
      else if equalsKeyword bytes subsecKeyword || equalsKeyword bytes subsecondKeyword then
        (DateTime.current clock).map fun current => { current with useSubsecond := true }
      else none

end Belay.Sqlite
