import Belay.Sqlite.Model.CountQueryLaws
import Belay.Sqlite.Model.SelectOneSubqueryOutput

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE c(SELECT count(*) FROM t WHERE p)` (ADR 0017, S4): a statement without
{lit}`FROM` and with one subquery, a count query of one table. The subquery gives one row with the number of
rows of the table for which {lit}`p` is true, so the statement has rows exactly when {lit}`c` is true with that
number as the value of the subquery. -/

namespace Belay.Sqlite.Model

/-- The result of a subquery that gives one row with the integer {lit}`count`, no fault and certain rows, as
{lit}`SELECT count(*) FROM t` does. -/
def Resolved.SubqueryRun.count (count : Nat) : Resolved.SubqueryRun :=
  { rows := [[.integer count]], fault := .none }

/-- For every number, the result of a subquery that gives that number as one row is quiet. Proof sketch: the
definition computes. -/
theorem Resolved.SubqueryRun.count_quiet (count : Nat) : (Resolved.SubqueryRun.count count).Quiet := ⟨rfl, rfl, rfl⟩

/-- The number of rows of a table for which a condition is true in a context, in scan order: all the rows when
there is no condition. For example, with the condition {lit}`x > 1` it counts the rows whose {lit}`x` is greater
than one; a row for which the condition is NULL is not counted. -/
def Resolved.countMatching (context : Resolved.EvalContext) (condition : Option Resolved.Expr) (table : Table) : Nat :=
  ((Resolved.sourceRows table).filter fun row => condition.all fun expression =>
    Resolved.truthy (expression.eval context row)).length

/-- The expressions of the count query of the first source of a table are its condition, if any. Proof sketch:
the definitions compute. -/
theorem Resolved.Query.countOf_first_expressions (position : Nat) (condition : Option Resolved.Expr) (name : String) :
    (Resolved.Query.countOf [Resolved.QuerySource.first position] condition name).expressions = condition.toList := by
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.countOf, Resolved.QuerySource.first,
    Resolved.QuerySource.expressions, Resolved.Output.scalars, Resolved.Output.operands]

/-- For every calm condition {lit}`c` and every calm condition of the subquery, the statement
{lit}`SELECT 1 WHERE c` with the count query of the first source of a table as its one subquery is calm
({name}`Resolved.Statement.Calm`). Proof sketch: the expressions of the statement are the condition, the
literal one, and the condition of the subquery ({name}`Resolved.Query.countOf_first_expressions`). -/
theorem Resolved.Statement.Calm.selectOne_count (position : Nat) (main : Resolved.Expr) (subCondition : Option Resolved.Expr)
    (name : String) (mainCalm : main.Calm) (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    (Resolved.Statement.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name]).Calm := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions,
    Resolved.Query.countOf_first_expressions, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append,
    List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with (rfl | rfl) | member
  · exact mainCalm
  · exact Resolved.Expr.calm_literal _
  · exact subCalm expression member

/-- For every connection, values, query, table at a position of the database and calm statement of the query with
one subquery that is the count query of that table, subquery 0 of the context of the statement for the outer row
with no cells has the one row with the number of rows of the table for which the condition is true
({name}`Resolved.countMatching`), no fault and certain rows. Proof sketch:
{name}`Connection.queryContext_subquery_zero` and {name}`Resolved.Query.Count.subqueryRun` with the source
rows of {name}`Resolved.Query.source_first`; the context is quiet, so no expression has a fault. -/
theorem Connection.queryContext_countSubquery_zero (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (position : Nat) (table : Table) (condition : Option Resolved.Expr) (name : String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query query
      [Resolved.Query.countOf [Resolved.QuerySource.first position] condition name]).Calm) :
    (connection.queryContext parameters query
      [Resolved.Query.countOf [Resolved.QuerySource.first position] condition name]).subqueries 0 [] =
      Resolved.SubqueryRun.count (Resolved.countMatching (Resolved.EvalContext.bound parameters) condition table) := by
  have plain := calm.subquery_plain (List.mem_singleton_self _)
  rw [connection.queryContext_subquery_zero parameters query _ calm]
  rw [(Resolved.Query.countOf_isCount _ _ _).subqueryRun _ _ rfl _
    (Resolved.Query.source_first _ _ _ position table rfl present) rfl plain fun row _ expression member => ?_]
  · rfl
  · simp only [List.all_eq_true, Bool.not_eq_true'] at plain
    exact Resolved.Expr.fault_of_plain _ (Resolved.EvalContext.bound_quiet parameters) row expression (plain expression member)

/-- For every connection, values, query, table and calm statement as in
{name}`Connection.queryContext_countSubquery_zero`, the context of the statement for the empty outer row serves the
subqueries of the statement as the list of the one result of the count query: subquery 0 gives the count, and
a later index names no subquery, so it gives no row and no fault. Proof sketch: the case of index 0 is
{name}`Connection.queryContext_countSubquery_zero`; the other indexes are past the one subquery, which the
definition of the context computes. -/
theorem Connection.queryContext_countSubquery_runs (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (position : Nat) (table : Table) (condition : Option Resolved.Expr) (name : String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query query
      [Resolved.Query.countOf [Resolved.QuerySource.first position] condition name]).Calm) (index : Nat) :
    (connection.queryContext parameters query
      [Resolved.Query.countOf [Resolved.QuerySource.first position] condition name]).subqueries index [] =
      ([Resolved.SubqueryRun.count (Resolved.countMatching (Resolved.EvalContext.bound parameters) condition table)][index]?).getD
        { rows := [], fault := .none } := by
  cases index with
  | zero => exact connection.queryContext_countSubquery_zero parameters query position table condition name present calm
  | succ later =>
    simp only [Connection.queryContext, Resolved.statementContext, List.length_singleton]
    simp [Resolved.subqueryContext]

/-- For every connection, values, condition {lit}`c`, table at a position of the database, condition of the
subquery and calm statement of {lit}`SELECT 1 WHERE c` with the count query of that table as its one subquery,
the output of the step has rows exactly when {lit}`c` is true in the context of the values in which subquery 0 is
the one row with the number of rows of the table for which the condition is true
({name}`Resolved.countMatching`). Proof sketch: {name}`resolvedStepOutput_selectOne_hasRows` with the results of
{name}`Connection.queryContext_countSubquery_runs`, which are quiet. -/
theorem resolvedStepOutput_count_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (position : Nat) (table : Table) (subCondition : Option Resolved.Expr) (name : String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name])).hasRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.count (Resolved.countMatching (Resolved.EvalContext.bound parameters) subCondition table)]) []) = true :=
  resolvedStepOutput_selectOne_hasRows index connection parameters condition _ _ calm
    (connection.queryContext_countSubquery_runs parameters _ position table subCondition name present calm)
    (fun run member => by simp at member; rw [member]; exact Resolved.SubqueryRun.count_quiet _)

/-- For every connection, values, condition, table, condition of the subquery and calm statement as in
{name}`resolvedStepOutput_count_hasRows`, the output of the step has no rows exactly when {lit}`c` is not true in
that context. Proof sketch: {name}`resolvedStepOutput_selectOne_hasNoRows` with the same results. -/
theorem resolvedStepOutput_count_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (position : Nat) (table : Table) (subCondition : Option Resolved.Expr) (name : String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name])).hasNoRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.count (Resolved.countMatching (Resolved.EvalContext.bound parameters) subCondition table)]) []) = false :=
  resolvedStepOutput_selectOne_hasNoRows index connection parameters condition _ _ calm
    (connection.queryContext_countSubquery_runs parameters _ position table subCondition name present calm)
    (fun run member => by simp at member; rw [member]; exact Resolved.SubqueryRun.count_quiet _)

/-- For every connection, values, condition, table, condition of the subquery and calm statement as in
{name}`resolvedStepOutput_count_hasRows`, the output of the step is no error. Proof sketch:
{name}`resolvedStepOutput_selectOne_not_isError` with the same results. -/
theorem resolvedStepOutput_count_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (position : Nat) (table : Table) (subCondition : Option Resolved.Expr) (name : String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition name])).isError = false :=
  resolvedStepOutput_selectOne_not_isError index connection parameters condition _ _ calm
    (connection.queryContext_countSubquery_runs parameters _ position table subCondition name present calm)
    (fun run member => by simp at member; rw [member]; exact Resolved.SubqueryRun.count_quiet _)

end Belay.Sqlite.Model
