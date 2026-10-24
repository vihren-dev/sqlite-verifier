import Belay.Sqlite.Model.SimpleResultsLaws
import Belay.Sqlite.Model.SelectOneRowsOutput
import Belay.Sqlite.Model.ExistsSubqueryOutput

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE c(SELECT e FROM t WHERE p)` for a condition {lit}`c` that names no scalar
subquery, such as {lit}`x IN (SELECT e FROM t WHERE p)` (ADR 0017, S4): a statement without {lit}`FROM` and with one
subquery, a simple query of one table with one expression column. The subquery gives the value of {lit}`e` for each row
of the table for which {lit}`p` is true, in the order of the scan, with no fault and certain rows. The statement has rows
exactly when {lit}`c` is true with these rows as the result of the subquery. -/

namespace Belay.Sqlite.Model

/-- The result of a subquery that gives the rows {lit}`rows`, with no fault and certain rows, as a simple query of a
table gives its rows. -/
def Resolved.SubqueryRun.certain (rows : List (List Value)) : Resolved.SubqueryRun := { rows, fault := .none }

/-- For every rows, the result of a subquery that gives these rows without fault is quiet. Proof sketch: the
definition computes. -/
theorem Resolved.SubqueryRun.certain_quiet (rows : List (List Value)) : (Resolved.SubqueryRun.certain rows).Quiet :=
  ⟨rfl, rfl, rfl⟩

/-- The rows that the simple query {lit}`SELECT e FROM t WHERE p` gives over the rows of the table in a context:
the value of {lit}`e` for each row for which {lit}`p` is true, one value in a row, in the order of the rows. -/
def Resolved.scalarRows (context : Resolved.EvalContext) (condition : Option Resolved.Expr) (value : Resolved.Expr)
    (table : Table) : List (List Value) :=
  ((Resolved.sourceRows table).filter fun row => condition.all fun expression =>
    Resolved.truthy (expression.eval context row)).map fun row => [value.eval context row]

/-- The expressions of the simple query of the first source of a table with one scalar column are its condition,
if any, and the expression of the column. Proof sketch: the definitions compute. -/
theorem Resolved.Query.simple_scalar_expressions (position : Nat) (condition : Option Resolved.Expr)
    (value : Resolved.Expr) (names : List String) :
    (Resolved.Query.simple [Resolved.QuerySource.first position] condition [.scalar value] names).expressions =
      condition.toList ++ [value] := by
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.simple, Resolved.QuerySource.first,
    Resolved.QuerySource.expressions, Resolved.Output.scalars, Resolved.Output.operands]

/-- For every calm condition {lit}`c`, every calm condition of the subquery and every calm expression of its column,
the statement {lit}`SELECT 1 WHERE c` with the simple query of the first source of a table with that column as its one
subquery is calm ({name}`Resolved.Statement.Calm`). Proof sketch: the expressions of the statement are the condition,
the literal one, the condition of the subquery and the column
({name}`Resolved.Query.simple_scalar_expressions`). -/
theorem Resolved.Statement.Calm.selectOne_scalar (position : Nat) (main : Resolved.Expr)
    (subCondition : Option Resolved.Expr) (value : Resolved.Expr) (names : List String) (mainCalm : main.Calm)
    (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm) (valueCalm : value.Calm) :
    (Resolved.Statement.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names]).Calm := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions,
    Resolved.Query.simple_scalar_expressions, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append,
    List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with (rfl | rfl) | member | rfl
  · exact mainCalm
  · exact Resolved.Expr.calm_literal _
  · exact subCalm expression (by simpa using member)
  · exact valueCalm

/-- For every connection, values, query, table at a position of the database and calm statement of the query with
one subquery that is the simple query of that table with one scalar column, subquery 0 of the context of the statement
for the outer row with no cells has the rows {name}`Resolved.scalarRows` as its rows, no fault and certain rows, once its
first row is marked certain. Proof sketch: {name}`Connection.queryContext_tableSubquery_zero` gives the rows of the
simple query, which are the values of the column for the kept rows ({name}`Resolved.Query.Simple.results_eq`). -/
theorem Connection.queryContext_scalarSubquery_zero (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (position : Nat) (table : Table) (condition : Option Resolved.Expr)
    (value : Resolved.Expr) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query query
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition [.scalar value] names]).Calm) :
    ((connection.queryContext parameters query
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition [.scalar value] names]).subqueries 0 []).certainFirst =
      Resolved.SubqueryRun.certain
        (Resolved.scalarRows (Resolved.EvalContext.bound parameters) condition value table) := by
  rw [connection.queryContext_tableSubquery_zero parameters query position table condition [.scalar value] names present calm,
    (Resolved.Query.simple_isSimple _ _ _ _).results_eq]
  rfl

/-- For every connection, values, query, table and calm statement as in
{name}`Connection.queryContext_scalarSubquery_zero`, the subqueries of the context of the statement for the empty outer
row are, once the first row is marked certain, the list of the one result: subquery 0 gives
{name}`Resolved.scalarRows`, and a later index names no subquery, so it gives no row and no fault. Proof sketch: the
case of index 0 is {name}`Connection.queryContext_scalarSubquery_zero`; the other indexes are past the one subquery, which
the definition of the context computes. -/
theorem Connection.queryContext_scalarSubquery_runs (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (position : Nat) (table : Table) (condition : Option Resolved.Expr)
    (value : Resolved.Expr) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query query
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition [.scalar value] names]).Calm) (index : Nat) :
    ((connection.queryContext parameters query
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition [.scalar value] names]).subqueries index []).certainFirst =
      ([Resolved.SubqueryRun.certain
        (Resolved.scalarRows (Resolved.EvalContext.bound parameters) condition value table)][index]?).getD
        { rows := [], fault := .none } := by
  cases index with
  | zero =>
    exact connection.queryContext_scalarSubquery_zero parameters query position table condition value names present calm
  | succ later =>
    simp only [Connection.queryContext, Resolved.statementContext, List.length_singleton]
    simp [Resolved.subqueryContext, Resolved.SubqueryRun.certainFirst]

/-- For every connection, values, condition {lit}`c` without scalar subquery, table at a position of the database,
condition and column of the subquery, and calm statement of {lit}`SELECT 1 WHERE c` with the simple query of that table
and column as its one subquery, the output of the step has rows exactly when {lit}`c` is true in the context of the values
in which subquery 0 gives the values of the column for the rows for which the condition is true
({name}`Resolved.scalarRows`). Proof sketch: {name}`resolvedStepOutput_selectOne_rows_hasRows` with the one result of
{name}`Connection.queryContext_scalarSubquery_runs`, which is quiet. -/
theorem resolvedStepOutput_scalar_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (position : Nat) (table : Table) (subCondition : Option Resolved.Expr)
    (value : Resolved.Expr) (names : List String)
    (present : connection.state.database.table position = some table)
    (noScalar : condition.any (· matches .subquery _) = false)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names])).hasRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.certain
          (Resolved.scalarRows (Resolved.EvalContext.bound parameters) subCondition value table)]) []) = true :=
  resolvedStepOutput_selectOne_rows_hasRows index connection parameters condition _ _ calm noScalar
    (connection.queryContext_scalarSubquery_runs parameters _ position table subCondition value names present calm)
    (fun run member => by simp at member; rw [member]; exact Resolved.SubqueryRun.certain_quiet _)

/-- For every connection, values, condition, table, subquery and calm statement as in
{name}`resolvedStepOutput_scalar_hasRows`, the output of the step has no rows exactly when {lit}`c` is not true in that
context. Proof sketch: {name}`resolvedStepOutput_selectOne_rows_hasNoRows` with the same result. -/
theorem resolvedStepOutput_scalar_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (position : Nat) (table : Table) (subCondition : Option Resolved.Expr)
    (value : Resolved.Expr) (names : List String)
    (present : connection.state.database.table position = some table)
    (noScalar : condition.any (· matches .subquery _) = false)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names])).hasNoRows = true ↔
      Resolved.truthy (condition.eval ((Resolved.EvalContext.bound parameters).withRuns
        [Resolved.SubqueryRun.certain
          (Resolved.scalarRows (Resolved.EvalContext.bound parameters) subCondition value table)]) []) = false :=
  resolvedStepOutput_selectOne_rows_hasNoRows index connection parameters condition _ _ calm noScalar
    (connection.queryContext_scalarSubquery_runs parameters _ position table subCondition value names present calm)
    (fun run member => by simp at member; rw [member]; exact Resolved.SubqueryRun.certain_quiet _)

/-- For every connection, values, condition, table, subquery and calm statement as in
{name}`resolvedStepOutput_scalar_hasRows`, the output of the step is no error. Proof sketch:
{name}`resolvedStepOutput_selectOne_rows_not_isError` with the same result. -/
theorem resolvedStepOutput_scalar_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Resolved.Expr) (position : Nat) (table : Table) (subCondition : Option Resolved.Expr)
    (value : Resolved.Expr) (names : List String)
    (present : connection.state.database.table position = some table)
    (noScalar : condition.any (· matches .subquery _) = false)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere condition)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar value] names])).isError = false :=
  resolvedStepOutput_selectOne_rows_not_isError index connection parameters condition _ _ calm noScalar
    (connection.queryContext_scalarSubquery_runs parameters _ position table subCondition value names present calm)
    (fun run member => by simp at member; rw [member]; exact Resolved.SubqueryRun.certain_quiet _)

end Belay.Sqlite.Model
