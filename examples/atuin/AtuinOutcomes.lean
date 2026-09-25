import AtuinFacts

/-! Universal outcome obligations use the actual resulting history table. -/
namespace AtuinOutcomes
open SqliteVerifier

/-- Reading the extended table retains all old fields and exposes actual NULLs. -/
theorem changed {database result : Database} {table : Table}
    (present : database "history" = some table)
    (columns : table.columns = AtuinSchema.history.columns) (valid : table.Valid)
    (stored : result "history" = some (table.appendColumns [AtuinSchema.shell])) :
    ∀ original, Interpretation.current.observe database = some original →
      ∃ logical, NextInterpretation.next.observe result = some logical ∧
        Requirements.change original logical := by
  intro original observed
  have equal : original = ⟨table.project AtuinSchema.fields, none⟩ := by
    simpa [Interpretation.current, observeNullable, present] using observed.symm
  subst original
  refine ⟨⟨(table.appendColumns [AtuinSchema.shell]).project AtuinSchema.fields,
    some ((table.appendColumns [AtuinSchema.shell]).project ["shell"])⟩,
    by simp [NextInterpretation.next, observeNullable, stored], ?_⟩
  have width := fun row member => (valid.2.2 row member).2
  refine ⟨TableExtends.project ⟨[AtuinSchema.shell], rfl⟩ width (AtuinFacts.covers columns), ?_⟩
  exact congrArg some (Table.project_newNullable width (by rw [columns]; decide +kernel))

/-- Statistics maintenance cannot alter the old application view on rollback. -/
theorem rolledBack {database result : Database}
    (conforms : Conforms AtuinSchema.start database)
    (maintenance : RowsChange statisticsNames database result)
    (allowed : rollbackPhase phase = true) :
    Requirements.contract.applicability database
      (.failure (if phase = .preflight ∨ phase = .beginTransaction then 0 else 1)
        (.runnerFailure phase false) result) ∧
    OutcomeSatisfies Generated.nextSchema Requirements.contract Interpretation.current
      NextInterpretation.next NextInterpretation.failures database
      (.failure (if phase = .preflight ∨ phase = .beginTransaction then 0 else 1)
        (.runnerFailure phase false) result) := by
  refine ⟨by simp [Requirements.contract, Requirements.permitted, allowed], ?_⟩
  intro original observed
  refine ⟨maintenance.conforms conforms, original, ?_, rfl⟩
  have unchanged := maintenance.other "history" (by decide +kernel)
  simpa [NextInterpretation.failures, Requirements.committed, Interpretation.current,
    observeNullable, unchanged] using observed

/-- Every committed completion shares one complete-schema and logical postcondition. -/
theorem committed {database result : Database} {table : Table}
    (present : database "history" = some table)
    (columns : table.columns = AtuinSchema.history.columns) (valid : table.Valid)
    (stored : result "history" = some (table.appendColumns [AtuinSchema.shell]))
    (conforms : Conforms AtuinSchema.next result) (completion : CommittedResult) :
    Requirements.contract.applicability database (completion.outcome 1 result) ∧
    OutcomeSatisfies Generated.nextSchema Requirements.contract Interpretation.current
      NextInterpretation.next NextInterpretation.failures database (completion.outcome 1 result) := by
  have invariant : NextInterpretation.next.invariant result := conforms
  have change := changed present columns valid stored
  cases completion <;> refine ⟨by simp [CommittedResult.outcome, Requirements.contract,
    Requirements.permitted], ?_⟩
  all_goals intro original observed
  case success => exact ⟨invariant, rfl, change original observed⟩
  all_goals exact ⟨invariant, change original observed⟩

/-- No modeled runner outcome loses history, constraints, indexes or the required new NULLs. -/
theorem all {database : Database} (admitted : Admitted AtuinSchema.start Interpretation.admitted database)
    (execution : ProfileExecutes (.sqlite346Sqlx AtuinCatalog.config)
      AtuinSchema.payload database outcome) :
    Requirements.contract.applicability database outcome ∧
    OutcomeSatisfies Generated.nextSchema Requirements.contract Interpretation.current
      NextInterpretation.next NextInterpretation.failures database outcome := by
  obtain ⟨table, present, columns, valid, payload, conforming⟩ := AtuinFacts.payload admitted.1
  cases execution with
  | rollback allowed maintenance => exact rolledBack admitted.1 maintenance allowed
  | payloadFailure failed _ => rw [payload] at failed; cases failed
  | committed succeeded metadataPresent inserted maintenance =>
    rw [payload] at succeeded
    cases succeeded
    have resultConforms := maintenance.conforms (conforming.replaceRows metadataPresent
      inserted.columns inserted.properties inserted.valid)
    have stored := maintenance.other "history" (by decide +kernel)
    exact committed present columns valid (by simpa [Database.set] using stored) resultConforms _

end AtuinOutcomes
