import VerifierConformance.Case
import VerifierConformance.RunPass

set_option doc.verso true

/-! The classification of a case (ADR 0004): a case whose recorder stops at the first error
compares the pass that halts ({name}`Belay.Sqlite.Model.Conformance.classifyHaltingCase`), and a
case whose recorder runs on after an SQL error compares the pass of the model's run that
continues ({name}`Belay.Sqlite.Model.Conformance.runPassFrom`). Compiled testing and kernel
proofs use the same classification ({lit}`checkCase`). -/

namespace Belay.Sqlite.Model.Conformance

/-- The clock of a run that continues, from the clock value of each statement: the values, and 0
beyond them, or {lean}`(none : Option Clock)` without values, so that a statement that reads the
clock ends the run. -/
def runClock (clocks : List Int) : Option Clock :=
  if clocks.isEmpty then none else some fun position => clocks.getD position 0

/-- The connection at the start of a run that continues: idle, on the database of the catalog
with the native starting tables ({name}`databaseOf`), with foreign keys as the profile sets
them. -/
def startConnection (profile : Profile) (catalog : Catalog) (initial : List NativeTable) : Connection :=
  { state := { database := databaseOf catalog initial }, foreignKeys := profile.foreignKeys }

/-- Classify a case whose recorder runs on after an SQL error: resolve the schema
({name}`resolveSchema`), then compare the pass of the run that continues ({name}`runPassFrom`)
from {name}`startConnection` with {name}`classifyObserved`. Each statement resolves against the
connection's state when it runs, with the values that the record binds to it
({name}`bindValues`) and the clock of the record's clock values ({name}`runClock`). A statement
that ends the run makes the case unsupported. A schema restriction is unsupported; a schema that
SQLite prepared but resolution refuses is a disagreement. -/
def classifyRunCase (c : Case) : Verdict :=
  match resolveSchema c.profile c.schema with
  | .error (.schemaRestricted _) | .error (.scriptRestricted _) => .modelUnsupported
  | .error (.schemaPrepareError ..) => .disagree none
  | .ok catalog =>
    let connection := startConnection c.profile catalog c.initial
    let pass := runPassFrom { profile := c.profile, mode := .execution } (runClock c.clocks) 0 connection
      (bindValues c.script c.parameters)
    classifyObserved c (observeState connection.state :: pass.observations) pass.outputs pass.possible pass.supported

/-- Classify a case: {name}`classifyRunCase` when its recorder ran on after an error
({lit}`Case.continues`), and {name}`classifyHaltingCase` otherwise. -/
def classifyCase (c : Case) : Verdict :=
  if c.continues then classifyRunCase c else classifyHaltingCase c

/-- Both compiled testing and concrete kernel proofs use the same classification. -/
def checkCase (c : Case) : Bool := decide (classifyCase c = .agree)

/-- For every case: if {name}`classifyCase` gives {name}`Verdict.modelUnsupported`, then
{name}`checkCase` is false. So no unsupported verdict can supply successful tier-two proof
evidence. -/
theorem unsupported_not_checked (c : Case) (h : classifyCase c = .modelUnsupported) :
    checkCase c = false := by simp [checkCase, h]

end Belay.Sqlite.Model.Conformance
