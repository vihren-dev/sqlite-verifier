import SqliteVerifier.RunnerFootprint
import SqliteVerifier.Preservation

/-! Stage-aware SQLx outcomes include rollback, metadata insertion, committed
errors and statistics maintenance. Error branches conservatively include reported
runner failures; crash/corruption recovery is outside the fixed execution profile. -/

namespace SqliteVerifier

/-- Post-commit observations retain the timing sentinel when its UPDATE failed. -/
inductive CommittedResult where
  | success (elapsed : Int)
  | timingFailure
  | cacheFailure (elapsed : Int)
  | commitFailure

/-- SQLx inserts -1 before COMMIT and changes only this new row afterward.
Completed durations use its as_nanos() as i64 cast, so overflow may be negative. -/
def CommittedResult.elapsed : CommittedResult → Int
  | .success elapsed | .cacheFailure elapsed => elapsed
  | .timingFailure | .commitFailure => -1

/-- A reported failure can describe committed storage; the bit is explicit in Q. -/
def CommittedResult.outcome (completion : CommittedResult) (position : Nat)
    (database : Database) : Outcome :=
  match completion with
  | .success _ => .success database
  | .timingFailure => .failure position (.runnerFailure .timingUpdate true) database
  | .cacheFailure _ => .failure position (.runnerFailure .cacheClear true) database
  | .commitFailure => .failure position (.runnerFailure .commit true) database

/-- Stages before a successful commit can leave the original storage after rollback. -/
def rollbackPhase (phase : RunnerPhase) : Bool :=
  [.preflight, .beginTransaction, .bookkeepingInsert, .commit].contains phase

/-- The relation admits every modeled stage outcome, not just the happy-path trace.
Commit errors include both possible commit observations without asserting a crash theorem. -/
inductive ProfileExecutes : ExecutionProfile → List Statement → Database → Outcome → Prop where
  | autocommit (execution : Executes 0 script database outcome) :
      ProfileExecutes .sqlite351Autocommit script database outcome
  | rollback (phaseAllowed : rollbackPhase phase = true)
      (maintenance : RowsChange statisticsNames database result) :
      ProfileExecutes (.sqlite346Sqlx config) script database
        (.failure (if phase = .preflight ∨ phase = .beginTransaction then 0 else script.length)
          (.runnerFailure phase false) result)
  | payloadFailure (execution : run script database = .failure position reason intermediate)
      (maintenance : RowsChange statisticsNames database result) :
      ProfileExecutes (.sqlite346Sqlx config) script database (.failure position reason result)
  | committed {completion : CommittedResult} (execution : run script database = .success payload)
      (present : payload "_sqlx_migrations" = some metadata)
      (inserted : MetadataInserted config.migration metadata recorded completion.elapsed)
      (maintenance : RowsChange statisticsNames (payload.set "_sqlx_migrations" recorded) result) :
      ProfileExecutes (.sqlite346Sqlx config) script database
        (completion.outcome script.length result)

/-- Explicit execution coverage survives even when applicability permits failure. -/
theorem ProfileExecutes.total (profile : ExecutionProfile) (script : List Statement)
    (conforms : Conforms schema database) : ∃ outcome, ProfileExecutes profile script database outcome := by
  cases profile with
  | sqlite351Autocommit => exact ⟨_, .autocommit (runFrom_executes script database 0)⟩
  | sqlite346Sqlx config =>
    exact ⟨_, .rollback (phase := .preflight) (by decide +kernel) (RowsChange.refl conforms)⟩

/-- The legacy profile still has exactly its old deterministic autocommit outcomes. -/
theorem ProfileExecutes.legacy (execution : ProfileExecutes .sqlite351Autocommit script database outcome) :
    Executes 0 script database outcome := by cases execution; assumption

/-- Each completion exposes precisely the post-commit database, including errors. -/
theorem CommittedResult.database {position : Nat} {database : Database} (completion : CommittedResult) :
    (completion.outcome position database).database = database := by cases completion <;> rfl

/-- All non-bookkeeping/statistics tables retain arbitrary old physical rows and cells. -/
theorem ProfileExecutes.preservesOutside
    (execution : ProfileExecutes profile script database outcome)
    (notMetadata : name ≠ "_sqlx_migrations") (notStatistics : name ∉ statisticsNames)
    (present : database name = some table) :
    ∃ result, outcome.database name = some result ∧ TableExtends table result := by
  cases execution with
  | autocommit execution =>
    have growth := run_extends script database
    rw [show run script database = outcome from execution.result] at growth
    exact growth name table present
  | rollback _ maintenance =>
    exact ⟨table, (maintenance.other name notStatistics).trans present, TableExtends.refl table⟩
  | payloadFailure _ maintenance =>
    exact ⟨table, (maintenance.other name notStatistics).trans present, TableExtends.refl table⟩
  | committed execution _ _ maintenance =>
    have growth := run_extends script database
    rw [execution] at growth
    obtain ⟨result, stored, extended⟩ := growth name table present
    refine ⟨result, ?_, extended⟩
    rw [CommittedResult.database, maintenance.other name notStatistics]
    simpa [Database.set, notMetadata, Outcome.database] using stored

#print axioms ProfileExecutes.preservesOutside

end SqliteVerifier
