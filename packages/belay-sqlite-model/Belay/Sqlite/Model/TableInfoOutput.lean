import Belay.Sqlite.Model.TableInfoResolution
import Belay.Sqlite.Model.SelectOneResolution
import Belay.Sqlite.Model.QueryJoinLaws
import Belay.Sqlite.Model.SimpleQuerySteps

set_option doc.verso true

/-! The output of {lit}`SELECT 1 FROM pragma_table_info('t') WHERE p` (ADR 0017, S4): the statement of the simple query
of one pragma source with fixed rows. If the statement is calm, its output has rows exactly when the condition is true for
a row of the pragma, has no rows exactly when it is true for none, and is never an error. -/

namespace Belay.Sqlite.Model

/-- For every evaluation context, query whose only source is a pragma with fixed rows ({name}`Resolved.QuerySource.pragma`)
and database, the source rows of the query are the rows of the pragma, with the width of the pragma and no fault. Proof
sketch: the join of an inner source without a condition keeps the concatenation of the one empty row with each row of the
pragma. -/
theorem Resolved.Query.source_pragma_fixed (context : Resolved.EvalContext) (query : Resolved.Query) (database : Database)
    (width : Nat) (rows : List (List Value))
    (sources : query.sources = [Resolved.QuerySource.pragma (.fixed width rows)]) :
    query.source context database = some { rows, width, fault := .none } := by
  simp [Resolved.Query.source, sources, List.foldlM, Resolved.QuerySource.join, Resolved.QuerySource.pragma,
    Resolved.PragmaRows.rowsOn, Resolved.PragmaRows.width, Resolved.joinRows, Resolved.joinRow, Resolved.joinMatches,
    Resolved.QuerySource.matches, bind, Option.bind, pure]

/-- For every pragma rows and condition that is calm, the statement of the simple query of the pragma source with that
condition and the literal one is calm ({name}`Resolved.Statement.Calm`). Proof sketch: the expressions of the statement are
the condition and the literal, and a pragma source has no expression. -/
theorem Resolved.Statement.Calm.selectOne_pragma (pragma : Resolved.PragmaRows) (condition : Option Resolved.Expr)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.pragma pragma] condition
      [.scalar (.literal (.integer 1))] ["1"]) []).Calm := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.expressions, Resolved.Query.keptExpressions,
    Resolved.Query.simple, Resolved.QuerySource.pragma, Resolved.QuerySource.expressions, List.mem_append,
    List.mem_flatMap, List.flatMap_nil, List.append_nil, List.mem_cons, List.mem_nil_iff, or_false] at member
  have literal : (Resolved.Expr.literal (.integer 1)).Calm := by
    simp [Resolved.Expr.Calm, Resolved.Expr.any, Resolved.Expr.isFallibleCall, Resolved.Expr.readsClockHere,
      Resolved.Expr.readsCounterHere]
  simp only [Resolved.Output.scalars, Resolved.Output.operands, List.mem_singleton, List.not_mem_nil, exists_eq_left,
    List.map_nil, or_false, Option.toList_none] at member
  rcases member with member | rfl
  · exact calm expression member
  · exact literal

/-- For every connection, values, width, rows of a pragma, condition, columns and names, and calm statement of the simple
query of the pragma source with those rows, the output of the step has rows exactly when the condition is true for some
row of the pragma, evaluated in the context of the values ({name}`Resolved.EvalContext.bound`). Without a condition, it has
rows exactly when the pragma has a row. Proof sketch: {name}`resolvedStepOutput_simple_hasRows` with the source rows of
{name}`Resolved.Query.source_pragma_fixed`. -/
theorem resolvedStepOutput_simplePragma_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (width : Nat) (rows : List (List Value)) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.pragma (.fixed width rows)] condition
      columns names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.pragma (.fixed width rows)] condition columns names) [])).hasRows = true ↔
      ∃ row ∈ rows, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = true := by
  rw [resolvedStepOutput_simple_hasRows index connection parameters _ (Resolved.Query.simple_isSimple _ _ _ _)
    { rows, width, fault := .none } calm
    (Resolved.Query.source_pragma_fixed _ _ _ width rows rfl) rfl,
    Connection.queryContext_of_calm connection parameters _ calm]
  rfl

/-- For every connection, values, pragma rows and calm statement as in {name}`resolvedStepOutput_simplePragma_hasRows`,
the output of the step has no rows exactly when the condition is not true for any row of the pragma. Proof sketch:
{name}`resolvedStepOutput_simple_hasNoRows` with the source rows of {name}`Resolved.Query.source_pragma_fixed`. -/
theorem resolvedStepOutput_simplePragma_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (width : Nat) (rows : List (List Value)) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.pragma (.fixed width rows)] condition
      columns names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.pragma (.fixed width rows)] condition columns names) [])).hasNoRows = true ↔
      ∀ row ∈ rows, condition.all
        (fun expression => Resolved.truthy (expression.eval (Resolved.EvalContext.bound parameters) row)) = false := by
  rw [resolvedStepOutput_simple_hasNoRows index connection parameters _ (Resolved.Query.simple_isSimple _ _ _ _)
    { rows, width, fault := .none } calm
    (Resolved.Query.source_pragma_fixed _ _ _ width rows rfl) rfl,
    Connection.queryContext_of_calm connection parameters _ calm]
  rfl

/-- For every connection, values, pragma rows and calm statement as in {name}`resolvedStepOutput_simplePragma_hasRows`,
the output of the step is no error. Proof sketch: {name}`resolvedStepOutput_simple_not_isError` with the source rows of
{name}`Resolved.Query.source_pragma_fixed`. -/
theorem resolvedStepOutput_simplePragma_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (width : Nat) (rows : List (List Value)) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.pragma (.fixed width rows)] condition
      columns names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [Resolved.QuerySource.pragma (.fixed width rows)] condition columns names) [])).isError = false :=
  resolvedStepOutput_simple_not_isError index connection parameters _ (Resolved.Query.simple_isSimple _ _ _ _)
    { rows, width, fault := .none } calm (Resolved.Query.source_pragma_fixed _ _ _ width rows rfl)

end Belay.Sqlite.Model
