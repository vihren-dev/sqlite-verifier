import Belay.Sqlite.Model.SqlLaws
import Belay.Sqlite.Model.ScriptLaws
import Belay.Sqlite.Model.SqlExecution
import Belay.Sqlite.Model.DatabaseLaws

set_option doc.verso true

/-! SQLite model laws describe transaction rollback, statement failure and
row preservation when a column is added. -/
set_option maxHeartbeats 2000000
namespace Belay.Sqlite.Model.Conformance

/-- Each statement in the body is non-control and succeeds at its position, at the clock
value of the clock assignment for that position, with the counters of the connection that it reads
({name}`Counters.view`) and with the values bound to its parameters, as {name}`advance` runs it. The
remaining body starts from its resulting database and from the counters after the counts of the
statement ({name}`Counters.apply`). An empty body requires nothing of the database. Use this
predicate to state successful-body laws. -/
inductive SuccessfulBody (clock : Nat → Int) :
    Counters → Nat → List (Resolved.Statement × List Value) → Database → Prop where
  /-- Every counters, position and database admit an empty successful body; no statement premise is
  required. -/
  | nil : SuccessfulBody clock counters position [] database
  /-- A non-control statement that succeeds, followed by a successful tail, forms a successful body. -/
  | cons (ordinary : statement.isControl = false)
      (success : (runStatement (clock position) (counters.view statement.counterReads) parameters statement
        database).effect = .ok next)
      (tail : SuccessfulBody clock
        (counters.apply (runStatement (clock position) (counters.view statement.counterReads) parameters statement
          database).counts) (position + 1) rest next) :
      SuccessfulBody clock counters position ((statement, parameters) :: rest) database

/-- For any clock assignment, counters, position, body, current database, original snapshot and values of
the ROLLBACK, if {name}`SuccessfulBody` holds, running the body followed by ROLLBACK with that
snapshot, clock assignment and counters returns success with exactly the original database.

The proof inducts over the successful body. Each non-control step preserves
the snapshot; the final ROLLBACK restores it. -/
theorem body_rollback (success : SuccessfulBody clock counters position body database) :
    runSqlFrom position (body ++ [(.rollback, rollbackValues)])
      { database, snapshot := some original, clock, counters } = .success original := by
  induction success with
  | nil =>
    simp [runSqlFrom, advance, advanceRun, advanceWith, SqlState.statementRun, runStatement, SqlState.finish,
      SqlTransition.counted]
  | cons ordinary success tail ih =>
    rw [List.cons_append, runSqlFrom_cons, advance_effect _ _ _ _ ordinary]
    simp only [SqlState.statementRun, success, SqlState.publish, SqlTransition.counted]
    exact ih

/-- For any body, database and values of the BEGIN and the ROLLBACK, if
{name}`SuccessfulBody` holds at position 1 at the clock value 0 and unknown counters, BEGIN followed by the body and
ROLLBACK returns success with that database.

The proof unfolds BEGIN and applies {name}`body_rollback` with the initial
database as the transaction snapshot. -/
theorem rollback (success : SuccessfulBody (fun _ => 0) {} 1 body database) :
    runSql ((.begin, beginValues) :: body ++ [(.rollback, rollbackValues)]) database = .success database := by
  simpa [runSql, runSqlFrom, advance, advanceRun, advanceWith, SqlState.statementRun, runStatement, SqlTransition.counted] using body_rollback (original := database) (counters := {}) success

/-- For every state, position, effect and outcome: if {name}`SqlState.publish` of the
effect halts with the outcome, the effect is an error with some reason and reached
database, and the outcome is {name}`SqlState.failed` of that reason with the reached
database for a FAIL failure and the state's database for every other reason. -/
theorem SqlState.publish_halt {state : SqlState} {position : Nat} {effect : Effect} {outcome : Outcome}
    (halted : state.publish position effect = .halt outcome) :
    ∃ reason reached, effect = .error (reason, reached) ∧
      outcome = state.failed position reason (if reason = .constraintFail then reached else state.database) := by
  cases effect with
  | ok database => simp [SqlState.publish] at halted
  | error failure =>
    obtain ⟨reason, reached⟩ := failure
    simp only [SqlState.publish, SqlTransition.halt.injEq] at halted
    exact ⟨reason, reached, rfl, halted.symm⟩

/-- For every state, position, effect and next state: if {name}`SqlState.publish` of the
effect continues with the next state, the effect succeeds with some database, and the
next state is the state with that database. -/
theorem SqlState.publish_next {state next : SqlState} {position : Nat} {effect : Effect}
    (continued : state.publish position effect = .next next) :
    ∃ database, effect = .ok database ∧ next = { state with database } := by
  cases effect with
  | ok database =>
    simp only [SqlState.publish, SqlTransition.next.injEq] at continued
    exact ⟨database, rfl, continued.symm⟩
  | error failure => simp [SqlState.publish] at continued

