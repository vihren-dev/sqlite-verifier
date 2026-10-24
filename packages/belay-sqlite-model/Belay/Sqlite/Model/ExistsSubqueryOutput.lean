import Belay.Sqlite.Model.NoFromQuerySteps
import Belay.Sqlite.Model.SimpleSubqueryRun
import Belay.Sqlite.Model.TableSourceLaws
import Belay.Sqlite.Model.ExprEvalLaws
import Belay.Sqlite.Model.ExprCalmLaws

set_option doc.verso true

/-! The output of {lit}`SELECT 1 WHERE [NOT] EXISTS (SELECT … FROM t WHERE p)` (ADR 0017, S4): a
statement without {lit}`FROM` and with one subquery, a simple query of one table. The subquery gives a row exactly
when {lit}`p` is true for a row of the table, so {lit}`EXISTS` makes the statement have rows exactly then, and
{lit}`NOT EXISTS` exactly when {lit}`p` is true for no row. -/

namespace Belay.Sqlite.Model

/-- The context of the subquery evaluation of a calm statement is quiet: the values bound to the
parameters, with no subquery and no counter. Proof sketch: the context gives no fault and certain
rows for every index. -/
theorem Resolved.EvalContext.bound_quiet (parameters : List Value) : (Resolved.EvalContext.bound parameters).Quiet :=
  fun _ _ => ⟨rfl, rfl, rfl⟩

/-- For every connection, values, query and calm statement of the query with one subquery, subquery 0 of the context
of the statement on the connection, for an outer row, is the run of that subquery
({name}`Resolved.Query.subqueryRun`) in the context of the values, over the database of the connection. Proof
sketch: the statement reads no counter, so its context is the context of the values with the
subquery list at depth one, and the definition of {name}`Resolved.subqueryContext` computes. -/
theorem Connection.queryContext_subquery_zero (connection : Connection) (parameters : List Value)
    (query inner : Resolved.Query) (calm : (Resolved.Statement.query query [inner]).Calm) (outer : List Value) :
    (connection.queryContext parameters query [inner]).subqueries 0 outer =
      inner.subqueryRun (Resolved.EvalContext.bound parameters) connection.state.database outer := by
  simp only [Connection.queryContext, calm.counterReads, Resolved.statementContext]
  rfl

/-- For every connection, values, query and calm statement of the query with one subquery that is the
simple query of the table at a position of the database, subquery 0 of the context for the outer row with no cells has the
one result of the simple query over the rows of the table in scan order (rowid order, or primary-key order for a {lit}`WITHOUT ROWID` table) as its rows, no fault and certain rows. Proof sketch:
{name}`Connection.queryContext_subquery_zero` and {name}`Resolved.Query.subqueryRun_simple` with the source rows of
{name}`Resolved.Query.source_first`; the context is quiet, so no expression has a fault. -/
theorem Connection.queryContext_tableSubquery_zero (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (position : Nat) (table : Table) (condition : Option Resolved.Expr)
    (columns : List Resolved.Output) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query query [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (connection.queryContext parameters query [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).subqueries 0 [] =
      { rows := (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names).results
          (Resolved.EvalContext.bound parameters) (Resolved.sourceRows table),
        fault := .none,
        firstCertain := (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names).windowCertain
          (Resolved.EvalContext.bound parameters) (Resolved.sourceRows table) (some 1),
        rowsCertain := true, ending := .done } := by
  have plain := calm.subquery_plain (List.mem_singleton_self _)
  rw [connection.queryContext_subquery_zero parameters query _ calm]
  refine Resolved.Query.subqueryRun_simple _ _ _ (Resolved.Query.simple_isSimple _ _ _ _) rfl _
    (Resolved.Query.source_first _ _ _ position table rfl present) rfl plain fun row _ expression member => ?_
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  exact Resolved.Expr.fault_of_plain _ (Resolved.EvalContext.bound_quiet parameters) row expression (plain expression member)

/-- For every connection, values, table at a position of the database, condition of the subquery, and
calm statement of {lit}`SELECT 1 WHERE EXISTS (q)` with that simple one-table subquery, the output of
the step has rows exactly when the condition is true, in the context of the values, for some row of the
table. Proof sketch: {name}`resolvedStepOutput_noFrom_hasRows`; the value of {lit}`EXISTS` is true when the
subquery has a row ({name}`Connection.queryContext_tableSubquery_zero`), which is the case exactly when the
condition keeps a row ({name}`Resolved.Query.Simple.results_ne_nil_iff`). -/
theorem resolvedStepOutput_exists_hasRows (index position : Nat) (connection : Connection) (parameters : List Value)
    (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.exists 0))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.exists 0))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names])).hasRows = true ↔
      ∃ row ∈ Resolved.sourceRows table, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  have run := connection.queryContext_tableSubquery_zero parameters _ position table condition columns names present calm
  rw [resolvedStepOutput_noFrom_hasRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_exists, run]))]
  simp only [Option.all_some, Resolved.Expr.eval_exists, run, truthy_truth, Bool.not_eq_eq_eq_not,
    Bool.not_true, List.isEmpty_eq_false_iff]
  exact (Resolved.Query.simple_isSimple _ _ _ _).results_ne_nil_iff _ _

