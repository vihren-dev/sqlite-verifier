import VerifierConformance.Native
import VerifierConformance.Outputs
import Belay.Sqlite.Resolution.SchemaScript

/-! ADR 0004's finite comparison authority. Native observations remain empirical
inputs; proving checkCase certifies only the model's agreement with those inputs.
A case carries statement syntax: the model resolves it, then executes it, and
compares each step's catalog and tables with the native ones. -/

namespace Belay.Sqlite.Conformance

/-- A version 5 case: the measured profile of the native connection, the SQL
texts, their statement syntax, the native tables before the migration, and native
truth after each executed statement. {lit}`outputs` is present when the record has
statement outputs; it then has one entry per executed statement. -/
structure Case where
  version : Nat
  profile : Profile
  schemaSql : String
  migrationSql : String
  schema : List Syntax.Statement
  script : List Syntax.Statement
  initial : List NativeTable
  nativeTrace : List NativeObservation
  requirements : List String := []
  provenance : List (String × String) := []
  parameters : List (List Value) := []
  outputs : Option (List NativeOutput) := none
  deriving Repr

/-- Unsupported cases cannot be mistaken for either agreement or a model bug. -/
inductive Verdict where
  | agree
  | disagree (position : Option Nat)
  | modelUnsupported
  deriving Repr, DecidableEq

/-- The resolution state before the first statement and after each statement, until
the first model restriction. These states assume successful execution of each
resolved statement. Execution can fail after resolution, so observation consumers
select the preceding state for a failed statement. -/
def resolveStates (context : ResolveContext) (index : Nat) (state : ResolveState) :
    List Syntax.Statement → List ResolveState
  | [] => [state]
  | statement :: rest => match resolveStatement context state index statement with
    | .ok (_, next) => state :: resolveStates context (index + 1) next rest
    | .error _ => [state]

/-- Select the catalog state for a zero-based trace observation. Index zero
is the initial observation. Success uses the state at the observation index;
a failed statement uses the preceding state, preserving its visible catalog and
saved transaction catalog. At index zero the preceding index is also zero.
An absent index uses the last state, or an empty catalog for an empty state list. -/
def observationState (states : List ResolveState) (index : Nat) (observation : Observation) : ResolveState :=
  let selected := if observation.error.isSome then index - 1 else index
  states[selected]?.getD (states.getLastD { catalog := [] })

/-- The number of catalog positions that any of the states uses, in its catalog or in
its saved catalog: the bound up to which a trace observes tables. -/
def stateBound (states : List ResolveState) : Nat :=
  states.foldl (fun bound state => max bound (max state.catalog.length ((state.saved.map List.length).getD 0))) 0

/-- The starting database: each catalog table holds the rows of the native table with
its folded name; a catalog table without a native table holds nothing. -/
def databaseOf (catalog : Catalog) (natives : List NativeTable) : Database :=
  fun position => match catalog[position]?, catalog.tableAt position with
    | some object, some shape => (natives.find? fun native =>
        normalizeIdentifier native.name == normalizeIdentifier object.name).map fun native =>
          { shape, rows := native.rows }
    | _, _ => none

/-- The primary result-code abstraction matches the granularity of ExecutionError. -/
def primaryCode : Option (Nat × ExecutionError) → Nat
  | none => 0
  | some (_, .constraintViolation) | some (_, .constraintFail) | some (_, .constraintRollback) => 19
  | some (_, .datatypeMismatch) => 20
  | some (_, .unmodeled) | some (_, .prepare _) | some (_, .transactionAlreadyActive)
  | some (_, .noActiveTransaction) | some (_, .integerOverflow) | some (_, .functionError)
  | some (_, .nullColumnDefault) => 1

/-- The phase in which SQLite reports a modeled error: a prepare error of resolution
in {lit}`sqlite3_prepare_v2`, and every other modeled error in {lit}`sqlite3_step`. -/
def errorPhase : Option (Nat × ExecutionError) → Option ErrorPhase
  | none => none
  | some (_, .prepare _) => some .prepare
  | some (_, .unmodeled) | some (_, .transactionAlreadyActive) | some (_, .noActiveTransaction)
  | some (_, .constraintViolation) | some (_, .constraintFail) | some (_, .constraintRollback)
  | some (_, .integerOverflow) | some (_, .datatypeMismatch) | some (_, .functionError)
  | some (_, .nullColumnDefault) => some .step

