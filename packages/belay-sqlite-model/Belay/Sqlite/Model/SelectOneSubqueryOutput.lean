import Belay.Sqlite.Model.NoFromQuerySteps
import Belay.Sqlite.Model.ExprContextLaws
import Belay.Sqlite.Model.ExistsSubqueryOutput

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE c` with subqueries, for any condition {lit}`c` (ADR 0017, S4): when
the results of the subqueries for the empty outer row are known and quiet, the statement has rows
exactly when {lit}`c` is true in the context that holds these results. The condition may name each subquery
by {lit}`EXISTS`, {lit}`IN` or as a scalar; one lemma serves every form of subquery. -/

namespace Belay.Sqlite.Model

/-- The results of the subqueries, as a list of runs: each run has no fault and certain rows. For example,
the run of a subquery that gives one row and cannot fail is quiet. -/
def Resolved.SubqueryRun.Quiet (run : Resolved.SubqueryRun) : Prop :=
  run.fault = .none ∧ run.firstCertain = true ∧ run.rowsCertain = true

/-- For every connection, values, query and subqueries of a calm statement, the context of the statement on the
connection is the context of the values, with the subqueries of the statement as its subqueries
({name}`Resolved.EvalContext.bound`): the statement reads no counter, so the context knows none. Proof sketch:
the statement reads no counters ({name}`Resolved.Statement.Calm.counterReads`); the other fields of the context
of a statement are those of the context of the values, whatever the number of its subqueries. -/
theorem Connection.queryContext_eq_bound (connection : Connection) (parameters : List Value) (query : Resolved.Query)
    (subqueries : List Resolved.Query) (calm : (Resolved.Statement.query query subqueries).Calm) :
    connection.queryContext parameters query subqueries =
      { Resolved.EvalContext.bound parameters with
        subqueries := (connection.queryContext parameters query subqueries).subqueries } := by
  simp only [Connection.queryContext, calm.counterReads, Resolved.statementContext]
  cases subqueries.length <;> rfl

/-- For every connection, values, condition, subqueries and results of the subqueries, where the statement
{lit}`SELECT 1 WHERE c` with these subqueries is calm, subquery {lit}`i` of the context of the statement for the
empty outer row has the result {lit}`runs[i]` (and no row and no fault past the list), and each result is quiet,
the value of the condition in the context of the statement is its value in the context of the values with these
results ({name}`Resolved.EvalContext.withRuns`), and it has no fault. Proof sketch:
the context of the statement is the context of the values with its subqueries
({name}`Connection.queryContext_eq_bound`); {name}`Resolved.Expr.evaluate_withSubqueries` replaces them by the
results, which agree for the empty row, and {name}`Resolved.Expr.fault_of_plain_at` gives the fault of the condition,
which has no fallible call because the statement is calm. -/
theorem Connection.queryContext_selectOne (connection : Connection) (parameters : List Value) (condition : Resolved.Expr)
    (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (agree : ∀ index, (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      index [] = (runs[index]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (condition.evaluate (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries) []).2 = .none ∧
    condition.eval (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries) [] =
      condition.eval ((Resolved.EvalContext.bound parameters).withRuns runs) [] := by
  have plain : condition.any Resolved.Expr.isFallibleCall = false :=
    (calm condition (by simp [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions])).1
  refine ⟨Resolved.Expr.fault_of_plain_at _ [] (fun index => ?_) condition plain, ?_⟩
  · rw [agree index]
    cases found : runs[index]? with
    | none => exact ⟨rfl, rfl, rfl⟩
    | some run => exact quiet run (List.mem_of_getElem? found)
  · have same := Resolved.Expr.evaluate_withSubqueries
      (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries) []
      (fun index _ => (runs[index]?).getD { rows := [], fault := .none }) agree condition plain
    have shape : ({ connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries with
        subqueries := fun index _ => (runs[index]?).getD { rows := [], fault := .none } } : Resolved.EvalContext) =
        (Resolved.EvalContext.bound parameters).withRuns runs := by
      rw [connection.queryContext_eq_bound parameters _ subqueries calm]
      rfl
    rw [shape] at same
    exact congrArg Prod.fst same.symm

/-- For every connection, values, condition, subqueries and results as in {name}`Connection.queryContext_selectOne`,
the output of the step of {lit}`SELECT 1 WHERE c` with the subqueries has rows exactly when the condition is true in
the context of the values with the results of the subqueries. Proof sketch:
{name}`resolvedStepOutput_noFrom_hasRows` with the fault and the value from {name}`Connection.queryContext_selectOne`. -/
theorem resolvedStepOutput_selectOne_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (agree : ∀ i, (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      i [] = (runs[i]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.selectOneWhere condition) subqueries)).hasRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns runs) []) = true := by
  obtain ⟨fault, value⟩ := connection.queryContext_selectOne parameters condition subqueries runs calm agree quiet
  rw [resolvedStepOutput_noFrom_hasRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ fault)]
  simp [value]

/-- For every connection, values, condition, subqueries and results as in {name}`Connection.queryContext_selectOne`,
the output of the step of {lit}`SELECT 1 WHERE c` with the subqueries has no rows exactly when the condition is not
true in the context of the values with the results of the subqueries. Proof sketch: as for
{name}`resolvedStepOutput_selectOne_hasRows`, with {name}`resolvedStepOutput_noFrom_hasNoRows`. -/
theorem resolvedStepOutput_selectOne_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (agree : ∀ i, (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      i [] = (runs[i]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.selectOneWhere condition) subqueries)).hasNoRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns runs) []) = false := by
  obtain ⟨fault, value⟩ := connection.queryContext_selectOne parameters condition subqueries runs calm agree quiet
  rw [resolvedStepOutput_noFrom_hasNoRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ fault)]
  simp [value]

/-- For every connection, values, condition, subqueries and results as in {name}`Connection.queryContext_selectOne`,
the output of the step of {lit}`SELECT 1 WHERE c` with the subqueries is no error. Proof sketch: as for
{name}`resolvedStepOutput_selectOne_hasRows`, with {name}`resolvedStepOutput_noFrom_not_isError`. -/
theorem resolvedStepOutput_selectOne_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (subqueries : List Resolved.Query) (runs : List Resolved.SubqueryRun)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition) subqueries).Calm)
    (agree : ∀ i, (connection.queryContext parameters (Resolved.Query.selectOneWhere condition) subqueries).subqueries
      i [] = (runs[i]?).getD { rows := [], fault := .none })
    (quiet : ∀ run ∈ runs, run.Quiet) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.selectOneWhere condition) subqueries)).isError = false :=
  resolvedStepOutput_noFrom_not_isError index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _
      (connection.queryContext_selectOne parameters condition subqueries runs calm agree quiet).1)

end Belay.Sqlite.Model
