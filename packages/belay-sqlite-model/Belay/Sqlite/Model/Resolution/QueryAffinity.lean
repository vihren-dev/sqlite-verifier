import Belay.Sqlite.Model.Resolution.QueryForm

set_option doc.verso true

/-! The affinity rules of a comparison in a query (ADR 0013, D4). A column reference has
its column's affinity, a {lit}`CAST` has the affinity of its type, and every other
expression has none ({lit}`sqlite3ExprAffinity`). Resolution computes the affinity of each
comparison from those of its operands, and evaluation applies it. -/

namespace Belay.Sqlite.Model

/-- A resolved operand and its affinity, which resolution keeps while it resolves an
expression: a column reference has its column's affinity, a {lit}`CAST` the affinity of its
type, every other expression, {lit}`+x` included, has none. The resolved expression keeps
only the affinity of each comparison. -/
abbrev Operand := Resolved.Expr × Option Affinity

/-- Whether an affinity is INTEGER, REAL or NUMERIC. -/
def numericAffinity : Affinity → Bool
  | .integer | .real | .numeric => true
  | .text | .blob => false

/-- The literal value of a resolved expression, if it is a literal. -/
def Resolved.Expr.literal? : Resolved.Expr → Option Value
  | .literal value => some value
  | .column _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. | .cast .. | .coalesce ..
  | .json .. | .now _ | .date .. | .scalar .. | .exists .. | .inQuery .. | .subquery _ | .inList .. | .aggregateValue _ | .parameter _ | .counter _ => none

/-- The affinity of a comparison of two operands with the given affinities, as SQLite's
{lit}`sqlite3CompareAffinity` gives it: when both have one, NUMERIC if either is INTEGER,
REAL or NUMERIC, else BLOB (R-58138-64688); else the affinity of the operand that has one
(R-29161-32953); else none. {assert}`comparisonAffinity (some .text) none = some .text`. -/
def comparisonAffinity : Option Affinity → Option Affinity → Option Affinity
  | some left, some right => if numericAffinity left || numericAffinity right then some .numeric else some .blob
  | some left, none => some left
  | none, some right => some right
  | none, none => none

end Belay.Sqlite.Model
