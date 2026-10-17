import Belay.Sqlite.RealText

set_option doc.verso true

/-! The conversions of SQLite's own printf ({lit}`sqlite3_str_vappendf` of the pinned
3.51.0 source) that {lit}`strftimeFunc` uses (ADR 0012, amendment 5, slice 6f):
{lit}`%d` with a width, with or without zeros, {lit}`%lld`, {lit}`%.3f`, {lit}`%06.3f`
and {lit}`%.16g`. The floating-point conversions use {lit}`sqlite3FpDecode` without the
{lit}`!` flag, so they round to at most 16 significant digits. Every double that
{lit}`strftimeFunc` formats is finite; the port has no branch for NaN or infinity. -/

namespace Belay.Sqlite

/-- The ASCII byte of a decimal digit. -/
def digitByte (digit : Nat) : UInt8 := (48 + digit).toUInt8

/-- The bytes of the decimal digits of a natural number, most significant first. -/
def decimalDigitBytes (value : Nat) : List UInt8 := (decimalDigits value).map digitByte

/-- An integer by {lit}`%Wd`, {lit}`%0Wd` or {lit}`%lld` (width 0): a minus for a
negative number, the digits of its magnitude, and padding to the width. With
{lit}`zeroPad` the zeros go after the sign; else spaces go before it. -/
def formatInteger (width : Nat) (zeroPad : Bool) (value : Int) : List UInt8 :=
  let digits := decimalDigitBytes value.natAbs
  let sign : List UInt8 := if value < 0 then [45] else []
  let precision := if zeroPad then width - sign.length else 0
  let body := sign ++ List.replicate (precision - digits.length) 48 ++ digits
  List.replicate (width - body.length) 32 ++ body

/-- The greatest number of significant digits of {lit}`sqlite3FpDecode` without the
{lit}`!` flag. -/
def printfDigitLimit : Nat := 16

/-- {lit}`sqlite3FpDecode` of a double: its sign, its significant digits and the position
of the decimal point after the first digit ({lit}`iDP`). A positive {lit}`round` keeps
that many significant digits; zero or less keeps {lit}`-round` digits after the decimal
point. Zero gives the digit 0 and the point 1. -/
def decodeDouble (value : Float) (round : Int) : Bool × List Nat × Int :=
  if value == 0 then (false, [0], 1) else
  let negative := value < 0
  let (digits, exponent) := fpDigits (if negative then -value else value)
  let point : Int := digits.length + exponent
  let (digits, point, round) :=
    if round > 0 then (digits, point, round) else
    let round := point - round
    if round == 0 && digits.headD 0 ≥ 5 then (0 :: digits, point + 1, 1) else (digits, point, round)
  let (digits, point) := roundDigits round.toNat printfDigitLimit digits point
  (negative, digits, point)

/-- The fixed-point bytes of decoded digits with {lit}`precision` digits after the
point, as the {lit}`etFLOAT` branch writes them: the integer digits (or one zero), the
point when the precision is positive, zeros before the first significant digit, then
the digits, with zeros past the last one. -/
def fixedDigitBytes (digits : List Nat) (point : Int) (precision : Nat) : List UInt8 :=
  let byteAt := fun (index : Nat) => digitByte (digits.getD index 0)
  let whole := if point ≤ 0 then [48] else (List.range point.toNat).map byteAt
  let used := if point ≤ 0 then 0 else point.toNat
  let zeros := min precision (if point < 0 then (-point).toNat else 0)
  let fraction := List.replicate zeros 48 ++ (List.range (precision - zeros)).map (fun index => byteAt (used + index))
  whole ++ (if precision > 0 then 46 :: fraction else [])

/-- A double by {lit}`%.Pf` or {lit}`%0W.Pf`: the sign, then {name}`fixedDigitBytes`
after rounding to {lit}`precision` digits after the point. With {lit}`zeroPad`, zeros
after the sign fill the text to the width. -/
def formatFixed (width : Nat) (zeroPad : Bool) (precision : Nat) (value : Float) : List UInt8 :=
  let (negative, digits, point) := decodeDouble value (-(precision : Int))
  let sign : List UInt8 := if negative then [45] else []
  let body := fixedDigitBytes digits point precision
  let padding := if zeroPad then width - (sign.length + body.length) else 0
  sign ++ List.replicate padding 48 ++ body

/-- Remove the trailing zeros after a point, then the point if no digit follows it, as
{lit}`%g` does without the {lit}`#` and {lit}`!` flags. -/
def trimGenericFraction (bytes : List UInt8) : List UInt8 :=
  if !bytes.contains 46 then bytes else
  let trimmed := (bytes.reverse.dropWhile (· == 48)).reverse
  if trimmed.getLast? == some 46 then trimmed.dropLast else trimmed

/-- The exponent suffix of {lit}`%e` as bytes: {lit}`e`, the sign, and two or three
digits. -/
def exponentSuffixBytes (exponent : Int) : List UInt8 :=
  let magnitude := exponent.natAbs
  let hundreds := if magnitude ≥ 100 then [digitByte (magnitude / 100)] else []
  [101, if exponent < 0 then 45 else 43] ++ hundreds ++ [digitByte (magnitude % 100 / 10), digitByte (magnitude % 10)]

/-- The significant digits of {lit}`%.16g`, which {lit}`strftime` uses for {lit}`%J`. -/
def julianDayTextDigits : Nat := 16

/-- A double by {lit}`%.16g`: {name}`julianDayTextDigits` significant digits, plain
notation for a decimal exponent from {name}`plainExponentMinimum` to 15, else exponent
notation, with {name}`trimGenericFraction`. -/
def formatGeneric16 (value : Float) : List UInt8 :=
  let (negative, digits, point) := decodeDouble value julianDayTextDigits
  let sign : List UInt8 := if negative then [45] else []
  let exponent := point - 1
  let precision : Int := julianDayTextDigits - 1
  if exponent < plainExponentMinimum || exponent > precision then
    sign ++ trimGenericFraction (fixedDigitBytes digits 1 precision.toNat) ++ exponentSuffixBytes exponent
  else sign ++ trimGenericFraction (fixedDigitBytes digits point (precision - exponent).toNat)

end Belay.Sqlite
