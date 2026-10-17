import SqliteVerifier.Contract

set_option doc.verso true

/-! Computation conveniences and refutation lemmas for the complete contract.
They remain separate from its definitions, so callers can supply the primitive
verification fields directly when these helpers do not fit their proof. -/

open Belay.Sqlite

namespace SqliteVerifier

/-- Establish all verification fields from the computed SQL result under every clock
assignment. The caller proves support and result obligations for every admitted database
and every clock assignment, as well as nonempty admission and sound representations. No
support premise is added to the target. The proof uses {name}`ProfileExecutes.result` to
cover every related outcome. Use this for a script that reads the clock. -/
theorem VerificationConditions.of_runSqlAt
    {Logical : Type u} {startCatalog nextCatalog : Catalog} {script : List Resolved.Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    {profile : Profile}
    (nonempty : ∃ database, Admitted profile startCatalog approvedConditions database)
    (beforeSound : SoundRepresentation contract profile startCatalog before)
    (afterSound : SoundRepresentation contract profile nextCatalog after)
    (failuresSound : ∀ position reason,
      SoundRepresentation contract profile (failures.catalog position reason)
        (failures.interpretation position reason))
    (starting : ∀ database, Admitted profile startCatalog approvedConditions database → before.invariant database)
    (ready : ∀ database, Admitted profile startCatalog approvedConditions database → SupportedSql script database)
    (checked : ∀ database, Admitted profile startCatalog approvedConditions database → ∀ clock,
      contract.applicability database (runSqlAt clock script database) ∧
      OutcomeSatisfies nextCatalog contract before after failures database (runSqlAt clock script database)) :
    VerificationConditions startCatalog nextCatalog script approvedConditions contract before after failures profile := by
  refine ⟨nonempty, beforeSound, afterSound, failuresSound, starting, ready, ?_⟩
  intro database admitted outcome execution
  obtain ⟨clock, executed⟩ := execution.result
  rw [← executed]
  exact checked database admitted clock

/-- Establish all verification fields from the computed SQL result of a script that does
not read the clock ({name}`scriptReadsClock`). The caller proves support and result
obligations for every admitted database, as well as nonempty admission and sound
representations. No support premise is added to the target. The proof uses
{name}`ProfileExecutes.result_of_readsClock` to cover every related outcome. Use this when
reasoning directly about {name}`runSql`. -/
theorem VerificationConditions.of_runSql
    {Logical : Type u} {startCatalog nextCatalog : Catalog} {script : List Resolved.Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    {profile : Profile}
    (nonempty : ∃ database, Admitted profile startCatalog approvedConditions database)
    (beforeSound : SoundRepresentation contract profile startCatalog before)
    (afterSound : SoundRepresentation contract profile nextCatalog after)
    (failuresSound : ∀ position reason,
      SoundRepresentation contract profile (failures.catalog position reason)
        (failures.interpretation position reason))
    (starting : ∀ database, Admitted profile startCatalog approvedConditions database → before.invariant database)
    (ready : ∀ database, Admitted profile startCatalog approvedConditions database → SupportedSql script database)
    (checked : ∀ database, Admitted profile startCatalog approvedConditions database →
      contract.applicability database (runSql script database) ∧
      OutcomeSatisfies nextCatalog contract before after failures database (runSql script database))
    (free : scriptReadsClock script = false) :
    VerificationConditions startCatalog nextCatalog script approvedConditions contract before after failures profile := by
  refine ⟨nonempty, beforeSound, afterSound, failuresSound, starting, ready, ?_⟩
  intro database admitted outcome execution
  simpa only [execution.result_of_readsClock free] using checked database admitted

/-- Reuse checked obligations for a new script whose computed SQL outcome equals
the old script's outcome for every admitted database, where neither script reads the
clock ({name}`scriptReadsClock`). The new script still needs
its own support proof for every admitted database. There is no requirement for
unadmitted databases. All failure positions and pending snapshots are retained.
The proof transfers the old outcome obligations through the supplied equality. -/
theorem VerificationConditions.congr_runSql
    {Logical : Type u} {startCatalog nextCatalog : Catalog} {oldScript newScript : List Resolved.Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    {profile : Profile}
    (checked : VerificationConditions startCatalog nextCatalog oldScript approvedConditions
      contract before after failures profile)
    (ready : ∀ database, Admitted profile startCatalog approvedConditions database → SupportedSql newScript database)
    (same : ∀ database, Admitted profile startCatalog approvedConditions database →
      runSql newScript database = runSql oldScript database)
    (oldFree : scriptReadsClock oldScript = false) (newFree : scriptReadsClock newScript = false) :
    VerificationConditions startCatalog nextCatalog newScript approvedConditions
      contract before after failures profile := by
  refine VerificationConditions.of_runSql checked.nonempty checked.beforeSound checked.afterSound
    checked.failuresSound checked.starting ready ?_ newFree
  intro database admitted
  rw [same database admitted]
  exact checked.outcomes database admitted _ (ProfileExecutes.of_readsClock oldFree)

/-- If applicability is {name}`requiresSuccess` and the resulting catalog fails the
contract's catalog requirement, no complete verification certificate exists for
these inputs under any profile. Nonempty admission rules out a vacuous
certificate. The proof picks its admitted witness: errors contradict required
success, while success contradicts the catalog requirement. This is a model
refutation, not a native test. -/
theorem violates_required_catalog
    {Logical : Type u} {startCatalog nextCatalog : Catalog} {script : List Resolved.Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    (successRequired : contract.applicability = requiresSuccess)
    {profile : Profile}
    (catalogViolation : ¬contract.catalogRequirement nextCatalog) :
    ¬VerificationConditions startCatalog nextCatalog script approvedConditions
      contract before after failures profile := by
  intro checked
  obtain ⟨database, admitted⟩ := checked.nonempty
  obtain ⟨logical, observed, _⟩ := (checked.beforeSound database (checked.starting database admitted)).2
  have obligations := checked.outcomes database admitted _ (.evaluated fun _ => 0)
  cases outcome : runSqlAt (fun _ => 0) script database with
  | failure position reason result =>
    have impossible := obligations.1
    simp [outcome, successRequired, requiresSuccess] at impossible
  | success result =>
    have post := obligations.2 logical observed
    rw [outcome] at post
    exact catalogViolation post.2.1
  | pending persisted visible error =>
    have impossible := obligations.1
    simp [outcome, successRequired, requiresSuccess] at impossible

end SqliteVerifier
