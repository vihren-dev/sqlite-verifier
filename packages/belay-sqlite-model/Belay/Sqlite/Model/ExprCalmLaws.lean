import Belay.Sqlite.Model.StatementCalm

set_option doc.verso true

/-! The calm expressions that a query condition uses (ADR 0017, S4): a column, a literal and a
parameter are calm, and so is a comparison, {lit}`AND`, {lit}`OR`, {lit}`NOT` or {lit}`IS NULL` of
calm expressions, and so is a subquery expression. A calm expression has no fallible call, no clock read
and no counter read. -/

namespace Belay.Sqlite.Model.Resolved

/-- A column is calm. Proof sketch: the column is no fallible call, no clock read and no counter
call. -/
theorem Expr.calm_column (position : Nat) : (Expr.column position).Calm := by
  simp [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere]

/-- A literal is calm. Proof sketch: as {name}`Expr.calm_column`. -/
theorem Expr.calm_literal (value : Value) : (Expr.literal value).Calm := by
  simp [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere]

/-- A parameter is calm. Proof sketch: as {name}`Expr.calm_column`. -/
theorem Expr.calm_parameter (number : Nat) : (Expr.parameter number).Calm := by
  simp [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere]

/-- A comparison is calm exactly when both operands are calm. Proof sketch: the comparison is no
fallible call, no clock read and no counter call itself, so the tests on it reduce to the tests
on its operands. -/
theorem Expr.calm_compare (operator : Comparison) (affinity : Option Affinity) (left right : Expr)
    (collation : Collation) :
    (Expr.compare operator affinity left right collation).Calm ↔ left.Calm ∧ right.Calm := by
  simp only [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere,
    Bool.false_or, Bool.or_eq_false_iff]
  grind

/-- {lit}`AND` is calm exactly when both operands are calm. Proof sketch: as
{name}`Expr.calm_compare`. -/
theorem Expr.calm_and (left right : Expr) : (Expr.and left right).Calm ↔ left.Calm ∧ right.Calm := by
  simp only [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere,
    Bool.false_or, Bool.or_eq_false_iff]
  grind

/-- {lit}`OR` is calm exactly when both operands are calm. Proof sketch: as
{name}`Expr.calm_compare`. -/
theorem Expr.calm_or (left right : Expr) : (Expr.or left right).Calm ↔ left.Calm ∧ right.Calm := by
  simp only [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere,
    Bool.false_or, Bool.or_eq_false_iff]
  grind

/-- {lit}`NOT` is calm exactly when its operand is calm. Proof sketch: as
{name}`Expr.calm_compare`. -/
theorem Expr.calm_not (operand : Expr) : (Expr.not operand).Calm ↔ operand.Calm := by
  simp only [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere,
    Bool.false_or]

/-- {lit}`IS NULL` is calm exactly when its operand is calm. Proof sketch: as
{name}`Expr.calm_compare`. -/
theorem Expr.calm_isNull (operand : Expr) (negated : Bool) : (Expr.isNull operand negated).Calm ↔ operand.Calm := by
  simp only [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere,
    Bool.false_or]

/-- {lit}`EXISTS (q)` is calm. Proof sketch: it is no fallible call, no clock read and no counter call; the
subquery is a statement of its own, whose expressions the calm statement checks. -/
theorem Expr.calm_exists (index : Nat) : (Expr.exists index).Calm := by
  simp [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere]

/-- A scalar subquery is calm. Proof sketch: as {name}`Expr.calm_exists`. -/
theorem Expr.calm_subquery (index : Nat) : (Expr.subquery index).Calm := by
  simp [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere]

/-- {lit}`x [NOT] IN (q)` is calm exactly when its operand is calm. Proof sketch: as
{name}`Expr.calm_not`. -/
theorem Expr.calm_inQuery (operand : Expr) (index : Nat) (affinity : Option Affinity) (collation : Collation)
    (negated : Bool) : (Expr.inQuery operand index affinity collation negated).Calm ↔ operand.Calm := by
  simp only [Expr.Calm, Expr.any, Expr.isFallibleCall, Expr.readsClockHere, Expr.readsCounterHere,
    Bool.false_or]

end Belay.Sqlite.Model.Resolved
