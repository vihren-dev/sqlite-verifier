import Belay.Sqlite.Model.Truth
import Belay.Sqlite.Model.ExprEval

set_option doc.verso true

/-! The evaluation laws of the resolved expressions that a query condition uses (ADR 0017, S4):
a column, a literal, a parameter, a comparison with its affinity and collation, {lit}`AND`,
{lit}`OR`, {lit}`NOT` and {lit}`IS NULL`, and the subquery expressions. The value laws
give the value of the expression on a row ({name}`Belay.Sqlite.Model.Resolved.Expr.eval`); the truth
laws give the Boolean that a {lit}`WHERE` takes ({name}`Belay.Sqlite.Model.Resolved.truthy`) in
the Booleans of the parts. -/

namespace Belay.Sqlite.Model.Resolved

/-- The value of a column on a row is the cell at its position, or NULL past the end of the
row. Proof sketch: the definition computes. -/
theorem Expr.eval_column (context : EvalContext) (row : List Value) (position : Nat) :
    (Expr.column position).eval context row = row.getD position .null := rfl

/-- The value of a literal is the literal. Proof sketch: the definition computes. -/
theorem Expr.eval_literal (context : EvalContext) (row : List Value) (value : Value) :
    (Expr.literal value).eval context row = value := rfl

/-- The value of parameter {lit}`number` is the item of the values of the context at that
number, or NULL when there is none ({name}`parameterValue`). Proof sketch: the definition
computes. -/
theorem Expr.eval_parameter (context : EvalContext) (row : List Value) (number : Nat) :
    (Expr.parameter number).eval context row = parameterValue context.parameters number := rfl

/-- The value of a comparison is the comparison of the operands after the affinity converted them
({name}`comparisonOperands`), under the collation of the comparison. Proof sketch: the definition
computes; the faults of the parts do not change the value. -/
theorem Expr.eval_compare (context : EvalContext) (row : List Value) (operator : Comparison)
    (affinity : Option Affinity) (left right : Expr) (collation : Collation) :
    (Expr.compare operator affinity left right collation).eval context row =
      operator.apply (comparisonOperands affinity (left.eval context row) (right.eval context row)).1
        (comparisonOperands affinity (left.eval context row) (right.eval context row)).2 collation := rfl

/-- The value of {lit}`AND` is SQLite's {lit}`AND` of the values of the operands
({name}`Value.and`). Proof sketch: the definition computes. -/
theorem Expr.eval_and (context : EvalContext) (row : List Value) (left right : Expr) :
    (Expr.and left right).eval context row = (left.eval context row).and (right.eval context row) := rfl

/-- The value of {lit}`OR` is SQLite's {lit}`OR` of the values of the operands
({name}`Value.or`). Proof sketch: the definition computes. -/
theorem Expr.eval_or (context : EvalContext) (row : List Value) (left right : Expr) :
    (Expr.or left right).eval context row = (left.eval context row).or (right.eval context row) := rfl

/-- The value of {lit}`NOT` is SQLite's {lit}`NOT` of the value of the operand
({name}`Value.not`). Proof sketch: the definition computes. -/
theorem Expr.eval_not (context : EvalContext) (row : List Value) (operand : Expr) :
    (Expr.not operand).eval context row = (operand.eval context row).not := rfl

/-- The value of {lit}`IS NULL` is 1 when the operand is NULL, else 0, and the reverse for
{lit}`IS NOT NULL`. Proof sketch: the definition computes. -/
theorem Expr.eval_isNull (context : EvalContext) (row : List Value) (operand : Expr) (negated : Bool) :
    (Expr.isNull operand negated).eval context row = truth ((operand.eval context row).isNull != negated) := rfl

/-- SQLite does not read NULL as true. Proof sketch: the definition computes. -/
@[simp] theorem truthy_null : truthy Value.null = false := rfl

/-- A value that is the result of {lit}`AND` is true exactly when both values are true. Proof
sketch: split on whether each value is NULL and whether SQLite reads it as true; the values 1
and 0 that {name}`Value.and` gives are not NULL and are true and false. -/
theorem truthy_and (a b : Value) : truthy (a.and b) = (truthy a && truthy b) := by
  cases na : a.isNull <;> cases nb : b.isNull <;>
    (try have := Value.truthy_of_isNull na) <;> (try have := Value.truthy_of_isNull nb) <;>
    cases ta : truthy a <;> cases tb : truthy b <;>
    simp_all [Value.and, falsy]

