import SqliteVerifier.ExtensionExecution

/-! General proof obligations are separate from additive proof conveniences.
Approved predicates determine permitted changes, applicability, and failure safety. -/

namespace SqliteVerifier

/-- Reusable human-approved logical requirements; Q need not be reflexive or transitive.
Applicability is an explicit outcome property, not an extra assumed precondition. -/
structure LogicalContract (Logical : Type u) where
  valid : Logical → Prop
  change : Logical → Logical → Prop
  schemaRequirement : Schema → Prop
  failure : Logical → Nat → ExecutionError → Logical → Prop
  applicability : Database → Outcome → Prop

/-- Partial reads expose missing coverage; the invariant must establish definedness.
The reader receives only represented storage, never a proof-only old database. -/
structure Interpretation (Logical : Type u) where
  invariant : Database → Prop
  observe : Database → Option Logical

/-- Failed scripts identify their actual prefix schema and resulting interpretation. -/
structure FailureRepresentation (Logical : Type u) where
  schema : Nat → ExecutionError → Schema
  interpretation : Nat → ExecutionError → Interpretation Logical

/-- Each declared representation invariant implies schema and logical validity. -/
def SoundRepresentation (contract : LogicalContract Logical) (schema : Schema)
    (interpretation : Interpretation Logical) : Prop :=
  ∀ database, interpretation.invariant database →
    Conforms schema database ∧ ∃ logical,
      interpretation.observe database = some logical ∧ contract.valid logical

/-- Approved initial conditions apply to all model-conforming starting databases. -/
def Admitted (schema : Schema) (approvedConditions : Database → Prop)
    (database : Database) : Prop :=
  Conforms schema database ∧ approvedConditions database

/-- Successful and failed outcomes have distinct approved logical obligations. -/
def OutcomeSatisfies (nextSchema : Schema) (contract : LogicalContract Logical)
    (before after : Interpretation Logical) (failures : FailureRepresentation Logical)
    (database : Database) (outcome : Outcome) : Prop :=
  ∀ original, before.observe database = some original →
    match outcome with
    | .success result =>
      after.invariant result ∧ contract.schemaRequirement nextSchema ∧
        ∃ logical, after.observe result = some logical ∧ contract.change original logical
    | .failure position reason result =>
      (failures.interpretation position reason).invariant result ∧ ∃ logical,
        (failures.interpretation position reason).observe result = some logical ∧
          contract.failure original position reason logical
    | .pending _ result none =>
      after.invariant result ∧ contract.schemaRequirement nextSchema ∧
        ∃ logical, after.observe result = some logical ∧ contract.change original logical
    | .pending _ result (some (position, reason)) =>
      (failures.interpretation position reason).invariant result ∧ ∃ logical,
        (failures.interpretation position reason).observe result = some logical ∧
          contract.failure original position reason logical

/-- This exact proposition is reconstructed from the supplied, bound inputs.
The witness prevents inconsistent starting assumptions from vacuously verifying.
Outcome coverage comes from ProfileExecutes.total; success is required only when the
approved applicability predicate says so. -/
structure VerificationConditions (startSchema nextSchema : Schema) (script : List Statement)
    (approvedConditions : Database → Prop) (contract : LogicalContract Logical)
    (before after : Interpretation Logical) (failures : FailureRepresentation Logical)
    (profile : ExecutionProfile := .sqlite351) : Prop where
  nonempty : ∃ database, Admitted startSchema approvedConditions database
  beforeSound : SoundRepresentation contract startSchema before
  afterSound : SoundRepresentation contract nextSchema after
  failuresSound : ∀ position reason,
    SoundRepresentation contract (failures.schema position reason)
      (failures.interpretation position reason)
  starting : ∀ database, Admitted startSchema approvedConditions database → before.invariant database
  ready : ∀ database, Admitted startSchema approvedConditions database → SupportedSql startSchema script database
  outcomes : ∀ database, Admitted startSchema approvedConditions database →
    ∀ outcome, ProfileExecutes profile script database outcome →
      contract.applicability database outcome ∧
      OutcomeSatisfies nextSchema contract before after failures database outcome

/-- A convenience applicability predicate requests success explicitly. -/
def requiresSuccess (_ : Database) : Outcome → Prop
  | .success _ => True
  | .failure _ _ _ => False
  | .pending .. => False

/-- Preserve an existing logical model through successful storage changes.
No future schema is prescribed; the candidate still proves sound representation. -/
def LogicalContract.preservation (valid : Logical → Prop) : LogicalContract Logical where
  valid := valid
  change := fun before after => after = before
  schemaRequirement _ := True
  failure := fun _ _ _ _ => False
  applicability := requiresSuccess

/-- Clients can prove the executable result instead of inspecting inductive derivations. -/
theorem VerificationConditions.of_run
    {Logical : Type u} {startSchema nextSchema : Schema} {script : List Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    (extensions : script.all Statement.isExtension = true)
    (schemaSupported : schemaAllows startSchema script = true)
    (nonempty : ∃ database, Admitted startSchema approvedConditions database)
    (beforeSound : SoundRepresentation contract startSchema before)
    (afterSound : SoundRepresentation contract nextSchema after)
    (failuresSound : ∀ position reason,
      SoundRepresentation contract (failures.schema position reason)
        (failures.interpretation position reason))
    (starting : ∀ database, Admitted startSchema approvedConditions database → before.invariant database)
    (checked : ∀ database, Admitted startSchema approvedConditions database →
      contract.applicability database (run script database) ∧
      OutcomeSatisfies nextSchema contract before after failures database (run script database)) :
    VerificationConditions startSchema nextSchema script approvedConditions contract before after failures := by
  refine ⟨nonempty, beforeSound, afterSound, failuresSound, starting,
    fun _ _ => ⟨schemaSupported, supportedSqlFrom_extensions extensions⟩, ?_⟩
  intro database admitted outcome execution
  have same : run script database = outcome :=
    (runSqlFrom_extensions extensions).symm.trans execution.result
  simpa only [same] using checked database admitted

/-- Equivalent runs reuse approved obligations, including all failure positions. -/
theorem VerificationConditions.congr_run
    {Logical : Type u} {startSchema nextSchema : Schema} {oldScript newScript : List Statement}
    {approvedConditions : Database → Prop} {contract : LogicalContract Logical}
    {before after : Interpretation Logical} {failures : FailureRepresentation Logical}
    (checked : VerificationConditions startSchema nextSchema oldScript approvedConditions
      contract before after failures)
    (extensions : newScript.all Statement.isExtension = true)
    (schemaSupported : schemaAllows startSchema newScript = true)
    (oldExtensions : oldScript.all Statement.isExtension = true)
    (same : ∀ database, Admitted startSchema approvedConditions database →
      run newScript database = run oldScript database) :
    VerificationConditions startSchema nextSchema newScript approvedConditions
      contract before after failures := by
  apply VerificationConditions.of_run extensions schemaSupported checked.nonempty checked.beforeSound checked.afterSound
    checked.failuresSound checked.starting
  intro database admitted
  rw [same database admitted]
  exact checked.outcomes database admitted _ (.extensions oldExtensions (runFrom_executes oldScript database 0))

/-- A checked schema contradiction refutes a success-required contract; this is
a model argument, distinct from failed proof search or a native counterexample. -/
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
