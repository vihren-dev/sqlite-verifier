import SqliteVerifier.Contract

set_option doc.verso true

/-! Computation conveniences and refutation lemmas for the complete contract.
They remain separate from its definitions, so callers can supply the primitive
verification fields directly when these helpers do not fit their proof. -/

namespace SqliteVerifier

/-- Establish all verification fields from the computed SQL result. The caller
proves support and result obligations for every admitted database, as well as
nonempty admission and sound representations. No support premise is added to the
target. The proof uses {name}`ProfileExecutes.result` to cover every related
outcome. Use this when reasoning directly about {name}`runSql`. -/
theorem VerificationConditions.of_runSql
    {Logical : Type u} {startSchema nextSchema : Schema} {script : List Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    {profile : ExecutionProfile}
    (nonempty : ∃ database, Admitted startSchema approvedConditions database)
    (beforeSound : SoundRepresentation contract startSchema before)
    (afterSound : SoundRepresentation contract nextSchema after)
    (failuresSound : ∀ position reason,
      SoundRepresentation contract (failures.schema position reason)
        (failures.interpretation position reason))
    (starting : ∀ database, Admitted startSchema approvedConditions database → before.invariant database)
    (ready : ∀ database, Admitted startSchema approvedConditions database → SupportedSql startSchema script database)
    (checked : ∀ database, Admitted startSchema approvedConditions database →
      contract.applicability database (runSql script database) ∧
      OutcomeSatisfies nextSchema contract before after failures database (runSql script database)) :
    VerificationConditions startSchema nextSchema script approvedConditions contract before after failures profile := by
  refine ⟨nonempty, beforeSound, afterSound, failuresSound, starting, ready, ?_⟩
  intro database admitted outcome execution
  simpa only [execution.result] using checked database admitted

/-- Reuse checked obligations for a new script whose computed SQL outcome equals
the old script's outcome for every admitted database. The new script still needs
its own support proof for every admitted database. There is no requirement for
unadmitted databases. All failure positions and pending snapshots are retained.
The proof transfers the old outcome obligations through the supplied equality. -/
theorem VerificationConditions.congr_runSql
    {Logical : Type u} {startSchema nextSchema : Schema} {oldScript newScript : List Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    {profile : ExecutionProfile}
    (checked : VerificationConditions startSchema nextSchema oldScript approvedConditions
      contract before after failures profile)
    (ready : ∀ database, Admitted startSchema approvedConditions database → SupportedSql startSchema newScript database)
    (same : ∀ database, Admitted startSchema approvedConditions database →
      runSql newScript database = runSql oldScript database) :
    VerificationConditions startSchema nextSchema newScript approvedConditions
      contract before after failures profile := by
  apply VerificationConditions.of_runSql checked.nonempty checked.beforeSound checked.afterSound
    checked.failuresSound checked.starting ready
  intro database admitted
  rw [same database admitted]
  exact checked.outcomes database admitted _ .evaluated

/-- If applicability is {name}`requiresSuccess` and the proposed schema fails the
contract's schema requirement, no complete verification certificate exists for
these inputs. Nonempty admission rules out a vacuous certificate. The proof picks
its admitted witness: errors contradict required success, while success
contradicts the schema requirement. This is a model refutation, not a native test. -/
theorem violates_required_schema
    {Logical : Type u} {startSchema nextSchema : Schema} {script : List Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    (successRequired : contract.applicability = requiresSuccess)
    (schemaViolation : ¬contract.schemaRequirement nextSchema) :
    ¬VerificationConditions startSchema nextSchema script approvedConditions
      contract before after failures := by
  intro checked
  obtain ⟨database, admitted⟩ := checked.nonempty
  obtain ⟨logical, observed, _⟩ := (checked.beforeSound database (checked.starting database admitted)).2
  have obligations := checked.outcomes database admitted _ .evaluated
  cases outcome : runSql script database with
  | failure position reason result =>
    have impossible := obligations.1
    simp [outcome, successRequired, requiresSuccess] at impossible
  | success result =>
    have post := obligations.2 logical observed
    rw [outcome] at post
    exact schemaViolation post.2.1
  | pending persisted visible error =>
    have impossible := obligations.1
    simp [outcome, successRequired, requiresSuccess] at impossible

end SqliteVerifier
