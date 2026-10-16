import Belay.Sqlite.SqlProofs
import Belay.Sqlite.SqlExecution

set_option doc.verso true

/-! SQLite model laws describe transaction rollback, statement failure and
row preservation when a column is added. -/
set_option maxHeartbeats 2000000
namespace Belay.Sqlite.Conformance

/-- Classify statements that leave transaction control to their surrounding script. -/
def nonControl : Resolved.Statement → Bool
  | .begin | .commit | .rollback => false
  | .createTable .. | .createIndex .. | .addColumn .. | .insert .. | .upsert .. | .update .. | .delete ..
  | .prepareError _ | .query _ => true

/-- Each statement in the body is non-control and succeeds at its position.
The remaining body starts from its resulting database. An empty body requires
nothing of the database. Use this predicate to state successful-body laws. -/
inductive SuccessfulBody : Nat → List Resolved.Statement → Database → Prop where
  /-- Every position and database admit an empty successful body; no statement premise is required. -/
  | nil : SuccessfulBody position [] database
  /-- A non-control statement that succeeds, followed by a successful tail, forms a successful body. -/
  | cons (ordinary : nonControl statement = true)
      (success : literalStep statement database position = .success next)
      (tail : SuccessfulBody (position + 1) rest next) :
      SuccessfulBody position (statement :: rest) database

/-- For any position, body, current database and original snapshot, if
{name}`SuccessfulBody` holds, running the body followed by ROLLBACK with that
snapshot returns success with exactly the original database.

The proof inducts over the successful body. Each non-control step preserves
the snapshot; the final ROLLBACK restores it. -/
theorem body_rollback (success : SuccessfulBody position body database) :
    runSqlFrom position (body ++ [.rollback]) ⟨database, some original⟩ = .success original := by
  induction success with
  | nil => simp [runSqlFrom, advance, SqlState.finish]
  | @cons statement database position next rest ordinary success tail ih =>
    cases statement <;> simp_all [nonControl, runSqlFrom, advance]

/-- For any body and database, if {name}`SuccessfulBody` holds at position 1,
BEGIN followed by the body and ROLLBACK returns success with that database.

The proof unfolds BEGIN and applies {name}`body_rollback` with the initial
database as the transaction snapshot. -/
theorem rollback (success : SuccessfulBody 1 body database) :
    runSql (.begin :: body ++ [.rollback]) database = .success database := by
  simpa [runSql, runSqlFrom, advance] using body_rollback (original := database) success

/-- For every statement, database and position, {name}`literalStep` returns one of:
* success with some database;
* a failure at that position with some reason and the unchanged input database;
* a FAIL failure ({name}`ExecutionError.constraintFail`) at that position with some
  database, which keeps the earlier rows of an INSERT.

