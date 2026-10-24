import Belay.Sqlite.Model.Laws
import Belay.Sqlite.Model.Resolution.ResolveStateSpec

set_option doc.verso true

/-! One SQL step and the resolution state: a step that continues keeps the connection
state in agreement with {lit}`ResolveState.after`, and a halt has an error.
{lit}`CatalogAgreement` folds these over a script. -/

namespace Belay.Sqlite.Model

/-- A connection state agrees with a resolution state when the visible database has the
current catalog of the resolution, and an open transaction's snapshot has the saved
catalog: both are absent, or both are present with equal catalogs. -/
def SqlState.Agrees (sql : SqlState) (state : ResolveState) : Prop :=
  sql.database.catalog = state.catalog ∧ sql.snapshot.map (·.catalog) = state.saved

/-- For every clock value, counters, list of values, statement that is not a setting pragma
({lit}`PRAGMA setting = value`), database and result: if {name}`literalStep` with the values succeeds with the result, then the result's catalog is
{name}`Resolved.Statement.applyCatalog` of the statement on the database's catalog, and the
statement is not transaction control. Proof sketch: CREATE TABLE, CREATE INDEX, CREATE TRIGGER, ADD
COLUMN and DROP call the catalog functions, writes store rows only ({name}`Database.setRows`, and the rows
of a write that checks foreign keys over the input catalog, {name}`keyRun_ok_catalog`), a query
returns the database, and every other statement fails. -/
theorem literalStep_success_catalog {clock : Int} {counters : Counters} {parameters : List Value} {statement : Resolved.Statement}
    {database result : Database} (notSetting : ∀ setting on, statement ≠ .setting setting on)
    (success : literalStep clock counters parameters statement database = .ok result) :
    result.catalog = statement.applyCatalog database.catalog ∧ statement.isControl = false := by
  cases statement with
  | setting setting on => exact absurd rfl (notSetting setting on)
  | createTable target name table =>
    simp only [literalStep, runStatement, step] at success
    split at success
    · cases success; exact ⟨rfl, rfl⟩
    · cases success
  | addColumn target column =>
    simp only [literalStep, runStatement, step] at success
    split at success
    · cases success
    · repeat' split at success
      all_goals first | (cases success; exact ⟨rfl, rfl⟩) | cases success
  | insert target rows returning subqueries foreignKeys =>
    cases foreignKeys with
    | none =>
      simp only [literalStep, runStatement, insertOutcome, checkedWrite, StatementRun.withKeys, Option.map] at success
      repeat' split at success
      all_goals first | (cases success; exact ⟨rfl, rfl⟩) | cases success
    | some depth =>
      simp only [literalStep, runStatement] at success
      split at success
      · cases success
      · simp only [StatementRun.withKeys, Option.map, insertKeys] at success
        exact ⟨keyRun_ok_catalog success, rfl⟩
  | upsert target rows clauses returning algorithm subqueries foreignKeys =>
    cases foreignKeys with
    | none =>
      simp only [literalStep, runStatement, StatementRun.withKeys, Option.map] at success
      repeat' split at success
      all_goals first | (cases success; exact ⟨rfl, rfl⟩) | cases success
    | some depth =>
      simp only [literalStep, runStatement] at success
      split at success
      · cases success
      · simp only [StatementRun.withKeys, Option.map, insertKeys] at success
        exact ⟨keyRun_ok_catalog success, rfl⟩
  | update target assignments filter returning subqueries foreignKeys =>
    cases foreignKeys with
    | none =>
      simp only [literalStep, runStatement, checkedWrite, StatementRun.withKeys, Option.map] at success
      repeat' split at success
      all_goals first | (cases success; exact ⟨rfl, rfl⟩) | cases success
    | some depth =>
      simp only [literalStep, runStatement] at success
      split at success
      · cases success
      · simp only [StatementRun.withKeys, Option.map, updateKeys, rowsKeys] at success
        exact ⟨keyRun_ok_catalog success, rfl⟩
  | delete target filter returning subqueries foreignKeys =>
    cases foreignKeys with
    | none =>
      simp only [literalStep, runStatement, StatementRun.withKeys, Option.map] at success
      split at success
      · cases success
      · cases success; exact ⟨rfl, rfl⟩
    | some depth =>
      simp only [literalStep, runStatement] at success
      split at success
      · cases success
      · simp only [StatementRun.withKeys, Option.map, deleteKeys, rowsKeys] at success
        exact ⟨keyRun_ok_catalog success, rfl⟩
  | query query subqueries =>
    simp only [literalStep, runStatement] at success
    cases ran : query.runOn clock counters parameters database subqueries with
    | none => simp only [ran, queryEffect] at success; cases success; exact ⟨rfl, rfl⟩
    | some pair =>
      obtain ⟨_, run⟩ := pair
      simp only [ran, queryEffect] at success
      repeat' split at success
      all_goals first | (cases success; exact ⟨rfl, rfl⟩) | cases success
  | createIndex target name index | createTrigger target name index =>
    simp only [literalStep, runStatement, step] at success
    repeat' split at success
    all_goals first | (cases success; exact ⟨rfl, rfl⟩) | cases success
  | drop positions foreignKeys =>
    cases foreignKeys with
    | none =>
      simp only [literalStep, runStatement, step, StatementRun.withKeys, Option.map] at success
      cases success; exact ⟨rfl, rfl⟩
    | some depth =>
      simp only [literalStep, runStatement, StatementRun.withKeys, Option.map] at success
      exact ⟨dropKeys_ok_catalog success, rfl⟩
  | begin | commit | rollback | prepareError =>
    simp [literalStep, runStatement, step] at success

