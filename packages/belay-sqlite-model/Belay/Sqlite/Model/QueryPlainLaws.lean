import Belay.Sqlite.Model.QueryRun

set_option doc.verso true

/-! Laws of a query without a fallible call: no expression of it has a fault, and no call of
it may fail, in a context whose subqueries have no fault. {lit}`SqlLaws` uses them for a
statement that writes nothing. -/

namespace Belay.Sqlite.Model.Resolved

/-- For every context whose subqueries have no fault ({name}`EvalContext.Quiet`), row and
expression without a fallible call at any depth ({name}`Expr.isFallibleCall`, {name}`Expr.any`),
the fault of the expression over the row in the context is {lean}`Fault.none`. Proof sketch:
induction over the mutual expression and argument types; every node joins or softens the
faults of its parts, which are all {lean}`Fault.none`, a subquery form has the fault of its
subquery, which is {lean}`Fault.none` in a quiet context, and a scalar function that cannot
fail gives a value ({name}`ScalarFunction.apply_ok`). -/
theorem Expr.fault_of_plain (context : EvalContext) (quiet : context.Quiet) (row : List Value) (expression : Expr)
    (plain : expression.any Expr.isFallibleCall = false) : (expression.evaluate context row).2 = .none := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.any Expr.isFallibleCall = false → (arguments.evaluate context row).2 = .none) <;>
    simp_all [Expr.any, Arguments.any, Expr.isFallibleCall, Expr.evaluate, Arguments.evaluate, Fault.join, Fault.soften,
      EvalContext.Quiet]
  case scalar function arguments ih =>
    have safe := plain.1
    have quiet := ih
    cases function
    case iif =>
      cases arguments with
      | nil => simp [Expr.evaluate]
      | cons head tail =>
        simp only [Arguments.evaluate] at quiet
        simp only [Expr.evaluate]
        rcases first : (head.evaluate context row).2 with _ | _ | _ <;>
          rcases later : (tail.evaluate context row).2 with _ | _ | _ <;>
          simp_all [Fault.join, Fault.soften]
    all_goals
      obtain ⟨value, ok⟩ := ScalarFunction.apply_ok _ (arguments.evaluate context row).1 safe
      simp [Expr.evaluate, ok, quiet, Fault.join, Fault.ofFunction]

/-- For every context whose subqueries have no fault ({name}`EvalContext.Quiet`), all rows
and every query without a fallible call in any of its expressions ({name}`Query.expressions`),
no call of the query may fail over the rows in the context ({name}`Query.mayFail`). Proof sketch: each expression that {name}`Query.mayFail`
evaluates is one of {name}`Query.expressions`, so {name}`Expr.fault_of_plain` applies to
it. -/
theorem Query.mayFail_of_plain (context : EvalContext) (quiet : context.Quiet) (query : Query) (rows : List (List Value))
    (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true) : query.mayFail context rows = false := by
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  unfold Query.mayFail anyMayFail
  simp only [Bool.or_eq_false_iff, Bool.and_eq_false_iff, List.any_eq_false, Bool.not_eq_true]
  refine ⟨.inr fun expression member => plain expression member, fun _ _ expression member => ?_,
    fun _ _ expression member => ?_⟩ <;>
    simp [Expr.mayFailOn, Expr.fault_of_plain context quiet _ _ (plain expression (by simp_all [Query.expressions]))]

end Belay.Sqlite.Model.Resolved
