import Belay.Sqlite.LiteralData
import Belay.Sqlite.Profile
import Belay.Sqlite.Resolved

set_option doc.verso true

/-! Conversion of literal expressions to stored values during name resolution.
Numeric literal text follows SQLite's rules, which are not lexical: separators are
removed, a hexadecimal literal is a 64-bit two's-complement integer, and a decimal
integer outside the 64-bit range is a REAL value. The first scope models no REAL
values and no time functions, so those are model restrictions. -/

namespace Belay.Sqlite

/-- Why an expression has no value: a SQLite prepare error, or a model restriction
with the path of the node inside the expression. -/
inductive ValueIssue where
  /-- SQLite refuses to prepare the statement. -/
  | prepare (error : PrepareError)
  /-- The model does not describe the expression at this path. -/
  | restriction (path : List Nat) (reason : String)
  deriving Repr, DecidableEq

/-- The value of a numeric literal's text: an integer, a REAL value that the first
scope does not model, or a hexadecimal literal too large for 64 bits. -/
inductive NumericValue where
  /-- A signed 64-bit integer. -/
  | integer (value : Int)
  /-- A REAL value. -/
  | real
  /-- More than 16 hexadecimal digits: {lit}`hex literal too big: %s`. -/
  | hexTooBig
  deriving Repr, DecidableEq

/-- The value of a hexadecimal digit, or {lean}`(none : Option Nat)`. -/
def hexDigit (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

/-- The value of digits in a base, or {lean}`(none : Option Nat)` for an
empty list or a character that is not a digit of that base. -/
def digitsValue (base : Nat) (digits : List Char) : Option Nat :=
  if digits.isEmpty then none else
  digits.foldl (fun result c => do
    let value ← result
    let digit ← hexDigit c
    if digit < base then some (value * base + digit) else none) (some 0)

/-- Whether an integer is in SQLite's signed 64-bit range. -/
def fitsInt64 (value : Int) : Bool := decide (-(2 ^ 63 : Int) ≤ value ∧ value < 2 ^ 63)

/-- A decimal integer times the sign, when it fits in 64 bits; REAL for a larger
integer or for any other numeric text. -/
def decimalNumericValue (chars : List Char) (sign : Int) : NumericValue :=
  match digitsValue 10 chars with
  | some value => if fitsInt64 (sign * value) then .integer (sign * value) else .real
  | none => .real

/-- SQLite's value of a numeric literal token, negated when {lit}`negated` is
true. Underscore separators are removed first. A literal with 1 to 16 hexadecimal
digits after {lit}`0x` is the 64-bit two's-complement integer of those bits; more
digits are {name}`NumericValue.hexTooBig`. A decimal integer is an integer when
it fits in 64 bits after negation, so {lit}`-9223372036854775808` is an integer;
otherwise it is REAL. A literal with a decimal point or an exponent is REAL. -/
def numericValue (text : String) (negated : Bool) : NumericValue :=
  let chars := text.toList.filter (· ≠ '_')
  let sign : Int := if negated then -1 else 1
  match chars with
  | '0' :: x :: hex =>
    if x = 'x' ∨ x = 'X' then
      if hex.length > 16 then .hexTooBig else
      match digitsValue 16 hex with
      | some bits =>
        let signed : Int := if bits ≥ 2 ^ 63 then bits - 2 ^ 64 else bits
        if fitsInt64 (sign * signed) then .integer (sign * signed) else .real
      | none => .real
    else decimalNumericValue chars sign
  | _ => decimalNumericValue chars sign

/-- Convert a numeric literal to a stored value. A REAL value is a model restriction;
a hexadecimal literal over 64 bits is SQLite's prepare error. -/
def numericLiteral (text : String) (negated : Bool) (path : List Nat) : Except ValueIssue Value :=
  match numericValue text negated with
  | .integer value => .ok (.integer value)
  | .real => .error (.restriction path "REAL values are outside the modeled subset")
  | .hexTooBig => .error (.prepare (.hexLiteralTooBig text))

/-- The stored value of a literal expression in a VALUES row or a SET assignment,
where no column is in scope. NULL, string and blob literals keep their bytes.
An identifier written in double quotes is a string literal when the
double-quoted-string setting {lit}`dqs` is on; any other identifier names no
column, which SQLite reports as {lit}`no such column: %s`. Unary plus keeps its
operand; unary minus negates a numeric literal. The time keywords and other
expressions are model restrictions. -/
def literalValue (dqs : Bool) : Syntax.Expr → Except ValueIssue Value
  | .null => .ok .null
  | .string bytes => .ok (.text bytes)
  | .blob bytes => .ok (.blob bytes)
  | .numeric text => numericLiteral text false []
  | .negate (.numeric text) => numericLiteral text true [0]
  | .positive operand => (literalValue dqs operand).mapError fun
      | .restriction path reason => .restriction (0 :: path) reason
      | .prepare error => .prepare error
  | .identifier name doubleQuoted =>
    if doubleQuoted && dqs then .ok (.text name.toUTF8.toList)
    else .error (.prepare (.noSuchColumn name))
  | .currentTime _ => .error (.restriction [] "time values are outside the modeled subset")
  | .negate _ => .error (.restriction [] "only a numeric literal may be negated")
  | .equals .. => .error (.restriction [] "a comparison is not a literal value")

/-- Admit a value only when the column's affinity stores it unchanged
({name}`LiteralData.lossless`); otherwise the conversion is a model restriction. -/
def storedValue (affinity : Affinity) (value : Value) (path : List Nat) : Except ValueIssue Value :=
  if LiteralData.lossless affinity value then .ok value
  else .error (.restriction path "the column affinity would convert this value")

end Belay.Sqlite
