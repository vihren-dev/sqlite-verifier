import Belay.Sqlite.Model.AggregateQueryLaws
import Belay.Sqlite.Model.SimpleQuerySteps
import Belay.Sqlite.Model.TableSourceLaws

set_option doc.verso true

/-! The output of a whole-table aggregate query statement over a table (ADR 0017, S4): a calm statement
{lit}`SELECT agg(x) FROM t WHERE p` has one row exactly when the aggregate does not fail over the rows that
{lit}`WHERE` keeps, is an error exactly when it fails, and never has no row. -/

namespace Belay.Sqlite.Model

/-- For every connection, values, table at a catalog position of the database of the connection, and calm statement
of the whole-table aggregate query of that table ({name}`Resolved.Query.aggregateOf`), the output of the step has
rows exactly when the aggregate does not fail ({name}`Resolved.Aggregate.fails`) over the rows of the table in scan
order for which the condition is true, in the context of the values ({name}`Resolved.EvalContext.bound`). Without a
condition, these are all the rows. For example, {lit}`SUM` fails when the sum of integers leaves the 64-bit range and
no REAL value follows. Proof sketch: {name}`resolvedStepOutput_query_hasRows` with the source rows of
{name}`Resolved.Query.source_first` and the run of {name}`Resolved.Query.aggregateOf_run_of_faultless`; the one result
is a row. -/
theorem resolvedStepOutput_aggregateTable_hasRows (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (aggregate : Resolved.Aggregate)
    (name : String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query
      (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) [])).hasRows =
        true ↔
      aggregate.fails (Resolved.EvalContext.bound parameters) ((Resolved.sourceRows table).filter fun row =>
        condition.all fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) =
        false := by
  have found := Resolved.Query.source_first (connection.queryContext parameters
    (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) [])
    (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name)
    connection.state.database position table rfl present
  have plain := calm.subqueries_plain
  rw [resolvedStepOutput_query_hasRows index connection parameters _ _ [] _ calm.readsClock (calm.firstUnknown _) found
      (Resolved.Query.aggregateOf_bindWindow _ _ _ _ parameters),
    Resolved.Query.aggregateOf_run_of_faultless _ _ _ _ _ calm.query_plain _ (calm.faultless_nil connection parameters),
    Resolved.Query.aggregateOf_results, Connection.queryContext_of_calm connection parameters _ calm]
  simp [plain, Resolved.Query.aggregateOf_filtered]

/-- For every connection, values, table and calm statement as in
{name}`resolvedStepOutput_aggregateTable_hasRows`, the output of the step never has no rows. Proof sketch: the
one result of the run is one row ({name}`Resolved.Query.aggregateOf_results`). -/
theorem resolvedStepOutput_aggregateTable_not_hasNoRows (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (aggregate : Resolved.Aggregate)
    (name : String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query
      (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) [])).hasNoRows =
        false := by
  have found := Resolved.Query.source_first (connection.queryContext parameters
    (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) [])
    (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name)
    connection.state.database position table rfl present
  refine Bool.eq_false_iff.2 fun hasNoRows => ?_
  have := (resolvedStepOutput_query_hasNoRows index connection parameters _ _ [] _ calm.readsClock (calm.firstUnknown _)
    found (Resolved.Query.aggregateOf_bindWindow _ _ _ _ parameters)).1 hasNoRows
  rw [Resolved.Query.aggregateOf_run_of_faultless _ _ _ _ _ calm.query_plain _ (calm.faultless_nil connection parameters),
    Resolved.Query.aggregateOf_results] at this
  simp at this

/-- For every connection, values, table and calm statement as in
{name}`resolvedStepOutput_aggregateTable_hasRows`, the output of the step is an error exactly when the aggregate
fails over the rows that the condition keeps. Proof sketch: {name}`resolvedStepOutput_query_isError` with the run of
{name}`Resolved.Query.aggregateOf_run_of_faultless`, which has no window mismatch and no fault. -/
theorem resolvedStepOutput_aggregateTable_isError (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (aggregate : Resolved.Aggregate)
    (name : String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query
      (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) [])).isError =
        true ↔
      aggregate.fails (Resolved.EvalContext.bound parameters) ((Resolved.sourceRows table).filter fun row =>
        condition.all fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) =
        true := by
  have found := Resolved.Query.source_first (connection.queryContext parameters
    (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) [])
    (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name)
    connection.state.database position table rfl present
  have plain := calm.subqueries_plain
  rw [resolvedStepOutput_query_isError index connection parameters _ [] _ calm.readsClock (calm.firstUnknown _) found,
    Resolved.Query.aggregateOf_run_of_faultless _ _ _ _ _ calm.query_plain _ (calm.faultless_nil connection parameters),
    Connection.queryContext_of_calm connection parameters _ calm]
  simp [plain, Resolved.Query.aggregateOf_filtered]

/-- For every condition and aggregate whose expressions are calm ({name}`Resolved.Expr.Calm`) and every position, the
statement of the whole-table aggregate query of the first source of a table is calm
({name}`Resolved.Statement.Calm`): the first source of a table has no expression, so the expressions of the
statement are the condition and the operands of the aggregate. Proof sketch: list the expressions of the query. -/
theorem Resolved.Statement.Calm.aggregateOf_first (position : Nat) (condition : Option Resolved.Expr)
    (aggregate : Resolved.Aggregate) (name : String) (conditionCalm : ∀ expression ∈ condition.toList, expression.Calm)
    (operandsCalm : ∀ expression ∈ (Resolved.Output.aggregate aggregate).operands, expression.Calm) :
    (Resolved.Statement.query
      (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition aggregate name) []).Calm := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.expressions, Resolved.Query.keptExpressions,
    Resolved.Query.aggregateOf, Resolved.QuerySource.first, Resolved.QuerySource.expressions, List.mem_append,
    List.mem_flatMap, List.flatMap_nil, List.append_nil, List.mem_cons, List.mem_nil_iff, or_false] at member
  simp only [Resolved.Output.scalars, List.map_nil, List.not_mem_nil, or_false] at member
  rcases member with (member | ⟨_, rfl, member | member⟩) | member
  · exact conditionCalm expression member
  · simp at member
  · simp at member
  · simp_all

end Belay.Sqlite.Model
