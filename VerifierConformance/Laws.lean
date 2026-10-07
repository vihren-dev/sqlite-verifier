import SqliteVerifier.SqlExecution

/-! ADR 0004 W5 laws use the same transitions as the verifier. -/
set_option maxHeartbeats 2000000
namespace SqliteVerifier.Conformance

/-- A body excludes transaction control so its successful steps preserve the snapshot. -/
def nonControl : Statement → Bool
  | .beginTransaction | .commit | .rollback => false
  | _ => true

/-- Every body statement succeeds, retaining its actual intermediate database. -/
inductive SuccessfulBody : Nat → List Statement → Database → Prop where
  | nil : SuccessfulBody position [] database
  | cons (ordinary : nonControl statement = true)
      (success : literalStep statement database position = .success next)
      (tail : SuccessfulBody (position + 1) rest next) :
      SuccessfulBody position (statement :: rest) database

/-- Successful ordinary bodies cannot change a transaction's original snapshot. -/
theorem body_rollback (success : SuccessfulBody position body database) :
    runSqlFrom position (body ++ [.rollback]) ⟨database, some original⟩ = .success original := by
  induction success with
  | nil => simp [runSqlFrom, advance, SqlState.finish]
  | @cons statement database position next rest ordinary success tail ih =>
    cases statement <;> simp_all [nonControl, runSqlFrom, advance]

/-- A successful transaction-free body followed by ROLLBACK restores the initial database. -/
theorem rollback (success : SuccessfulBody 1 body database) :
    runSql (.beginTransaction :: body ++ [.rollback]) database = .success database := by
  simpa [runSql, runSqlFrom, advance] using body_rollback (original := database) success

/-- Literal execution either succeeds or fails with its input database intact. -/
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

/-- Every halted statement leaves both the visible and committed databases unchanged. -/
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

/-- A successful ADD's exact table transformation preserves rows and appends one NULL. -/
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
end SqliteVerifier.Conformance
