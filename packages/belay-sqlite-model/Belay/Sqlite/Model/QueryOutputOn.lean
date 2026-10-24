import Belay.Sqlite.Model.QueryStepOutput

set_option doc.verso true

/-! The output of a query statement in the terms of its query (ADR 0017, S4): the error that its
run gives, or the output of the results that SQLite may give for it. A query statement that the
model describes gives {lit}`Resolved.Query.outputOn`, and one that it does not describe gives
{name}`Belay.Sqlite.Model.Output.unmodeled`. -/

namespace Belay.Sqlite.Model

/-- For every state, position, error and database, a statement that fails with the error halts with
that error ({name}`haltError`), also in an open transaction and for a rollback failure. Proof
sketch: unfold the failure of the state and take the cases of its snapshot. -/
theorem haltError_failed (state : SqlState) (position : Nat) (reason : ExecutionError) (database : Database) :
    haltError (.halt (state.failed position reason database)) = some reason := by
  unfold SqlState.failed SqlState.finish
  split
  · cases h : state.snapshot <;> simp [haltError]
  · cases h : state.snapshot <;> simp [haltError]

/-- The output of a query that the model describes, at a clock value with the counters that it
reads and the values bound to its parameters, over the database and the subqueries of its
statement: the error of a window value that is not an integer
({name}`Resolved.QueryRun.mismatch`), of an integer overflow ({name}`Resolved.QueryRun.overflow`) or
of a failing function ({name}`Resolved.Fault.must`), in this order; otherwise
{name}`Output.ofResults` of the results that SQLite may give
({name}`Resolved.Query.possibleOn`). It is {name}`Output.unmodeled` when the model has no source
rows for the query. -/
def Resolved.Query.outputOn (query : Resolved.Query) (clock : Int) (counters : Counters) (parameters : List Value)
    (database : Database) (subqueries : List Resolved.Query) : Belay.Sqlite.Model.Output :=
  match query.runOn clock counters parameters database subqueries with
  | none => Belay.Sqlite.Model.Output.unmodeled "the model gives no result for this query"
  | some (_, run) =>
    if run.mismatch then Belay.Sqlite.Model.Output.error ExecutionError.datatypeMismatch.primaryCode
    else if run.overflow then Belay.Sqlite.Model.Output.error ExecutionError.integerOverflow.primaryCode
    else if run.fault == .must then Belay.Sqlite.Model.Output.error ExecutionError.functionError.primaryCode
    else match query.possibleOn clock counters parameters database subqueries with
      | some results => Belay.Sqlite.Model.Output.ofResults results
      | none => Belay.Sqlite.Model.Output.unmodeled "the model gives no result for this query"

/-- For every query, subqueries, clock value, index, values and state, and every run of the statement
whose effect is that of the query ({name}`queryEffect`), the output of the statement from its run and
its transition ({name}`Output.ofStep`) is the output of the query ({name}`Resolved.Query.outputOn`)
with the counters that the statement reads. Proof sketch: a query changes nothing, so its
transition continues, or halts with the error of its effect ({name}`haltError_failed`); the cases of
the effect are the cases of the output. -/
theorem Output.ofStep_query (query : Resolved.Query) (subqueries : List Resolved.Query) (clock : Int) (index : Nat)
    (parameters : List Value) (state : SqlState) (run : StatementRun)
    (effect : run.effect = queryEffect state.database
      (query.runOn clock (state.counters.view (Resolved.Statement.query query subqueries).counterReads) parameters
        state.database subqueries)) :
    Output.ofStep clock parameters (.query query subqueries) state run
      (advanceRun index (.query query subqueries) state run) =
    query.outputOn clock (state.counters.view (Resolved.Statement.query query subqueries).counterReads) parameters
      state.database subqueries := by
  unfold Output.ofStep advanceRun advanceWith
  simp only [possibleOutput, effect]
  generalize state.counters.view (Resolved.Statement.query query subqueries).counterReads = counters
  unfold Resolved.Query.outputOn
  cases ran : query.runOn clock counters parameters state.database subqueries with
  | none =>
    have possible : query.possibleOn clock counters parameters state.database subqueries = none := by
      simp [Resolved.Query.possibleOn, Resolved.Query.runOn] at ran ⊢
      simp [ran]
    simp [queryEffect, SqlState.publish, SqlTransition.counted, haltError, possible]
  | some pair =>
    obtain ⟨source, run⟩ := pair
    by_cases mismatch : run.mismatch = true
    · simp [queryEffect, SqlState.publish, SqlTransition.counted, mismatch, haltError_failed]
    by_cases overflow : run.overflow = true
    · simp [queryEffect, SqlState.publish, SqlTransition.counted, mismatch, overflow, haltError_failed]
    by_cases must : (run.fault == Resolved.Fault.must) = true
    · simp [queryEffect, SqlState.publish, SqlTransition.counted, mismatch, overflow, must, haltError_failed]
    simp [queryEffect, SqlState.publish, SqlTransition.counted, mismatch, overflow, must, haltError]
    rfl

end Belay.Sqlite.Model