/-- For any position, statement, values, state and outcome, if {name}`advance` halts with that
outcome and its error is neither a FAIL failure ({name}`ExecutionError.constraintFail`)
nor a ROLLBACK failure ({name}`ExecutionError.constraintRollback`), its visible database
equals the state's current database. Its persisted database equals the saved snapshot
when present, and otherwise the current database. For FAIL and ROLLBACK the formula
says nothing; {lit}`constraint_rollback` states ROLLBACK.

The proof splits on the statement and snapshot; an ordinary statement halts through
{name}`SqlState.publish_halt`, which keeps the state's database for these errors. -/
theorem statement_atomicity (halted : advance position statement parameters state = .halt outcome)
    (atomic : outcome.error? ≠ some .constraintFail ∧ outcome.error? ≠ some .constraintRollback) :
    outcome.database = state.database ∧
    outcome.persistedDatabase = state.snapshot.getD state.database := by
  cases statement <;> simp only [advance, advanceRun, SqlTransition.counted_eq_halt, advanceWith] at halted
  all_goals try (solve | (clear atomic; cases h : state.snapshot <;> simp_all [SqlState.finish,
    Outcome.database, Outcome.persistedDatabase, Option.getD]))
  all_goals first
    | (obtain ⟨reason, reached, _, rfl⟩ := SqlState.publish_halt halted
       have notFail : reason ≠ .constraintFail :=
         fun failed => atomic.1 (by subst failed; exact SqlState.failed_error _ _ _ _)
       have notRollback : reason ≠ .constraintRollback :=
         fun rolled => atomic.2 (by subst rolled; exact SqlState.failed_error _ _ _ _)
       simp only [notFail, ite_false]
       exact SqlState.failed_database _ _ _ _ notRollback)
    | (clear atomic; cases hs : state.snapshot <;>
       simp_all [SqlState.finish, Outcome.database, Outcome.persistedDatabase, Option.getD] <;>
       subst halted <;> simp)

/-- For any position, statement, values, state and outcome, if {name}`advance` halts with that
outcome and its error is a ROLLBACK failure ({name}`ExecutionError.constraintRollback`),
its visible and its persisted database are the saved snapshot when present, and
otherwise the current database: the transaction of the snapshot is rolled back.

The proof splits on the statement and snapshot; an ordinary statement halts through
{name}`SqlState.publish_halt`, which gives a ROLLBACK failure the state's database. -/
theorem constraint_rollback (halted : advance position statement parameters state = .halt outcome)
    (rolled : outcome.error? = some .constraintRollback) :
    outcome.database = state.snapshot.getD state.database ∧
    outcome.persistedDatabase = state.snapshot.getD state.database := by
  cases statement <;> simp only [advance, advanceRun, SqlTransition.counted_eq_halt, advanceWith] at halted
  all_goals try (solve | cases h : state.snapshot <;> simp_all [SqlState.finish,
    Outcome.database, Outcome.persistedDatabase, Option.getD, Outcome.error?])
  all_goals first
    | (obtain ⟨reason, reached, _, rfl⟩ := SqlState.publish_halt halted
       rw [SqlState.failed_error] at rolled
       cases rolled
       exact SqlState.failed_rollback _ _ _)
    | (cases hs : state.snapshot <;>
       simp_all [SqlState.finish, Outcome.database, Outcome.persistedDatabase, Option.getD, Outcome.error?] <;>
       subst halted <;> simp_all)

/-- For any position, table position, column without a time default
({name}`CatalogColumn.clockDefault`), values and states, if ADD COLUMN with the values advances to the next state,
some table exists at that table position in the original state.
The next database contains that table with the column appended. This table has
the same row count and rowids, and each original row gains the affinity-applied
value returned by {name}`readDefaultValue`.

The proof follows the successful ADD branch and unfolds column extension
and its row mapping. -/
theorem add_column_shape (constant : column.clockDefault = false)
    (success : advance position (.addColumn target column) parameters state = .next next) :
    ∃ table value, state.database.table target = some table ∧
      readDefaultValue column = .ok value ∧
      next.database.table target = some (table.appendColumns [(column, value)]) ∧
      (table.appendColumns [(column, value)]).rows.length = table.rows.length ∧
      (table.appendColumns [(column, value)]).rows.map Row.rowid = table.rows.map Row.rowid ∧
      (table.appendColumns [(column, value)]).rows.map Row.values =
        table.rows.map (fun row => row.values ++ [Value.store column.affinity value]) := by
  rw [advance_addColumn] at success
  simp only [SqlState.statementRun, runStatement, step, SqlState.publish] at success
  repeat (split at * <;> simp_all)
  all_goals subst_vars
  all_goals simp_all [Database.table_addColumn, Table.appendColumns, Row.appendValues, List.map_map]

#print axioms rollback
#print axioms statement_atomicity
#print axioms constraint_rollback
#print axioms add_column_shape
end Belay.Sqlite.Model.Conformance
