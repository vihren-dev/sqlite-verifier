import Belay.Sqlite.Model.SimpleQuerySteps
import Belay.Sqlite.Model.TableSourceLaws

set_option doc.verso true

/-! The output of a query of one table (ADR 0017, S4): the statement of the simple query
{lit}`SELECT columns FROM t WHERE condition` that reads the table at a position of the database. If
the statement is calm, its output has rows exactly when the condition is true for a row of the
table, has no rows exactly when it is true for none, and is never an error. -/

namespace Belay.Sqlite.Model

/-- For every connection, values, table at a catalog position of the database of the connection, and
calm statement of the simple query of that table with the given condition, columns and names, the
output of the step has rows exactly when the condition is true for some row of the table in scan order
(rowid order, or primary-key order for a {lit}`WITHOUT ROWID` table; {name}`Resolved.sourceRows`), evaluated in the context of the values
({name}`Resolved.EvalContext.bound`). A query without a condition has rows exactly when the table
has a row. Proof sketch: {name}`resolvedStepOutput_simple_hasRows` with the source rows of
{name}`Resolved.Query.source_first`. -/
theorem resolvedStepOutput_simpleTable_hasRows (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])).hasRows = true ↔
      ∃ row ∈ Resolved.sourceRows table, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  have found := Resolved.Query.source_first (connection.queryContext parameters (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []) (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names)
    connection.state.database position table rfl present
  rw [resolvedStepOutput_simple_hasRows index connection parameters _ (Resolved.Query.simple_isSimple _ _ _ _) _ calm found rfl,
    Connection.queryContext_of_calm connection parameters _ calm]
  rfl

/-- For every connection, values, table and calm statement as in
{name}`resolvedStepOutput_simpleTable_hasRows`, the output of the step has no rows exactly when the
condition is not true for any row of the table. Proof sketch:
{name}`resolvedStepOutput_simple_hasNoRows` with the source rows of
{name}`Resolved.Query.source_first`. -/
theorem resolvedStepOutput_simpleTable_hasNoRows (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])).hasNoRows = true ↔
      ∀ row ∈ Resolved.sourceRows table, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  have found := Resolved.Query.source_first (connection.queryContext parameters (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []) (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names)
    connection.state.database position table rfl present
  rw [resolvedStepOutput_simple_hasNoRows index connection parameters _ (Resolved.Query.simple_isSimple _ _ _ _) _ calm found rfl,
    Connection.queryContext_of_calm connection parameters _ calm]
  rfl

/-- For every connection, values, table and calm statement as in
{name}`resolvedStepOutput_simpleTable_hasRows`, the output of the step is no error. Proof sketch:
{name}`resolvedStepOutput_simple_not_isError` with the source rows of
{name}`Resolved.Query.source_first`. -/
theorem resolvedStepOutput_simpleTable_not_isError (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String) (present : connection.state.database.table position = some table)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])).isError = false :=
  resolvedStepOutput_simple_not_isError index connection parameters _ (Resolved.Query.simple_isSimple _ _ _ _) _ calm
    (Resolved.Query.source_first (connection.queryContext parameters (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []) (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names)
      connection.state.database position table rfl present)

end Belay.Sqlite.Model
