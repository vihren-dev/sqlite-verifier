import Belay.Sqlite.Resolution.QueryForm
import Belay.Sqlite.Resolution.Restrictions

set_option doc.verso true

/-! The affinity rules of a comparison in a query (ADR 0012, slices 1 and 2). A column
reference has its column's affinity, a {lit}`CAST` has the affinity of its type, and
every other expression has none ({lit}`sqlite3ExprAffinity`). A comparison whose
affinity rule would convert a value is a model restriction, so that evaluation
compares the values as they are. -/

namespace Belay.Sqlite

/-- A resolved operand and its affinity in a comparison: a column reference has
its column's affinity, a {lit}`CAST` the affinity of its type, every other expression
has none. -/
abbrev Operand := Resolved.Expr × Option Affinity

/-- Whether an affinity is INTEGER, REAL or NUMERIC. -/
def numericAffinity : Affinity → Bool
  | .integer | .real | .numeric => true
  | .text | .blob => false

/-- The literal value of a resolved expression, if it is a literal. -/
def Resolved.Expr.literal? : Resolved.Expr → Option Value
  | .literal value => some value
  | .column _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. | .cast .. | .coalesce ..
  | .json .. | .arguments _ | .now _ => none

/-- Whether a value is TEXT. -/
def Value.isText : Value → Bool
  | .text _ => true
  | .null | .integer _ | .real _ | .blob _ => false

/-- Whether TEXT affinity keeps a value unchanged: NULL, TEXT or BLOB. -/
def Value.keepsText : Value → Bool
  | .null | .text _ | .blob _ => true
  | .integer _ | .real _ => false

/-- Whether an expression without affinity may give a TEXT value: a TEXT literal, a
column, a JSON function, a time keyword, or a {lit}`COALESCE` with such an operand. Comparisons, logical operators,
arithmetic and {lit}`CAST` to INTEGER, REAL or NUMERIC give numbers or NULL. A
{lit}`CAST` to TEXT or BLOB has an affinity, so this question does not arise for it;
it counts as possibly TEXT. -/
def Resolved.Expr.mayBeText : Resolved.Expr → Bool
  | .literal value => value.isText
  | .column _ => true
  | .coalesce first rest => first.mayBeText || rest.mayBeText
  | .cast affinity _ => !numericAffinity affinity
  | .json .. | .now _ => true
  | .arguments _ => false
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. => false

/-- Why the affinity rule of a comparison would convert one operand, given the
affinity of the other: when the other operand has INTEGER, REAL or NUMERIC
affinity, an operand without affinity that may be TEXT ({name}`Resolved.Expr.mayBeText`)
or a column of another affinity would get NUMERIC affinity (R-58138-64688); when the other operand is a TEXT column and this one has
no affinity, a value other than a NULL, text or blob literal would get TEXT
affinity (R-29161-32953). -/
def conversion (target : Operand) (other : Option Affinity) : Option RestrictionKind :=
  if other.any numericAffinity then
    match target.2 with
    | some affinity =>
      if numericAffinity affinity then none
      else some .mixedAffinityComparison
    | none =>
      if target.1.mayBeText then
        some .textToNumber
      else none
  else if other == some .text && target.2.isNone && !((target.1.literal?.map Value.keepsText).getD false) then
    some .numberToText
  else none

/-- Why the affinity rule of a comparison would convert an operand, with the path of
that operand (R-10393-27560), checking the left operand first. -/
def affinityIssue (left right : Operand) : Option (List Nat × RestrictionKind) :=
  match conversion left right.2 with
  | some reason => some ([0], reason)
  | none => (conversion right left.2).map ([1], ·)

end Belay.Sqlite
