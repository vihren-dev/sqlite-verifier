import Belay.Sqlite.Model.SelectOneSubqueryOutput

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE c` with subqueries when {lit}`c` names no scalar subquery (ADR 0017, S4):
{lit}`EXISTS` and {lit}`IN` read the rows of a subquery, its fault and whether the rows are certain, but not
whether its first row is certain. A subquery of several rows without {lit}`ORDER BY` has an uncertain first row, and
{lit}`x IN (SELECT c FROM t)` is still decided. The lemmas here are those of
{lit}`resolvedStepOutput_selectOne_hasRows` for such a condition, with the results of the subqueries given up to the
mark of the first row ({name}`Belay.Sqlite.Model.Resolved.SubqueryRun.certainFirst`). -/

namespace Belay.Sqlite.Model

/-- For every connection, values, condition without scalar subquery, subqueries and results of the subqueries, where
the statement {lit}`SELECT 1 WHERE c` with these subqueries is calm, subquery {lit}`i` of the context of the statement for
the empty outer row has the result {lit}`runs[i]` once its first row is marked certain (and no row and no fault past the
list), and each result is quiet, the value of the condition in the context of the statement is its value in the context of
the values with these results ({name}`Resolved.EvalContext.withRuns`), and it has no fault. Proof sketch: as for
{name}`Connection.queryContext_selectOne`, in the context of the statement with the first row of every subquery marked
certain, which gives the condition the same value and fault ({name}`Resolved.Expr.evaluate_certainFirst`). -/
theorem Connection.queryContext_selectOne_rows (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (noScalar : condition.any (· matches .subquery _) = false)
    (agree : ∀ index, ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      index []).certainFirst = (runs[index]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (condition.evaluate (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries) []).2 = .none ∧
    condition.eval (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries) [] =
      condition.eval ((Resolved.EvalContext.bound parameters).withRuns runs) [] := by
  have plain : condition.any Resolved.Expr.isFallibleCall = false :=
    (calm condition (by simp [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions])).1
  have same := Resolved.Expr.evaluate_certainFirst
    (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries) [] condition noScalar plain
  have quietAt : ({ connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries with
      subqueries := fun index outer => ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition)
        subqueries).subqueries index outer).certainFirst } : Resolved.EvalContext).QuietAt [] := fun index => by
    have known : ((runs[index]?).getD { rows := [], fault := .none } : Resolved.SubqueryRun).Quiet := by
      cases found : runs[index]? with
      | none => exact ⟨rfl, rfl, rfl⟩
      | some run => exact quiet run (List.mem_of_getElem? found)
    rw [← agree index] at known
    exact known
  refine ⟨?_, ?_⟩
  · rw [← same]
    exact Resolved.Expr.fault_of_plain_at _ [] quietAt condition plain
  · have value := Resolved.Expr.evaluate_withSubqueries
      { connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries with
        subqueries := fun index outer => ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition)
          subqueries).subqueries index outer).certainFirst } []
      (fun index _ => (runs[index]?).getD { rows := [], fault := .none }) agree condition plain
    have shape : ({ connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries with
        subqueries := fun index _ => (runs[index]?).getD { rows := [], fault := .none } } : Resolved.EvalContext) =
        (Resolved.EvalContext.bound parameters).withRuns runs := by
      rw [connection.queryContext_eq_bound parameters _ subqueries calm]
      rfl
    have shape' : ({ ({ connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries with
        subqueries := fun index outer => ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition)
          subqueries).subqueries index outer).certainFirst } : Resolved.EvalContext) with
        subqueries := fun index _ => (runs[index]?).getD { rows := [], fault := .none } } : Resolved.EvalContext) =
        (Resolved.EvalContext.bound parameters).withRuns runs := by
      rw [← shape]
    rw [shape'] at value
    unfold Resolved.Expr.eval
    rw [← same]
    exact congrArg Prod.fst value.symm

/-- For every connection, values, condition, subqueries and results as in
{name}`Connection.queryContext_selectOne_rows`, the output of the step of {lit}`SELECT 1 WHERE c` with the subqueries has
rows exactly when the condition is true in the context of the values with the results of the subqueries. Proof sketch:
{name}`resolvedStepOutput_noFrom_hasRows` with the fault and the value from
{name}`Connection.queryContext_selectOne_rows`. -/
theorem resolvedStepOutput_selectOne_rows_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (noScalar : condition.any (· matches .subquery _) = false)
    (agree : ∀ i, ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      i []).certainFirst = (runs[i]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.selectOneWhere condition) subqueries)).hasRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns runs) []) = true := by
  obtain ⟨fault, value⟩ := connection.queryContext_selectOne_rows parameters condition subqueries runs calm noScalar agree quiet
  rw [resolvedStepOutput_noFrom_hasRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ fault)]
  simp [value]

/-- For every connection, values, condition, subqueries and results as in
{name}`Connection.queryContext_selectOne_rows`, the output of the step has no rows exactly when the condition is not true in
the context of the values with the results of the subqueries. Proof sketch: as for
{name}`resolvedStepOutput_selectOne_rows_hasRows`, with {name}`resolvedStepOutput_noFrom_hasNoRows`. -/
theorem resolvedStepOutput_selectOne_rows_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (noScalar : condition.any (· matches .subquery _) = false)
    (agree : ∀ i, ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      i []).certainFirst = (runs[i]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.selectOneWhere condition) subqueries)).hasNoRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns runs) []) = false := by
  obtain ⟨fault, value⟩ := connection.queryContext_selectOne_rows parameters condition subqueries runs calm noScalar agree quiet
  rw [resolvedStepOutput_noFrom_hasNoRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ fault)]
  simp [value]

/-- For every connection, values, condition, subqueries and results as in
{name}`Connection.queryContext_selectOne_rows`, the output of the step is no error. Proof sketch: as for
{name}`resolvedStepOutput_selectOne_rows_hasRows`, with {name}`resolvedStepOutput_noFrom_not_isError`. -/
theorem resolvedStepOutput_selectOne_rows_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (noScalar : condition.any (· matches .subquery _) = false)
    (agree : ∀ i, ((connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      i []).certainFirst = (runs[i]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.selectOneWhere condition) subqueries)).isError = false :=
  resolvedStepOutput_noFrom_not_isError index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _
      (connection.queryContext_selectOne_rows parameters condition subqueries runs calm noScalar agree quiet).1)

end Belay.Sqlite.Model