The proof splits on the statement and table lookup, then follows each validation
branch. Each failure branch other than FAIL retains the input database. -/
theorem literal_cases (statement : Resolved.Statement) (database : Database) (position : Nat) :
    (∃ result, literalStep statement database position = .success result) ∨
    (∃ reason, literalStep statement database position = .failure position reason database) ∨
    (∃ after, literalStep statement database position = .failure position .constraintFail after) := by
  cases statement with
  | createTable at_ name table =>
    cases h : database at_ <;> simp [literalStep, step, h]
  | addColumn at_ column =>
    cases h : database at_ <;> simp [literalStep, step, h]
  | insert at_ rows keys _ =>
    cases h : database at_ <;> simp only [literalStep, insertOutcome, checkedWrite, h]
    all_goals (repeat' split) <;> simp
  | upsert at_ rows clauses keys _ policy =>
    cases h : database at_ <;> simp only [literalStep, h]
    all_goals (repeat' split) <;> try simp
    rename_i reason _ _ _
    cases reason <;> simp [LiteralData.failedDatabase]
  | update at_ assignments filter keys _ =>
    cases h : database at_ <;> simp only [literalStep, checkedWrite, h]
    all_goals (repeat' split) <;> simp
  | delete at_ filter _ =>
    cases h : database at_ <;> simp [literalStep, h]
  | createIndex _ _ _ => simp [literalStep, step]
  | query query =>
    simp only [literalStep, step]
    cases query.source database with
    | none => simp
    | some rows => cases h : query.fails rows <;> simp [h]
  | prepareError _ => simp [literalStep, step]
  | begin => simp [literalStep, step]
  | commit => simp [literalStep, step]
  | rollback => simp [literalStep, step]

/-- For any position, statement, state and outcome, if {name}`advance` halts with that
outcome and its error is neither a FAIL failure ({name}`ExecutionError.constraintFail`)
nor a ROLLBACK failure ({name}`ExecutionError.constraintRollback`), its visible database
equals the state's current database. Its persisted database equals the saved snapshot
when present, and otherwise the current database. For FAIL and ROLLBACK the formula
says nothing; {lit}`constraint_rollback` states ROLLBACK.

The proof splits on the statement and snapshot. {name}`literal_cases` supplies
the success and failure alternatives for ordinary statements. -/
theorem statement_atomicity (halted : advance position statement state = .halt outcome)
    (atomic : outcome.error? ≠ some .constraintFail ∧ outcome.error? ≠ some .constraintRollback) :
    outcome.database = state.database ∧
    outcome.persistedDatabase = state.snapshot.getD state.database := by
  have possibilities := literal_cases statement state.database position
  cases statement <;> simp only [advance] at halted
  all_goals try (solve | (clear atomic; cases h : state.snapshot <;> simp_all [SqlState.finish,
    Outcome.database, Outcome.persistedDatabase, Option.getD]))
  all_goals try (rcases possibilities with ⟨result, h⟩ | ⟨reason, h⟩ | ⟨after, h⟩ <;> rw [h] at halted <;>
    simp only [reduceCtorEq, SqlTransition.halt.injEq] at halted <;> subst halted)
  all_goals first
    | exact absurd (SqlState.failed_error _ _ _ _) atomic.1
    | (rename_i reason
       by_cases rolled : reason = .constraintRollback
       · subst rolled; exact absurd (SqlState.failed_error _ _ _ _) atomic.2
       · exact SqlState.failed_database _ _ _ _ rolled)
    | (clear atomic possibilities; cases hs : state.snapshot <;>
       simp_all [SqlState.finish, Outcome.database, Outcome.persistedDatabase, Option.getD] <;>
       subst halted <;> simp)

/-- For any position, statement, state and outcome, if {name}`advance` halts with that
outcome and its error is a ROLLBACK failure ({name}`ExecutionError.constraintRollback`),
its visible and its persisted database are the saved snapshot when present, and
otherwise the current database: the transaction of the snapshot is rolled back.

The proof splits on the statement and snapshot. Only an INSERT fails with ROLLBACK, and
by {name}`literal_cases` its failure keeps the input database. -/
theorem constraint_rollback (halted : advance position statement state = .halt outcome)
    (rolled : outcome.error? = some .constraintRollback) :
    outcome.database = state.snapshot.getD state.database ∧
    outcome.persistedDatabase = state.snapshot.getD state.database := by
  have possibilities := literal_cases statement state.database position
  cases statement <;> simp only [advance] at halted
  all_goals try (solve | cases h : state.snapshot <;> simp_all [SqlState.finish,
    Outcome.database, Outcome.persistedDatabase, Option.getD, Outcome.error?])
  all_goals try (rcases possibilities with ⟨result, h⟩ | ⟨reason, h⟩ | ⟨after, h⟩ <;> rw [h] at halted <;>
    simp only [reduceCtorEq, SqlTransition.halt.injEq] at halted <;> subst halted)
  all_goals first
    | (rw [SqlState.failed_error] at rolled; simp only [Option.some.injEq, reduceCtorEq] at rolled; done)
    | (rw [SqlState.failed_error] at rolled; cases rolled; exact SqlState.failed_rollback _ _ _)
    | (clear possibilities; cases hs : state.snapshot <;>
       simp_all [SqlState.finish, Outcome.database, Outcome.persistedDatabase, Option.getD, Outcome.error?] <;>
       subst halted <;> simp_all)

/-- For any position, table position, column and states, if ADD COLUMN advances
to the next state, some table exists at that table position in the original state.
The next database contains that table with the column appended. This table has
the same row count and rowids, and each original row gains one NULL value.

The proof follows the successful ADD branch and unfolds column extension
and its row mapping. -/
theorem add_column_shape
    (success : advance position (.addColumn at_ column) state = .next next) :
    ∃ table, state.database at_ = some table ∧
      next.database at_ = some (table.appendColumns [column]) ∧
      (table.appendColumns [column]).rows.length = table.rows.length ∧
      (table.appendColumns [column]).rows.map Row.rowid = table.rows.map Row.rowid ∧
      (table.appendColumns [column]).rows.map Row.values =
        table.rows.map (fun row => row.values ++ [.null]) := by
  simp only [advance, literalStep, step] at success
  repeat (split at * <;> simp_all)
  all_goals subst_vars
  all_goals simp_all [Database.set, Table.appendColumns, Row.appendNulls, List.map_map]

#print axioms rollback
#print axioms statement_atomicity
#print axioms constraint_rollback
#print axioms add_column_shape
end Belay.Sqlite.Conformance
