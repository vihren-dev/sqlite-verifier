import VerifierConformance.Native
import VerifierConformance.Pass
import Belay.Sqlite.Model.Resolution.SchemaScript

/-! ADR 0004's finite comparison authority. Native observations remain empirical
inputs; proving checkCase certifies only the model's agreement with those inputs.
A case carries statement syntax: the model resolves it, then executes it, and
compares each step's catalog and tables with the native ones. -/

namespace Belay.Sqlite.Model.Conformance

/-- A version 5 case: the measured profile of the native connection, the SQL
texts, their statement syntax, the native tables before the migration, and native
truth after each executed statement. {lit}`outputs` is present when the record has
statement outputs; it then has one entry per executed statement. {lit}`continues` tells
whether the run goes on after an error. -/
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
  /-- The clock value of each statement of the script, in SQLite's Julian-day milliseconds,
  as the recorder supplied it; empty for a record without a controlled clock. -/
  clocks : List Int := []
  /-- Whether the recorder ran on after an SQL error (native record version 6), so that the
  native trace has one observation after each statement of the script, and the model's run
  continues after an error too; false for a recorder that stops at the
  first error. -/
  continues : Bool := false
  deriving Repr

/-- Unsupported cases cannot be mistaken for either agreement or a model bug. -/
inductive Verdict where
  | agree
  | disagree (position : Option Nat)
  | modelUnsupported
  deriving Repr, DecidableEq

/-- The rows of a native table as the model stores them: as recorded, or for a
{lit}`WITHOUT ROWID` table numbered 1, 2, ... in recorded order, since SQLite gives them no
rowid and the model's rowids of such a table are its own (ADR 0014, D4). -/
def storedRows (table : CatalogTable) (rows : List Row) : List Row :=
  if table.withoutRowid then rows.zipIdx.map fun (row, index) => { row with rowid := index + 1 } else rows

/-- The starting database: the catalog, and at each catalog table the rows of the native
table with its folded name ({name}`storedRows`). A catalog table without a native table,
an index and a trigger hold no rows. -/
def databaseOf (catalog : Catalog) (natives : List NativeTable) : Database :=
  { catalog, rows := catalog.map fun object => match object.entry with
    | .table table => storedRows table (((natives.find? fun native =>
        native.name.sameName object.name).map (·.rows)).getD [])
    | .index _ | .trigger _ => [] }

/-- The primary result code of an observation's error: 0 without an error, and
{name}`ExecutionError.primaryCode` of the error. -/
def primaryCode : Option (Nat × ExecutionError) → Nat
  | none => 0
  | some (_, error) => error.primaryCode

/-- The phase in which SQLite reports a modeled error: a prepare error of resolution
in {lit}`sqlite3_prepare_v2`, and every other modeled error in {lit}`sqlite3_step`. -/
def errorPhase : Option (Nat × ExecutionError) → Option ErrorPhase
  | none => none
  | some (_, .prepare _) => some .prepare
  | some (_, .unmodeled) | some (_, .transactionAlreadyActive) | some (_, .noActiveTransaction)
  | some (_, .constraintViolation) | some (_, .constraintFail) | some (_, .constraintRollback)
  | some (_, .integerOverflow) | some (_, .datatypeMismatch) | some (_, .functionError)
  | some (_, .nullColumnDefault) | some (_, .nonConstantColumnDefault) | some (_, .checkColumnDefault) =>
    some .step

/-- Compare the visible and committed databases, each with its own catalog, the
transaction status, the primary code and, when the recorder observed it, the error phase;
never compare error message text. -/
def matchesObservation (model : Observation) (native : NativeObservation) : Bool :=
  tablesMatch model.visible native.visible && tablesMatch model.persisted native.persisted &&
  model.transactionOpen == native.transactionOpen && primaryCode model.error == native.primaryCode &&
  (native.phase.isNone || native.phase == errorPhase model.error)

