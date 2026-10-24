import Belay.Sqlite.Model.QueryStepOutput

set_option doc.verso true

/-! The output of a statement that SQLite refuses to prepare (ADR 0017, S4): a statement that
resolution turns into a prepare error, such as a query of a table that does not exist, gives the
output {name}`Belay.Sqlite.Model.Output.error` with the code of the prepare error, at any index, on any
connection and with any values. -/

namespace Belay.Sqlite.Model

/-- For every state, position, prepare error and database, the failure of a prepare error halts
with that error: the error is no rollback failure, and an open transaction keeps the error as
the pending one. Proof sketch: unfold {name}`SqlState.failed` and {name}`SqlState.finish`, and
split on the snapshot. -/
theorem SqlState.haltError_failed_prepare (state : SqlState) (position : Nat) (error : PrepareError) (database : Database) :
    haltError (.halt (state.failed position (.prepare error) database)) = some (.prepare error) := by
  unfold SqlState.failed SqlState.finish
  cases state.snapshot <;> simp [haltError]

/-- For every index, connection, values and prepare error, the output of the step of the
statement that SQLite refuses to prepare is the error output with the code of the prepare error.
Proof sketch: the statement reads no clock and no counter and is ready, so the output is
{name}`Output.ofStep`, which maps the halt with the prepare error
({name}`SqlState.haltError_failed_prepare`) to that output. -/
theorem resolvedStepOutput_prepareError (index : Nat) (connection : Connection) (parameters : List Value)
    (error : PrepareError) :
    resolvedStepOutput none index connection parameters (.prepareError error) =
      .error (ExecutionError.prepare error).primaryCode := by
  have halted : haltError (advanceRun index (.prepareError error) connection.state
      (connection.state.statementRun 0 parameters (.prepareError error))) = some (.prepare error) := by
    simp [advanceRun, advanceWith, SqlState.statementRun, runStatement, SqlState.publish, SqlTransition.counted, step]
    exact SqlState.haltError_failed_prepare _ _ _ _
  have clock : statementClock none index (.prepareError error) = some 0 := by
    simp [statementClock, Resolved.Statement.readsClock, Resolved.Statement.clockExpressions]
  have known : connection.state.counters.firstUnknown (Resolved.Statement.prepareError error).counterReads = none := by
    simp [Resolved.Statement.counterReads, Resolved.Statement.clockExpressions]
  have ready : (connection.state.statementRun 0 parameters (.prepareError error)).ready = true := by
    simp [SqlState.statementRun, runStatement, known]
  unfold resolvedStepOutput
  rw [clock]
  simp only [known, ready]
  simp [Output.ofStep, halted]

end Belay.Sqlite.Model