/-- For every connection, values, table and calm statement as in {name}`resolvedStepOutput_exists_hasRows`, the
output of the step has no rows exactly when the condition of the subquery is not true for any row of the
table. Proof sketch: as for {name}`resolvedStepOutput_exists_hasRows`, with
{name}`resolvedStepOutput_noFrom_hasNoRows` and {name}`Resolved.Query.Simple.results_eq_nil_iff`. -/
theorem resolvedStepOutput_exists_hasNoRows (index position : Nat) (connection : Connection) (parameters : List Value)
    (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.exists 0))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.exists 0))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names])).hasNoRows = true ↔
      ∀ row ∈ Resolved.sourceRows table, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  have run := connection.queryContext_tableSubquery_zero parameters _ position table condition columns names present calm
  rw [resolvedStepOutput_noFrom_hasNoRows index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_exists, run]))]
  simp only [Option.all_some, Resolved.Expr.eval_exists, run, truthy_truth, Bool.not_eq_eq_eq_not,
    Bool.not_false, List.isEmpty_iff]
  exact (Resolved.Query.simple_isSimple _ _ _ _).results_eq_nil_iff _ _

/-- For every connection, values, table and calm statement as in {name}`resolvedStepOutput_exists_hasRows`, the
output of the step is no error. Proof sketch: {name}`resolvedStepOutput_noFrom_not_isError`, with the fault of the
subquery from {name}`Connection.queryContext_tableSubquery_zero`. -/
theorem resolvedStepOutput_exists_not_isError (index position : Nat) (connection : Connection) (parameters : List Value)
    (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output) (names : List String)
    (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.selectOneWhere (.exists 0))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names]).Calm) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere (.exists 0))
      [Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names])).isError = false := by
  have run := connection.queryContext_tableSubquery_zero parameters _ position table condition columns names present calm
  exact resolvedStepOutput_noFrom_not_isError index connection parameters _ _ _ _ calm
    (Resolved.Query.selectOneWhere_faultless _ _ (by rw [Resolved.Expr.fault_exists, run]))

/-- The expressions of the simple query of the first source of a table are its condition, if any, and
the expressions of its result column {lit}`1`. Proof sketch: the definitions compute. -/
theorem Resolved.Query.simple_first_expressions (position : Nat) (condition : Option Resolved.Expr) :
    (Resolved.Query.simple [Resolved.QuerySource.first position] condition [.scalar (.literal (.integer 1))] ["1"]).expressions =
      condition.toList ++ [.literal (.integer 1)] := by
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.simple, Resolved.QuerySource.first,
    Resolved.QuerySource.expressions, Resolved.Output.scalars, Resolved.Output.operands]

/-- For every calm condition {lit}`c` and every calm condition of the subquery, the statement of
{lit}`SELECT 1 WHERE c` with the one subquery {lit}`SELECT 1 FROM t WHERE p` that resolution gives is calm
({name}`Resolved.Statement.Calm`): the literal one is calm, and the first source of a table has no
expression. Proof sketch: the expressions of the statement are the condition, the literal one of the
statement's query, the subquery's condition and the literal one of the subquery. -/
theorem Resolved.Statement.Calm.selectOne_subquery (position : Nat) (main : Resolved.Expr)
    (subCondition : Option Resolved.Expr) (mainCalm : main.Calm)
    (subCalm : ∀ expression ∈ subCondition.toList, expression.Calm) :
    (Resolved.Statement.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition
        [.scalar (.literal (.integer 1))] ["1"]]).Calm := by
  have literal : (Resolved.Expr.literal (.integer 1)).Calm := Resolved.Expr.calm_literal _
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions,
    Resolved.Query.simple_first_expressions, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append,
    List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with (rfl | rfl) | member | rfl
  · exact mainCalm
  · exact literal
  · exact subCalm expression (by simpa using member)
  · exact literal

end Belay.Sqlite.Model
