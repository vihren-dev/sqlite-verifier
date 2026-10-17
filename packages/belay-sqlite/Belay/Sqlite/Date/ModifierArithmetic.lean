import Belay.Sqlite.Date.Parse

set_option doc.verso true

/-! The arithmetic modifiers of {lit}`parseModifier` in the pinned SQLite 3.51.0
{lit}`date.c` (ADR 0012, amendment 5, slice 6g): {lit}`NNN days` and the other units,
{lit}`±YYYY-MM-DD` with an optional time, and {lit}`±HH:MM[:SS[.SSS]]`. Each function
returns the new structure, or {lit}`none` when SQLite refuses the modifier. -/

namespace Belay.Sqlite

/-- The units of the modifier {lit}`NNN units` (the table {lit}`aXformType`). -/
inductive TimeUnit where
  /-- {lit}`second`. -/
  | second
  /-- {lit}`minute`. -/
  | minute
  /-- {lit}`hour`. -/
  | hour
  /-- {lit}`day`. -/
  | day
  /-- {lit}`month`: whole months move the month, a fraction counts 30 days. -/
  | month
  /-- {lit}`year`: whole years move the year, a fraction counts 365 days. -/
  | year
  deriving Repr, DecidableEq

/-- The units in the order of the table {lit}`aXformType`. -/
def TimeUnit.all : List TimeUnit := [.second, .minute, .hour, .day, .month, .year]

/-- The name of a unit in lower-case ASCII bytes. -/
def TimeUnit.name : TimeUnit → List UInt8
  | .second => [115, 101, 99, 111, 110, 100]
  | .minute => [109, 105, 110, 117, 116, 101]
  | .hour => [104, 111, 117, 114]
  | .day => [100, 97, 121]
  | .month => [109, 111, 110, 116, 104]
  | .year => [121, 101, 97, 114]

/-- The bound {lit}`rLimit` of the amount: the amount must be greater than its negative
and less than it. SQLite stores the bound as a C {lit}`float`, so the values are the
single-precision roundings of {lit}`4.6427e+14`, {lit}`7.7379e+12` and
{lit}`1.2897e+11`. -/
def TimeUnit.amountLimit : TimeUnit → Float
  | .second => 464269992787968.0
  | .minute => 7737900007424.0
  | .hour => 128969998336.0
  | .day => 5373485.0
  | .month => 176546.0
  | .year => 14713.0

/-- The seconds of one unit ({lit}`rXform`). -/
def TimeUnit.seconds : TimeUnit → Float
  | .second => 1.0
  | .minute => 60.0
  | .hour => 3600.0
  | .day => 86400.0
  | .month => 2592000.0
  | .year => 31536000.0

/-- The unit whose name the text equals without regard to ASCII case and whose bound
accepts the amount, as the loop over {lit}`aXformType` finds it. -/
def TimeUnit.find? (text : List UInt8) (amount : Float) : Option TimeUnit :=
  TimeUnit.all.find? fun unit =>
    text.map lowerAsciiByte == unit.name && amount > -unit.amountLimit && amount < unit.amountLimit

/-- Bring the month into 1 to 12 and carry whole years into the year, with C's
truncating division: {lit}`x = M>0 ? (M-1)/12 : (M-12)/12`. -/
def DateTime.normalizeMonth (p : DateTime) : DateTime :=
  let carry := if p.month > 0 then (p.month - 1).tdiv 12 else (p.month - 12).tdiv 12
  { p with year := p.year + carry, month := p.month - carry * 12 }

/-- Add an amount of a unit, as the end of the digit branch of {lit}`parseModifier`
does. Whole months and years change the date fields first and set
{name}`DateTime.dayOverflow`; the rest of the amount is added as milliseconds, rounded
away from zero. -/
def DateTime.addUnits (p : DateTime) (unit : TimeUnit) (amount : Float) : DateTime :=
  let p := { p.computeJulianDay with dayOverflow := 0 }
  let rounder : Float := if amount < 0 then -0.5 else 0.5
  let whole := doubleToInt32 amount
  let (p, rest) := match unit with
    | .month =>
      let p := p.computeCivilDate.computeTimeOfDay
      ({ ({ p with month := p.month + whole }).normalizeMonth.computeFloor with validJulianMilliseconds := false },
        amount - Float.ofInt whole)
    | .year =>
      let p := p.computeCivilDate.computeTimeOfDay
      ({ ({ p with year := p.year + whole }).computeFloor with validJulianMilliseconds := false },
        amount - Float.ofInt whole)
    | .second | .minute | .hour | .day => (p, amount)
  let p := p.computeJulianDay
  { p with julianMilliseconds :=
      wrapInt64 (p.julianMilliseconds + doubleToInt64 (rest * 1000.0 * unit.seconds + rounder)) }.clearDateTimeZone

/-- The modifier {lit}`±YYYY-MM-DD`: add or subtract years, months (0 to 11) and days (0
to 30). The years and months change the date fields, then {name}`DateTime.computeFloor`
runs, then the days are added to the Julian day. -/
def DateTime.addDateOffset (p : DateTime) (negative : Bool) (years months days : Nat) : DateTime :=
  let p := { p.computeCivilDate.computeTimeOfDay with validJulianMilliseconds := false }
  let (year, month, dayDelta) : Int × Int × Int :=
    if negative then (p.year - years, p.month - months, -(days : Int)) else (p.year + years, p.month + months, days)
  let p := ({ p with year, month }).normalizeMonth.computeFloor.computeJulianDay
  { p with validTime := false, validDate := false,
           julianMilliseconds := wrapInt64 (p.julianMilliseconds + dayDelta * 86400000) }

/-- The milliseconds of a time modifier: the time of {name}`parseTimeOfDay`, after its
own time zone offset, modulo one day. {lit}`24:00` gives 0. -/
def timeOffsetMilliseconds (time : DateTime) : Int :=
  let sinceMidnight := time.computeJulianDay.julianMilliseconds - 43200000
  sinceMidnight - sinceMidnight.tdiv 86400000 * 86400000

/-- The modifier {lit}`±HH:MM[:SS[.SSS]]`: add or subtract the time of day of the text,
or {lit}`none` when {name}`parseTimeOfDay` refuses it. -/
def DateTime.addTimeOffset (p : DateTime) (negative : Bool) (text : List UInt8) : Option DateTime :=
  (parseTimeOfDay text).map fun time =>
    let offset := timeOffsetMilliseconds time
    let p := p.computeJulianDay.clearDateTimeZone
    { p with julianMilliseconds := wrapInt64 (p.julianMilliseconds + if negative then -offset else offset) }

/-- The end of the number in a digit modifier, as the first loop of the digit branch
finds it: the position of the first colon or space after the first byte, or of a minus
after four or five year digits; else the end of the text. -/
def numberEnd (body : List UInt8) : Nat → List UInt8 → Nat
  | index, [] => index
  | index, byte :: rest =>
    if byte == 58 || isSpaceByte byte then index
    else if byte == 45 && ((index == 5 && (readDateField 4 0 yearFieldMaximum none body).isSome) ||
        (index == 6 && (readDateField 5 0 yearFieldMaximum none body).isSome)) then index
    else numberEnd body (index + 1) rest

end Belay.Sqlite
