import Belay.Sqlite.Date.ModifierArithmetic

set_option doc.verso true

/-! The digit branch of {lit}`parseModifier` in the pinned SQLite 3.51.0 {lit}`date.c`
(ADR 0012, amendment 5, slice 6g): a modifier that starts with {lit}`+`, {lit}`-` or a
digit. It reads a number, then decides by the byte after it: a minus starts
{lit}`±YYYY-MM-DD`, a colon starts {lit}`±HH:MM`, and other text is a unit. -/

namespace Belay.Sqlite

/-- The shortest unit text that the unit form accepts, before a final {lit}`s` is
removed. -/
def unitTextMinimum : Nat := 3

/-- The longest unit text that the unit form accepts, before a final {lit}`s` is
removed. -/
def unitTextMaximum : Nat := 10

/-- The unit form {lit}`NNN units`: the text after the number, after spaces, with one
final {lit}`s` or {lit}`S` removed, names a unit of {name}`TimeUnit.find?` that accepts
the amount. -/
def DateTime.applyUnitModifier (p : DateTime) (amount : Float) (rest : List UInt8) : Option DateTime :=
  let text := dropSpaces rest
  if text.length < unitTextMinimum || text.length > unitTextMaximum then none else
  let text := if text.getLast?.map lowerAsciiByte == some 115 then text.dropLast else text
  (TimeUnit.find? text amount).map fun unit => p.addUnits unit amount

/-- Whether a time text starts with {lit}`HH:MM` as {lit}`getDigits` reads it with the
format {lit}`20c:20e`: an hour to 24 and a minute to 59. -/
def startsWithHourMinute (text : List UInt8) : Bool :=
  match readDateField 2 0 24 (some 58) text with
  | none => false
  | some (_, rest) => (readDateField 2 0 59 none rest).isSome

/-- The form {lit}`±YYYY-MM-DD[ HH:MM[:SS[.SSS]]]` after a sign: four or five year
digits, a month below 12 and a day below 31. A time after one space is added or
subtracted by {name}`DateTime.addTimeOffset`. -/
def DateTime.applyDateModifier (p : DateTime) (negative : Bool) (yearDigits : Nat) (body : List UInt8) :
    Option DateTime :=
  match readDateField yearDigits 0 yearFieldMaximum (some 45) body with
  | none => none
  | some (years, rest) => match readDateField 2 0 12 (some 45) rest with
    | none => none
    | some (months, rest) => match readDateField 2 0 31 none rest with
      | none => none
      | some (days, rest) =>
        if months ≥ 12 || days ≥ 31 then none else
        let p := p.addDateOffset negative years months days
        match rest with
        | [] => some p
        | separator :: time =>
          if isSpaceByte separator && startsWithHourMinute time then p.addTimeOffset negative time else none

/-- The digit branch of {lit}`parseModifier`: the number before {name}`numberEnd` must
be a number that {name}`atof` reads in full. A minus after it needs a sign at the start
and gives {name}`DateTime.applyDateModifier`; a colon gives
{name}`DateTime.addTimeOffset` on the text without its sign; other text gives
{name}`DateTime.applyUnitModifier`. -/
def DateTime.applyNumericModifier (p : DateTime) (text : List UInt8) : Option DateTime :=
  match text with
  | [] => none
  | first :: body =>
    let length := numberEnd body 1 body
    let (amount, code) := atof (text.take length)
    if code ≤ 0 then none else
    let negative := first == 45
    match text.drop length with
    | 45 :: _ => if first == 43 || first == 45 then p.applyDateModifier negative (length - 1) body else none
    | 58 :: _ => p.addTimeOffset negative (if isDigitByte first then text else body)
    | rest => p.applyUnitModifier amount rest

end Belay.Sqlite
