import Belay.Sqlite.SqlExecution

set_option doc.verso true

/-! SQLite model laws describe transaction rollback, statement failure and
row preservation when a column is added. -/
set_option maxHeartbeats 2000000
namespace Belay.Sqlite.Conformance

/-- Classify statements that leave transaction control to their surrounding script. -/
def nonControl : Statement → Bool
  | .beginTransaction | .commit | .rollback => false
  | .createTable .. | .addColumn .. | .insert .. | .update .. => true

/-- Each statement in the body is non-control and succeeds at its position.
The remaining body starts from its resulting database. An empty body requires
nothing of the database. Use this predicate to state successful-body laws. -/
inductive SuccessfulBody : Nat → List Statement → Database → Prop where
  | nil : SuccessfulBody position [] database
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
    runSql (.beginTransaction :: body ++ [.rollback]) database = .success database := by
  simpa [runSql, runSqlFrom, advance] using body_rollback (original := database) success

/-- For every statement, database and position, {name}`literalStep` either
returns success with some database or returns a failure at that position with
some reason and the unchanged input database.

The proof splits on the statement and table lookup, then follows each
validation branch. Each failure branch retains the input database. -/
theorem literal_cases (statement : Statement) (database : Database) (position : Nat) :
    (∃ result, literalStep statement database position = .success result) ∨
    (∃ reason, literalStep statement database position = .failure position reason database) := by
  cases statement with
  | createTable name columns =>
    cases h : database name <;> simp only [literalStep, step, h]
    all_goals split <;> simp_all
  | addColumn name column =>
    cases h : database name <;> simp only [literalStep, step, h]
    all_goals repeat (split <;> simp_all)
    all_goals simp_all
  | insert name columns values =>
    cases h : database name <;> simp only [literalStep, h]
    all_goals try (split <;> simp_all)
    all_goals simp
  | update name column value key equals =>
    cases h : database name <;> simp only [literalStep, h]
    all_goals try (split <;> simp_all)
    all_goals simp
  | beginTransaction | commit | rollback => simp [literalStep, step]

/-- For any position, statement, state and outcome, if {name}`advance` halts
with that outcome, its visible database equals the state's current database.
Its persisted database equals the saved snapshot when present, and otherwise
the current database.

The proof splits on the statement and snapshot. {name}`literal_cases` supplies
the success and failure alternatives for ordinary statements. -/
theorem statement_atomicity (halted : advance position statement state = .halt outcome) :
    outcome.database = state.database ∧
    outcome.persistedDatabase = state.snapshot.getD state.database := by
  have possibilities := literal_cases statement state.database position
  cases statement <;> simp only [advance] at halted
  all_goals try (solve | cases h : state.snapshot <;> simp_all [SqlState.finish,
    Outcome.database, Outcome.persistedDatabase, Option.getD])
  all_goals rcases possibilities with ⟨result, h⟩ | ⟨reason, h⟩
  all_goals try simp only [h] at halted
  all_goals try contradiction
  all_goals cases hs : state.snapshot <;>
    simp_all [SqlState.finish, Outcome.database, Outcome.persistedDatabase, Option.getD]

  all_goals rw [← halted]
  all_goals exact ⟨rfl, rfl⟩

/-- For any position, table name, column and states, if ADD COLUMN advances
to the next state, some table exists at that name in the original state. The
next database contains that table with the column appended. This table has
the same row count and rowids, and each original row gains one NULL value.

The proof follows the successful ADD branch and unfolds column extension
and its row mapping. -/
theorem add_column_shape
    (success : advance position (.addColumn name column) state = .next next) :
    ∃ table, state.database name = some table ∧
      next.database name = some (table.appendColumns [column]) ∧
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
#print axioms add_column_shape
end Belay.Sqlite.Conformance
