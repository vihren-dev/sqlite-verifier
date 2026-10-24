import Belay.Sqlite.Model.ExistsSubqueryOutput

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE NOT EXISTS (SELECT … FROM t WHERE p)` (ADR 0017, S4): the
statement of {lit}`ExistsSubqueryOutput` with {lit}`NOT`. It has rows exactly when {lit}`p` is true for no
row of the table, has no rows exactly when it is true for some row, and is never an error. -/

namespace Belay.Sqlite.Model

/-- For every connection, values, table at a position of the database, condition of the subquery, and
calm statement of {lit}`SELECT 1 WHERE NOT EXISTS (q)` with that simple one-table subquery, the output of
the step has rows exactly when the condition is not true, in the context of the values, for any row of the
table. Proof sketch: {name}`resolvedStepOutput_noFrom_hasRows`; the value of {lit}`NOT EXISTS` is true when the
subquery has no row ({name}`Connection.queryContext_tableSubquery_zero`), which is the case exactly when the
condition keeps no row ({name}`Resolved.Query.Simple.results_eq_nil_iff`). -/
theorem resolvedStepOutput_notExists_hasRows (index position : Nat) (connection : Connection) (parameters : List Value)
    (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names])).hasRows = true ↔
      ∀ row ∈ Resolved.sourceRows table, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  have run := connection.queryContext_tableSubquery_zero parameters _ position table condition columns names present calm
  rw [resolvedStepOutput_noFrom_hasRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_not, Resolved.Expr.fault_exists, run]))]
  simp only [Option.all_some, Resolved.Expr.eval_not, Resolved.Expr.eval_exists, Resolved.truthy_not, run,
    Resolved.falsy, truthy_truth, isNull_truth, Bool.not_false, Bool.true_and, Bool.not_not,
    List.isEmpty_iff]
  exact (Resolved.Query.simple_isSimple _ _ _ _).results_eq_nil_iff _ _

/-- For every connection, values, table and calm statement as in {name}`resolvedStepOutput_notExists_hasRows`,
the output of the step has no rows exactly when the condition of the subquery is true for some row of the
table. Proof sketch: as for {name}`resolvedStepOutput_notExists_hasRows`, with
{name}`resolvedStepOutput_noFrom_hasNoRows` and {name}`Resolved.Query.Simple.results_ne_nil_iff`. -/
theorem resolvedStepOutput_notExists_hasNoRows (index position : Nat) (connection : Connection) (parameters : List Value)
    (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names])).hasNoRows = true ↔
      ∃ row ∈ Resolved.sourceRows table, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  have run := connection.queryContext_tableSubquery_zero parameters _ position table condition columns names present calm
  rw [resolvedStepOutput_noFrom_hasNoRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_not, Resolved.Expr.fault_exists, run]))]
  simp only [Option.all_some, Resolved.Expr.eval_not, Resolved.Expr.eval_exists, Resolved.truthy_not, run,
    Resolved.falsy, truthy_truth, isNull_truth, Bool.not_false, Bool.true_and, Bool.not_not]
  rw [List.isEmpty_eq_false_iff]
  exact (Resolved.Query.simple_isSimple _ _ _ _).results_ne_nil_iff _ _

/-- For every connection, values, table and calm statement as in {name}`resolvedStepOutput_notExists_hasRows`,
the output of the step is no error. Proof sketch: {name}`resolvedStepOutput_noFrom_not_isError`, with the
fault of the subquery from {name}`Connection.queryContext_tableSubquery_zero`. -/
theorem resolvedStepOutput_notExists_not_isError (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names])).isError = false := by
  have run := connection.queryContext_tableSubquery_zero parameters _ position table condition columns names present calm
  exact resolvedStepOutput_noFrom_not_isError index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_not, Resolved.Expr.fault_exists, run]))

end Belay.Sqlite.Model
