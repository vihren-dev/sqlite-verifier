import VerifierConformance.Trace

/-! ADR 0004's finite comparison authority. Native observations remain empirical
inputs; proving checkCase certifies only the model's agreement with those inputs. -/

namespace SqliteVerifier.Conformance

/-- Present tables only; absence is reconstructed over the complete case name set. -/
abbrev FiniteDatabase := List (String × Table)

/-- Native extended codes are retained for diagnostics; the current model compares
primary codes because constraintViolation does not distinguish constraint kinds. -/
structure NativeObservation where
  visible : FiniteDatabase
  persisted : FiniteDatabase
  transactionOpen : Bool
  primaryCode : Nat
  extendedCode : Nat
  deriving Repr, DecidableEq

/-- Version-one case data keeps initialization separate from the migration. -/
structure Case where
  version : Nat
  schemaSql : String
  migrationSql : String
  schema : Schema
  initial : FiniteDatabase
  script : List Statement
  nativeTrace : List NativeObservation
  requirements : List String := []
  provenance : List (String × String) := []
  deriving Repr

/-- Unsupported cases cannot be mistaken for either agreement or a model bug. -/
inductive Verdict where
  | agree
  | disagree (position : Option Nat)
  | modelUnsupported
  deriving Repr, DecidableEq

/-- Interpret finite fixture contents without changing the production database type. -/
def databaseOf (tables : FiniteDatabase) : Database :=
  fun name => (tables.find? (fun entry => entry.1 == name)).map Prod.snd

/-- Include every name a statement can read or create, including failed statements. -/
def statementNames : Statement → List String
  | .createTable name _ | .addColumn name _ | .insert name _ _ | .update name .. => [name]
  | _ => []

/-- Fixture names are included even if native execution unexpectedly loses a table. -/
def Case.names (c : Case) : List String :=
  ((c.schema.map TableSchema.name) ++ c.initial.map Prod.fst ++
    c.script.flatMap statementNames ++ c.nativeTrace.flatMap (fun observation =>
      (observation.visible ++ observation.persisted).map Prod.fst)).eraseDups

/-- The primary result-code abstraction matches the granularity of ExecutionError. -/
def primaryCode : Option (Nat × ExecutionError) → Nat
  | none => 0
  | some (_, .constraintViolation) => 19
  | some _ => 1

/-- Compare typed states and transaction status; never compare error message text. -/
def matchesObservation (names : List String) (model : Observation)
    (native : NativeObservation) : Bool :=
  decide (model.visible = observeTables names (databaseOf native.visible)) &&
  decide (model.persisted = observeTables names (databaseOf native.persisted)) &&
  model.transactionOpen == native.transactionOpen && primaryCode model.error == native.primaryCode

/-- A missing or extra observation is a disagreement at its first statement position. -/
def compareSteps (names : List String) (position : Nat) :
    List Observation → List NativeObservation → Verdict
  | [], [] => .agree
  | model :: models, native :: natives =>
    if matchesObservation names model native then compareSteps names (position + 1) models natives
    else .disagree (some position)
  | _, _ => .disagree (some position)

/-- Keep production admission separate from modeled execution failures. -/
def admitted (c : Case) : Bool :=
  schemaAllows c.schema c.script && supportedSqlFrom 0 c.script { database := databaseOf c.initial }

/-- invalidDefinition is an admission boundary, never a native SQLite error. -/
def invalidObservation (observation : Observation) : Bool :=
  match observation.error with
  | some (_, .invalidDefinition) => true
  | _ => false

/-- Initial state is checked first, admission second, then the complete execution trace. -/
def classifyCase (c : Case) : Verdict :=
  let names := c.names
  let observed := trace names c.script (databaseOf c.initial)
  match observed, c.nativeTrace with
  | first :: rest, expected :: expectations =>
    if !matchesObservation names first expected then .disagree none
    else if !admitted c || observed.any invalidObservation then .modelUnsupported
    else compareSteps names 0 rest expectations
  | _, _ => .disagree none

/-- Both compiled testing and concrete kernel proofs use the same classification. -/
def checkCase (c : Case) : Bool := decide (classifyCase c = .agree)

/-- No unsupported verdict can supply successful tier-two proof evidence. -/
theorem unsupported_not_checked (c : Case) (h : classifyCase c = .modelUnsupported) :
    checkCase c = false := by simp [checkCase, h]

end SqliteVerifier.Conformance
