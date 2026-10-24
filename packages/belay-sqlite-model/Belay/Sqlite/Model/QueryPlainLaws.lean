import Belay.Sqlite.Model.QueryRun
import Belay.Sqlite.Model.QueryLaws

set_option doc.verso true

/-! Laws of a query without a fallible call: no expression of it has a fault, and no call of
it may fail, in a context whose subqueries have no fault. {lit}`SqlLaws` uses them for a
statement that writes nothing. -/

namespace Belay.Sqlite.Model.Resolved

/-- Whether no subquery of the context has a fault or uncertain rows for one outer row: for every index, the
fault of the subquery's run for the row is {lean}`Fault.none`, and its first row and its rows are certain. An
expression over the row reads the subqueries for that row only, so this is what its evaluation needs of them. -/
def EvalContext.QuietAt (context : EvalContext) (row : List Value) : Prop :=
  ∀ index, (context.subqueries index row).fault = .none ∧ (context.subqueries index row).firstCertain = true ∧
    (context.subqueries index row).rowsCertain = true

/-- For every quiet context ({name}`EvalContext.Quiet`) and row, the context is quiet at the row
({name}`EvalContext.QuietAt`). Proof sketch: the hypothesis for the row. -/
theorem EvalContext.Quiet.at {context : EvalContext} (quiet : context.Quiet) (row : List Value) : context.QuietAt row :=
  fun index => quiet index row

/-- For every context, row and expression without a fallible call at any depth ({name}`Expr.isFallibleCall`,
{name}`Expr.any`), where the subqueries of the context are quiet for the row ({name}`EvalContext.QuietAt`), the fault
of the expression over the row in the context is {lean}`Fault.none`. Proof sketch:
induction over the mutual expression and argument types; every node joins or softens the
faults of its parts, which are all {lean}`Fault.none`, a subquery form has the fault of its
subquery for the row, which is {lean}`Fault.none` when the context is quiet at the row, and a scalar function that cannot
fail gives a value ({name}`ScalarFunction.apply_ok`). -/
theorem Expr.fault_of_plain_at (context : EvalContext) (row : List Value) (quiet : context.QuietAt row)
    (expression : Expr) (plain : expression.any Expr.isFallibleCall = false) :
    (expression.evaluate context row).2 = .none := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.any Expr.isFallibleCall = false → (arguments.evaluate context row).2 = .none) <;>
    simp_all [Expr.any, Arguments.any, Expr.isFallibleCall, Expr.evaluate, Arguments.evaluate, Fault.join, Fault.soften,
      EvalContext.QuietAt]
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

/-- For every context whose subqueries have no fault ({name}`EvalContext.Quiet`), row and
expression without a fallible call at any depth ({name}`Expr.isFallibleCall`, {name}`Expr.any`),
the fault of the expression over the row in the context is {lean}`Fault.none`. Proof sketch:
{name}`Expr.fault_of_plain_at`, for a context that is quiet at every row. -/
theorem Expr.fault_of_plain (context : EvalContext) (quiet : context.Quiet) (row : List Value) (expression : Expr)
    (plain : expression.any Expr.isFallibleCall = false) : (expression.evaluate context row).2 = .none :=
  Expr.fault_of_plain_at context row (quiet.at row) expression plain

/-- For every context, rows and query without a fallible call in any of its expressions
({name}`Query.expressions`), whose expressions have no fault over the empty row and over each of the rows,
no call of the query may fail over the rows in the context ({name}`Query.mayFail`). Proof sketch: each
expression that {name}`Query.mayFail` evaluates is one of {name}`Query.expressions`, over a row
that is the empty row or one of the rows ({name}`mem_filtered`), so the hypothesis gives it no fault. -/
theorem Query.mayFail_of_faultless (context : EvalContext) (query : Query) (rows : List (List Value))
    (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true)
    (faultless : ∀ row ∈ [] :: rows, ∀ expression ∈ query.expressions, (expression.evaluate context row).2 = .none) :
    query.mayFail context rows = false := by
  have inRows : ∀ row ∈ filtered context query rows ++ (if query.aggregate then [[]] else []), row ∈ [] :: rows := by
    intro row member
    rcases List.mem_append.mp member with kept | extra
    · exact List.mem_cons_of_mem _ ((mem_filtered context query rows row).mp kept).1
    · split at extra
      · simp_all
      · simp_all
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  unfold Query.mayFail anyMayFail
  simp only [Bool.or_eq_false_iff, Bool.and_eq_false_iff, List.any_eq_false, Bool.not_eq_true]
  refine ⟨.inr fun expression member => plain expression member, fun row member expression inside => ?_,
    fun row member expression inside => ?_⟩
  · simp [Expr.mayFailOn, faultless row member expression (by simp_all [Query.expressions])]
  · simp [Expr.mayFailOn, faultless row (inRows row member) expression (by simp_all [Query.expressions])]

/-- For every context, rows and query whose expressions have no fault over the empty row and over each of the rows,
{name}`Query.mustFail` is false for the query: it detects no failure. It does not say that the query cannot overflow
an aggregate or fail in a window. Proof sketch: each expression that
{name}`Query.mustFail` tests is one of {name}`Query.expressions`, over a row of the rows, and an expression without
fault does not fail ({name}`Expr.mustFailOn`). -/
theorem Query.mustFail_of_faultless (context : EvalContext) (query : Query) (rows : List (List Value))
    (faultless : ∀ row ∈ [] :: rows, ∀ expression ∈ query.expressions, (expression.evaluate context row).2 = .none) :
    query.mustFail context rows = false := by
  unfold Query.mustFail
  simp only [Bool.and_eq_false_iff, List.any_eq_false, Bool.not_eq_true, Bool.or_eq_false_iff]
  refine .inr fun row member => ?_
  have quietly : ∀ expression ∈ query.expressions, expression.mustFailOn context row = false := fun expression member' => by
    simp [Expr.mustFailOn, faultless row (List.mem_cons_of_mem _ member) expression member']
  refine ⟨?_, .inr ⟨fun expression member => quietly expression ?_, .inr fun expression member => quietly expression ?_⟩⟩
  · cases found : query.filter with
    | none => rfl
    | some condition => simpa using quietly condition (by simp [Query.expressions, found])
  · simp only [List.mem_flatMap] at member
    simp [Query.expressions, Query.keptExpressions, List.mem_flatMap, member]
  · simp only [List.mem_flatMap] at member
    simp [Query.expressions, Query.keptExpressions, List.mem_flatMap, member]

/-- For every context whose subqueries have no fault ({name}`EvalContext.Quiet`), all rows
and every query without a fallible call in any of its expressions ({name}`Query.expressions`),
no call of the query may fail over the rows in the context ({name}`Query.mayFail`). Proof sketch:
{name}`Query.mayFail_of_faultless`, with {name}`Expr.fault_of_plain` for the fault of each
expression. -/
theorem Query.mayFail_of_plain (context : EvalContext) (quiet : context.Quiet) (query : Query) (rows : List (List Value))
    (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true) : query.mayFail context rows = false := by
  refine Query.mayFail_of_faultless context query rows plain fun row _ expression member => ?_
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  exact Expr.fault_of_plain context quiet row expression (plain expression member)

end Belay.Sqlite.Model.Resolved
