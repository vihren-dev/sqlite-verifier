import Belay.Sqlite.SqlExecution

set_option doc.verso true

/-! General proof obligations are separate from additive proof conveniences.
Approved predicates determine permitted changes, applicability, and failure safety. -/

open Belay.Sqlite

namespace SqliteVerifier

/-- Approved logical predicates. Supply the application meaning explicitly: the
change relation need not be reflexive or transitive. Applicability is a required
outcome property. Equality preservation is available through a convenience contract. -/
structure LogicalContract (Logical : Type u) where
  /-- Predicate selecting valid logical values for the representation obligations. -/
  valid : Logical → Prop
  /-- Required relation between every observed before/after pair on success. -/
  change : Logical → Logical → Prop
  /-- Required predicate on the proposed schema on success or an error-free pending outcome. -/
  schemaRequirement : Schema → Prop
  /-- Required relation on observed before/result values at the actual failure position and error. -/
  failure : Logical → Nat → ExecutionError → Logical → Prop
  /-- Required outcome predicate for each admitted database and every execution outcome. -/
  applicability : Database → Outcome → Prop

/-- An invariant and a partial observation of actual storage. Use {lean}`Option.none`
when a database has no represented logical value; the invariant must prove that
every admitted starting database has a defined observation. -/
structure Interpretation (Logical : Type u) where
  /-- Predicate identifying storage represented by this interpretation. -/
  invariant : Database → Prop
  /-- Read an actual logical value; {lean}`Option.none` means the read is undefined. -/
  observe : Database → Option Logical

/-- Select the schema and interpretation for each zero-based failure position and
error. They describe the resulting storage, including a committed prefix. -/
structure FailureRepresentation (Logical : Type u) where
  /-- Result schema selected for every failure position and error. -/
  schema : Nat → ExecutionError → Schema
  /-- Result representation selected for every failure position and error. -/
  interpretation : Nat → ExecutionError → Interpretation Logical

/-- For every database satisfying the interpretation invariant, require conformance
to the given schema and an observed logical value that the contract declares valid.
A false invariant imposes no requirement. Use this for each before/after/failure representation. -/
def SoundRepresentation (contract : LogicalContract Logical) (schema : Schema)
    (interpretation : Interpretation Logical) : Prop :=
  ∀ database, interpretation.invariant database →
    Conforms schema database ∧ ∃ logical,
      interpretation.observe database = some logical ∧ contract.valid logical

/-- A database is admitted exactly when it conforms to the supplied schema and
satisfies the approved condition. This predicate does not assert that any such
database exists; a complete verification target requires a separate witness. -/
def Admitted (schema : Schema) (approvedConditions : Database → Prop)
    (database : Database) : Prop :=
  Conforms schema database ∧ approvedConditions database

/-- For every original value actually observed before execution, impose the
following result obligations. If no original value is observed, this predicate
requires nothing. Success and an error-free pending transaction require the after
invariant, the next-schema requirement and an observed value related by the
contract change predicate. Failure and a pending transaction with an error require
the selected failure invariant and an observed value related by the failure
predicate at that position/error. Committed storage is not inspected here. -/
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

/-- The complete verification target for bound schemas, script, approved conditions,
representations and profile. Each field is required; a starting witness prevents
inconsistent admission from making the universal obligations vacuous. Outcomes
are those of {name}`ProfileExecutes`, including errors and open transactions.
Supply an applicability predicate that states which outcomes the application allows. -/
structure VerificationConditions (startSchema nextSchema : Schema) (script : List Statement)
    (approvedConditions : Database → Prop) (contract : LogicalContract Logical)
    (before after : Interpretation Logical) (failures : FailureRepresentation Logical)
    (profile : ExecutionProfile := .sqlite351) : Prop where
  /-- There exists a conforming database satisfying the approved starting condition. -/
  nonempty : ∃ database, Admitted startSchema approvedConditions database
  /-- Every database in the before invariant conforms and has an observed valid value. -/
  beforeSound : SoundRepresentation contract startSchema before
  /-- Every database in the after invariant conforms and has an observed valid value. -/
  afterSound : SoundRepresentation contract nextSchema after
  /-- For every position/error, the failure invariant implies conformance and an observed valid value;
  an impossible failure invariant makes that instance vacuous. -/
  failuresSound : ∀ position reason,
    SoundRepresentation contract (failures.schema position reason)
      (failures.interpretation position reason)
  /-- Every admitted starting database satisfies the before invariant. -/
  starting : ∀ database, Admitted startSchema approvedConditions database → before.invariant database
  /-- Every admitted starting database satisfies the checked SQL support obligation. -/
  ready : ∀ database, Admitted startSchema approvedConditions database → SupportedSql startSchema script database
  /-- For every admitted database and every related outcome, require both applicability
  and {name}`OutcomeSatisfies`. No outcome may be excluded by an extra premise. -/
  outcomes : ∀ database, Admitted startSchema approvedConditions database →
    ∀ outcome, ProfileExecutes profile script database outcome →
      contract.applicability database outcome ∧
      OutcomeSatisfies nextSchema contract before after failures database outcome

/-- For every database, accept precisely a successful outcome. Failures and all
pending transactions are false. Use this when the application requires a closed,
successful script; the database argument is ignored. -/
def requiresSuccess (_ : Database) : Outcome → Prop
  | .success _ => True
  | .failure _ _ _ => False
  | .pending .. => False

/-- Build a contract whose validity is the supplied predicate and whose change
relation requires equality of the old and new logical values. Every next schema
satisfies its schema requirement. No failure is permitted, and applicability is
{name}`requiresSuccess`. Candidate proofs still establish sound representations. -/
def LogicalContract.preservation (valid : Logical → Prop) : LogicalContract Logical where
  valid := valid
  change := fun before after => after = before
  schemaRequirement _ := True
  failure := fun _ _ _ _ => False
  applicability := requiresSuccess

end SqliteVerifier