/-- A value that is the result of {lit}`OR` is true exactly when one of the values is true.
Proof sketch: the definition of {name}`Value.or` tests the truth of the two values first. -/
theorem truthy_or (a b : Value) : truthy (a.or b) = (truthy a || truthy b) := by
  unfold Value.or
  cases ta : truthy a <;> cases tb : truthy b <;> cases na : a.isNull <;> cases nb : b.isNull <;> simp_all

/-- A value that is the result of {lit}`NOT` is true exactly when the value is false, which is
not NULL and not true ({name}`Resolved.falsy`). Proof sketch: split on whether the value is
NULL; a NULL value is not true. -/
theorem truthy_not (value : Value) : truthy value.not = falsy value := by
  cases null : value.isNull <;> simp [Value.not, falsy, null]

/-- The comparison {lit}`left op right` for an operator other than {lit}`IS` and {lit}`IS NOT` is
true exactly when neither operand is NULL and the ordering of the operands under the collation
satisfies the operator. Proof sketch: unfold {name}`Comparison.apply`; the operator is one of
the six ordinary ones, whose value is NULL for a NULL operand and 1 or 0 otherwise. -/
theorem truthy_apply_ordinary (operator : Comparison) (notIs : operator ≠ .is) (notIsNot : operator ≠ .isNot)
    (left right : Value) (collation : Collation) :
    truthy (operator.apply left right collation) =
      (!left.isNull && !right.isNull && operator.holds (collation.compare left right)) := by
  cases hl : left.isNull <;> cases hr : right.isNull <;> cases operator <;> simp_all [Comparison.apply]

/-- The value of {lit}`EXISTS (q)` on a row is 1 when the subquery gives a row for the row, else 0.
Proof sketch: the definition computes. -/
theorem Expr.eval_exists (context : EvalContext) (row : List Value) (index : Nat) :
    (Expr.exists index).eval context row = truth !(context.subqueries index row).rows.isEmpty := rfl

/-- The fault of {lit}`EXISTS (q)` on a row is the fault of the subquery for the row. Proof
sketch: the definition computes. -/
theorem Expr.fault_exists (context : EvalContext) (row : List Value) (index : Nat) :
    ((Expr.exists index).evaluate context row).2 = (context.subqueries index row).fault := rfl

/-- The value of a scalar subquery on a row is the first value of its first row for the row, or NULL when
it has none. Proof sketch: the definition computes. -/
theorem Expr.eval_subquery (context : EvalContext) (row : List Value) (index : Nat) :
    (Expr.subquery index).eval context row =
      ((context.subqueries index row).rows.head?.bind List.head?).getD .null := rfl

/-- The fault of a scalar subquery on a row is the fault of the subquery for the row when the first
value of its first row is certain, else {lean}`Fault.may`. Proof sketch: the definition computes. -/
theorem Expr.fault_subquery (context : EvalContext) (row : List Value) (index : Nat) :
    ((Expr.subquery index).evaluate context row).2 =
      if (context.subqueries index row).firstCertain then (context.subqueries index row).fault else .may := rfl

/-- The value of {lit}`x [NOT] IN (q)` on a row is the value of the membership test
({name}`inValue`) of the operand among the first values of the rows of the subquery for the row. Proof sketch: the
definition computes. -/
theorem Expr.eval_inQuery (context : EvalContext) (row : List Value) (operand : Expr) (index : Nat)
    (affinity : Option Affinity) (collation : Collation) (negated : Bool) :
    (Expr.inQuery operand index affinity collation negated).eval context row =
      inValue affinity collation negated (operand.eval context row)
        ((context.subqueries index row).rows.filterMap List.head?) := rfl

/-- The fault of {lit}`x [NOT] IN (q)` on a row is the fault of the operand, joined with the fault of
the subquery for the row when the rows of the subquery are certain, and joined with {lean}`Fault.may` when
they are not. A must-fault of the operand stays a must-fault. Proof sketch: the definition computes. -/
theorem Expr.fault_inQuery (context : EvalContext) (row : List Value) (operand : Expr) (index : Nat)
    (affinity : Option Affinity) (collation : Collation) (negated : Bool) :
    ((Expr.inQuery operand index affinity collation negated).evaluate context row).2 =
      (operand.evaluate context row).2.join
        (if (context.subqueries index row).rowsCertain then (context.subqueries index row).fault else .may) := rfl

/-- The fault of {lit}`NOT x` on a row is the fault of the operand. Proof sketch: the definition
computes. -/
theorem Expr.fault_not (context : EvalContext) (row : List Value) (operand : Expr) :
    ((Expr.not operand).evaluate context row).2 = (operand.evaluate context row).2 := rfl

end Belay.Sqlite.Model.Resolved
