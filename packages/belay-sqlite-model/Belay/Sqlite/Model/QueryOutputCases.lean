import Belay.Sqlite.Model.QueryOutputOn

set_option doc.verso true

/-! The cases of the output of a query (ADR 0017, S4): the first branch of
{name}`Belay.Sqlite.Model.Resolved.Query.outputOn` that applies, by the window mismatch, the
overflow and the failing function of the run of the query over its source rows. -/

namespace Belay.Sqlite.Model

/-- For every query and statement data whose query has source rows {lit}`source` and a bound window
{lit}`bound`, when the run of the query has no window mismatch, no overflow and no failing
function, the output of the query ({name}`Resolved.Query.outputOn`) is the output of the results
that SQLite may give for the bound query. Proof sketch: unfold the output; the three conditions
take the last branch. -/
theorem Resolved.Query.outputOn_clean (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows) (bound : Resolved.Query)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source)
    (window : query.bindWindow parameters = some bound)
    (mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false)
    (overflow : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = false)
    (fault : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault ≠ .must) :
    query.outputOn clock counters parameters database subqueries =
      Output.ofResults (bound.possibleResults (Resolved.statementContext clock counters parameters database subqueries) source.rows) := by
  unfold Resolved.Query.outputOn Resolved.Query.runOn Resolved.Query.possibleOn
  simp [found, window, mismatch, overflow, fault]

/-- For every query and statement data whose query has source rows, a run with a window mismatch
gives the error of a datatype mismatch. Proof sketch: the first branch of the output. -/
theorem Resolved.Query.outputOn_mismatch (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source)
    (mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = true) :
    query.outputOn clock counters parameters database subqueries =
      Output.error ExecutionError.datatypeMismatch.primaryCode := by
  unfold Resolved.Query.outputOn Resolved.Query.runOn
  simp [found, mismatch]

/-- For every query and statement data whose query has source rows, a run with an overflow and no
window mismatch gives the error of an integer overflow. Proof sketch: the second branch of the
output. -/
theorem Resolved.Query.outputOn_overflow (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source)
    (mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false)
    (overflow : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = true) :
    query.outputOn clock counters parameters database subqueries =
      Output.error ExecutionError.integerOverflow.primaryCode := by
  unfold Resolved.Query.outputOn Resolved.Query.runOn
  simp [found, mismatch, overflow]

/-- For every query and statement data whose query has source rows, a run with a failing function
and neither a window mismatch nor an overflow gives the error of a function. Proof sketch: the third
branch of the output. -/
theorem Resolved.Query.outputOn_function (query : Resolved.Query) (clock : Int) (counters : Counters)
    (parameters : List Value) (database : Database) (subqueries : List Resolved.Query)
    (source : Resolved.SourceRows)
    (found : query.source (Resolved.statementContext clock counters parameters database subqueries) database = some source)
    (mismatch : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).mismatch = false)
    (overflow : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).overflow = false)
    (fault : (query.run (Resolved.statementContext clock counters parameters database subqueries) source.rows).fault = .must) :
    query.outputOn clock counters parameters database subqueries =
      Output.error ExecutionError.functionError.primaryCode := by
  unfold Resolved.Query.outputOn Resolved.Query.runOn
  simp [found, mismatch, overflow, fault]

end Belay.Sqlite.Model