/-- For every position, statement, list of values, connection states and resolution state: if
the connection state agrees with the resolution state ({name}`SqlState.Agrees`) and
{name}`advance` of the statement with the values continues, then the next connection state agrees with
{name}`ResolveState.after` of the statement. Proof sketch: BEGIN saves the database whose
catalog the resolution saves, COMMIT drops both, ROLLBACK restores the snapshot whose
catalog the resolution restores, a setting pragma keeps the database, and
every other statement follows {name}`literalStep_success_catalog`. -/
theorem advance_agrees {position : Nat} {statement : Resolved.Statement} {parameters : List Value}
    {sql next : SqlState} {state : ResolveState}
    (agrees : sql.Agrees state) (continued : advance position statement parameters sql = .next next) :
    next.Agrees (state.after statement) := by
  obtain ⟨catalog, saved⟩ := agrees
  obtain ⟨transitioned, reached, rfl⟩ := advance_eq_next continued
  clear continued
  cases statement with
  | begin =>
    simp only [advanceWith] at reached
    split at reached
    · cases reached
    · rename_i none_
      cases reached
      rw [none_] at saved
      simp only [Option.map_none] at saved
      simp [SqlState.Agrees, ResolveState.after, ← saved, catalog]
  | commit =>
    simp only [advanceWith] at reached
    split at reached
    · cases reached
    · cases reached
      exact ⟨catalog, rfl⟩
  | rollback =>
    simp only [advanceWith] at reached
    split at reached
    · cases reached
    · rename_i original some_
      cases reached
      rw [some_] at saved
      simp only [Option.map_some] at saved
      simp [SqlState.Agrees, ResolveState.after, ← saved]
  | setting setting on =>
    simp only [advanceWith] at reached
    obtain ⟨result, stepped, rfl⟩ := Conformance.SqlState.publish_next reached
    simp only [SqlState.statementRun, runStatement, step] at stepped
    cases stepped
    cases setting <;> exact ⟨catalog, saved⟩
  | createTable | createIndex | createTrigger | addColumn | drop | insert | update | upsert | delete | prepareError
  | query =>
    simp only [advanceWith] at reached
    obtain ⟨result, stepped, rfl⟩ := Conformance.SqlState.publish_next reached
    obtain ⟨changed, control⟩ := literalStep_success_catalog (fun _ _ => by simp) stepped
    rw [state.after_of_isControl control]
    exact ⟨changed.trans (catalog ▸ rfl), saved⟩

/-- For every position, statement, list of values, connection state and outcome: if
{name}`advance` of the statement with the values halts with the outcome, the outcome has an error ({name}`Outcome.error?`). A halt is never a
success and never a pending transaction without an error. Proof sketch: split on the
statement: BEGIN in a transaction finishes a failure, which keeps its error with or
without a snapshot; COMMIT and ROLLBACK without a transaction fail; every other statement
halts only on an error of {lit}`literalStep` ({lit}`SqlState.publish_halt`), whose error
{name}`SqlState.failed_error` keeps. -/
theorem advance_halt_error {position : Nat} {statement : Resolved.Statement} {parameters : List Value} {sql : SqlState}
    {outcome : Outcome} (halted : advance position statement parameters sql = .halt outcome) : outcome.error?.isSome := by
  have finished : ∀ index reason database,
      (sql.finish (.failure index reason database)).error?.isSome := by
    intro index reason database
    cases h : sql.snapshot <;> simp [SqlState.finish, Outcome.error?, h]
  cases statement with
  | begin =>
    simp only [advance, advanceRun, SqlTransition.counted_eq_halt, advanceWith] at halted
    split at halted
    · cases halted; exact finished _ _ _
    · cases halted
  | commit | rollback =>
    simp only [advance, advanceRun, SqlTransition.counted_eq_halt, advanceWith] at halted
    split at halted
    · cases halted; simp [Outcome.error?]
    · cases halted
  | createTable | createIndex | createTrigger | addColumn | drop | insert | update | upsert | delete | prepareError
  | query | setting =>
    simp only [advance, advanceRun, SqlTransition.counted_eq_halt, advanceWith] at halted
    obtain ⟨_, _, _, rfl⟩ := Conformance.SqlState.publish_halt halted
    simp [SqlState.failed_error]

end Belay.Sqlite.Model
