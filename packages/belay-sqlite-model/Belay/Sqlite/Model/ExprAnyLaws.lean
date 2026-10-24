import Belay.Sqlite.Model.Resolution.ExprAny

set_option doc.verso true

/-! Laws of the traversal {name}`Belay.Sqlite.Model.Resolved.Expr.any` (ADR 0017, S4): a test that holds
only where a second test holds finds a part only where the second test does. -/

namespace Belay.Sqlite.Model.Resolved

mutual
/-- For two tests of a node where the first implies the second, an expression with a part that the first
finds has a part that the second finds. Proof sketch: by recursion on the expression; the node itself
by the implication, and each part by the recursion. -/
theorem Expr.any_mono (first second : Expr → Bool) (implies : ∀ node, first node = true → second node = true) :
    ∀ expression : Expr, expression.any first = true → expression.any second = true
  | .column _ | .literal _ | .now _ | .exists _ | .aggregateValue _ | .parameter _ | .counter _ | .subquery _ => by
    simpa [Expr.any] using implies _
  | .compare _ _ left right _ => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (fun hit => hit.imp (implies _) (Expr.any_mono first second implies left))
      (Expr.any_mono first second implies right)
  | .and left right => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (fun hit => hit.imp (implies _) (Expr.any_mono first second implies left))
      (Expr.any_mono first second implies right)
  | .or left right => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (fun hit => hit.imp (implies _) (Expr.any_mono first second implies left))
      (Expr.any_mono first second implies right)
  | .arithmetic _ left right => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (fun hit => hit.imp (implies _) (Expr.any_mono first second implies left))
      (Expr.any_mono first second implies right)
  | .coalesce left right => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (fun hit => hit.imp (implies _) (Expr.any_mono first second implies left))
      (Expr.any_mono first second implies right)
  | .not operand => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Expr.any_mono first second implies operand)
  | .isNull operand _ => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Expr.any_mono first second implies operand)
  | .cast _ operand => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Expr.any_mono first second implies operand)
  | .inQuery operand .. => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Expr.any_mono first second implies operand)
  | .json _ arguments => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Arguments.any_mono first second implies arguments)
  | .date _ arguments => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Arguments.any_mono first second implies arguments)
  | .scalar _ arguments => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (implies _) (Arguments.any_mono first second implies arguments)
  | .inList operand values .. => by
    simp only [Expr.any, Bool.or_eq_true]
    exact fun hit => hit.imp (fun hit => hit.imp (implies _) (Expr.any_mono first second implies operand))
      (Arguments.any_mono first second implies values)

/-- For two tests of a node where the first implies the second, arguments with a part that the first
finds have a part that the second finds. Proof sketch: by recursion on the arguments, as for
{name}`Expr.any_mono`. -/
theorem Arguments.any_mono (first second : Expr → Bool) (implies : ∀ node, first node = true → second node = true) :
    ∀ arguments : Arguments, arguments.any first = true → arguments.any second = true
  | .nil => by simp [Arguments.any]
  | .cons head tail => by
    simp only [Arguments.any, Bool.or_eq_true]
    exact fun hit => hit.imp (Expr.any_mono first second implies head) (Arguments.any_mono first second implies tail)
end

/-- For a test and an expression with no part that the test finds, no part satisfies a stronger test that also
requires another condition. Proof sketch: {name}`Expr.any_mono` with the stronger test as the first. -/
theorem Expr.any_and_eq_false (test other : Expr → Bool) (expression : Expr) (none : expression.any test = false) :
    expression.any (fun node => test node && other node) = false := by
  refine Bool.eq_false_iff.mpr fun found => ?_
  have := Expr.any_mono (fun node => test node && other node) test (fun node hit => (Bool.and_eq_true_iff.mp hit).1)
    expression found
  simp_all

end Belay.Sqlite.Model.Resolved