/-- A missing or extra observation is a disagreement at its first statement position. -/
def compareSteps (position : Nat) : List Observation → List NativeObservation → Verdict
  | [], [] => .agree
  | model :: models, native :: natives =>
    if matchesObservation model native then compareSteps (position + 1) models natives
    else .disagree (some position)
  | _, _ => .disagree (some position)

/-- An unmodeled statement is an admission boundary, never a native SQLite error. -/
def invalidObservation (observation : Observation) : Bool :=
  match observation.error with
  | some (_, .unmodeled) => true
  | _ => false

/-- Missing capability stays unsupported; every available output must match native evidence, and
the rows of a query that succeeds must be one of the results that SQLite may give
({name}`NativeOutput.fits`, ADR 0018, D6). -/
def compareOutputs (position : Nat) : List (Option StatementOutput) → List NativeOutput →
    List (Option (List (List ResultRow))) → Verdict
  | [], [], _ => .agree
  | none :: _, _, _ => .modelUnsupported
  | some actual :: rest, expected :: expectations, possible =>
    if matchesOutput expected.result actual expected.groups && expected.fits (possible.head?.join) then
      compareOutputs (position + 1) rest expectations possible.tail
    else .disagree (some position)
  | _, _, _ => .disagree (some position)

/-- The clock assignment of a case: the recorded clock value of each statement, and 0
beyond them, where SQLite's time keywords give NULL. -/
def Case.clock (c : Case) : Clock := fun position => c.clocks.getD position 0

/-- Compare the model's observations, outputs and possible results of a case with the native
evidence: the initial state first, admission second ({lit}`supported`, an unmodeled
observation, and a missing output where the record has outputs), and the execution trace and
outputs last. -/
def classifyObserved (c : Case) (observed : List Observation) (outputs : List (Option StatementOutput))
    (possible : List (Option (List (List ResultRow)))) (supported : Bool) : Verdict :=
  match observed, c.nativeTrace with
  | first :: rest, expected :: expectations =>
    if !matchesObservation first expected then .disagree none
    else if !supported || observed.any invalidObservation || (c.outputs.isSome && outputs.any Option.isNone) then
      .modelUnsupported
    else
      match compareSteps 0 rest expectations with
      | .agree => match c.outputs with
        | none => .agree
        | some natives => compareOutputs 0 outputs natives possible
      | verdict => verdict
  | _, _ => .disagree none

/-- Classify a case whose recorder stops at the first error: resolve the case under its recorded
profile, then compare its pass that halts ({name}`passFrom`) with {name}`classifyObserved`.
Each statement runs at its recorded clock value as {name}`runSqlAt` gives it
({name}`scriptClock`), with the values that the record binds to it ({name}`bindValues` of
{lit}`Case.parameters`); a script that reads the clock is unsupported for a record without clock
values. A model restriction is unsupported; a schema that SQLite prepared but resolution refuses
is a disagreement. -/
def classifyHaltingCase (c : Case) : Verdict :=
  match resolveSchemaAndScript c.profile c.schema c.script with
  | .error (.schemaRestricted _) | .error (.scriptRestricted _) => .modelUnsupported
  | .error (.schemaPrepareError ..) => .disagree none
  | .ok resolution =>
    let pass := passFrom 0 (bindValues resolution.resolved c.parameters)
      { database := databaseOf resolution.startCatalog c.initial, clock := scriptClock c.clock resolution.resolved }
    classifyObserved c pass.observations pass.outputs pass.possible
      (!(c.clocks.isEmpty && scriptReadsClock resolution.resolved) && pass.supported)

/-- The model's outcome for a case: resolve the syntax, then run the resolved script with the
values that the record binds to each statement from the native starting tables; {name}`Option.none` when the model refuses the case. -/
def modelOutcome (c : Case) : Option Outcome :=
  match resolveSchemaAndScript c.profile c.schema c.script with
  | .ok resolution =>
    some (runSqlAt c.clock (bindValues resolution.resolved c.parameters) (databaseOf resolution.startCatalog c.initial))
  | .error _ => none

end Belay.Sqlite.Model.Conformance
