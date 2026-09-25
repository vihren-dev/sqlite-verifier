import AtuinSchema

/-! Proposed owner-reviewable guarantees for the selected real migration.
This draft is mathematically checkable; human acceptance is recorded separately. -/
namespace Requirements
open SqliteVerifier

/-- Every old history field and physical rowid, plus the newly exposed shell field. -/
abbrev LogicalState := NullableView

/-- Existing history is exact; every old row gains an actual SQL NULL shell value. -/
def change (before after : LogicalState) : Prop :=
  after.rows = before.rows ∧ after.added = some (nullExtension before.rows)

/-- A runner failure explicitly identifies whether the migration committed. -/
def committed : ExecutionError → Bool
  | .runnerFailure _ yes => yes
  | _ => false

/-- Only the named runner-stage failures are permitted for this applicable payload. -/
def permitted : Outcome → Prop
  | .success _ => True
  | .failure position (.runnerFailure phase done) _ =>
    if done then position = 1 ∧ phase ∈ [.commit, .timingUpdate, .cacheClear]
    else rollbackPhase phase = true ∧
      position = if phase = .preflight ∨ phase = .beginTransaction then 0 else 1
  | .failure _ _ _ => False

/-- Retain the complete schema and distinguish rolled-back from committed errors. -/
def contract : LogicalContract LogicalState where
  valid := fun _ => True
  change := change
  schemaRequirement schema := schema = AtuinSchema.next
  failure before _ reason after := if committed reason then change before after else before = after
  applicability _ outcome := permitted outcome

end Requirements