/-- Compare the visible and committed views under their catalogs, the transaction
status, the primary code and, when the recorder observed it, the error phase; never
compare error message text. -/
def matchesObservation (state : ResolveState) (model : Observation) (native : NativeObservation) : Bool :=
  tablesMatch state.catalog model.visible native.visible &&
  tablesMatch (state.saved.getD state.catalog) model.persisted native.persisted &&
  model.transactionOpen == native.transactionOpen && primaryCode model.error == native.primaryCode &&
  (native.phase.isNone || native.phase == errorPhase model.error)

/-- A missing or extra observation is a disagreement at its first statement position. -/
def compareSteps (states : List ResolveState) (position : Nat) :
    List Observation → List NativeObservation → Verdict
  | [], [] => .agree
  | model :: models, native :: natives =>
    let state := observationState states (position + 1) model
    if matchesObservation state model native then compareSteps states (position + 1) models natives
    else .disagree (some position)
  | _, _ => .disagree (some position)

/-- An unmodeled statement is an admission boundary, never a native SQLite error. -/
def invalidObservation (observation : Observation) : Bool :=
  match observation.error with
  | some (_, .unmodeled) => true
  | _ => false

/-- Missing capability stays unsupported; every available output must match native evidence. -/
def compareOutputs (position : Nat) : List (Option StatementOutput) → List NativeOutput → Verdict
  | [], [] => .agree
  | none :: _, _ => .modelUnsupported
  | some actual :: rest, expected :: expectations =>
    if matchesOutput expected.result actual expected.groups then
      compareOutputs (position + 1) rest expectations
    else .disagree (some position)
  | _, _ => .disagree (some position)

/-- Resolve the case under its recorded profile, then check the initial state first,
admission second, and the complete execution trace and outputs last. A model
restriction is unsupported; a schema that SQLite prepared but resolution refuses is
a disagreement. -/
def classifyCase (c : Case) : Verdict :=
  let profile := c.profile
  match resolveSchemaAndScript profile c.schema c.script with
  | .error (.schemaRestricted _) | .error (.scriptRestricted _) => .modelUnsupported
  | .error (.schemaPrepareError ..) => .disagree none
  | .ok resolution =>
    let states := resolveStates { profile, mode := .execution } 0 { catalog := resolution.startCatalog } c.script
    let count := stateBound states
    let initial := databaseOf resolution.startCatalog c.initial
    let observed := trace count resolution.resolved initial
    let outputs := outputTraceFrom 0 resolution.resolved { database := initial }
    match observed, c.nativeTrace with
    | first :: rest, expected :: expectations =>
      if !matchesObservation { catalog := resolution.startCatalog } first expected then .disagree none
      else if !supportedSqlFrom 0 resolution.resolved { database := initial } || observed.any invalidObservation ||
          c.parameters.any (fun values => !values.isEmpty) || (c.outputs.isSome && outputs.any Option.isNone) then
        .modelUnsupported
      else
        match compareSteps states 0 rest expectations with
        | .agree => match c.outputs with
          | none => .agree
          | some natives => compareOutputs 0 outputs natives
        | verdict => verdict
    | _, _ => .disagree none

/-- The model's outcome for a case: resolve the syntax, then run the resolved script
from the native starting tables; {name}`Option.none` when the model refuses the case. -/
def modelOutcome (c : Case) : Option Outcome :=
  match resolveSchemaAndScript c.profile c.schema c.script with
  | .ok resolution => some (runSql resolution.resolved (databaseOf resolution.startCatalog c.initial))
  | .error _ => none

/-- Both compiled testing and concrete kernel proofs use the same classification. -/
def checkCase (c : Case) : Bool := decide (classifyCase c = .agree)

/-- No unsupported verdict can supply successful tier-two proof evidence. -/
theorem unsupported_not_checked (c : Case) (h : classifyCase c = .modelUnsupported) :
    checkCase c = false := by simp [checkCase, h]

end Belay.Sqlite.Conformance
