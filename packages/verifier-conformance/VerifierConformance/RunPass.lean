import VerifierConformance.Trace
import VerifierConformance.PossibleOutputs
import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! The classification pass of the run that continues after an error (ADR 0017, D3, amended
2026-10-22), for the records of a recorder that runs on after an SQL error. Each statement takes
the model's step ({name}`Belay.Sqlite.Model.runScriptStepWith` and
{name}`Belay.Sqlite.Model.ranScriptStep`, of which {name}`Belay.Sqlite.Model.runScriptStep` is
made), so the pass and {name}`Belay.Sqlite.Model.runScriptFrom` are one run
({lit}`VerifierConformance.RunPassLaws` proves it). The pass keeps what
the comparison needs and the run's output does not hold: the observation after each statement,
with the error and its phase, and the columns, rows and changes of each statement. -/

namespace Belay.Sqlite.Model.Conformance

/-- What the pass of the run that continues gives. For example, the pass of no statements has
no observations and no outputs, and is supported. -/
structure RunPass where
  /-- One observation after each statement that ran, with the error of a statement that
  stopped with one. -/
  observations : List Observation
  /-- The output of each statement that ran ({name}`statementOutput`). -/
  outputs : List (Option StatementOutput)
  /-- The results that SQLite may give for each statement that ran ({name}`possibleOutput`). -/
  possible : List (Option (List (List ResultRow)))
  /-- The output of each statement in the run ({name}`Output`): one for each statement that
  ran, and {name}`Output.unmodeled` last when the run ended early. -/
  results : List Output
  /-- Whether the run reached the end of the statements: false when a statement ended it. -/
  supported : Bool

/-- The pass of a run that ends at a statement, with the reason: no more observations or
outputs, the result {name}`Output.unmodeled` of the reason, and not supported. -/
def RunPass.ended (reason : String) : RunPass :=
  { observations := [], outputs := [], possible := [], results := [.unmodeled reason], supported := false }

/-- The observation after a statement at a zero-based index: the visible and committed
databases and the transaction status of the connection after it, and the error with which its
transition stops ({name}`haltError`), at the index. -/
def observeStep (index : Nat) (next : Connection) (transition : SqlTransition) : Observation :=
  { observeState next.state with error := (haltError transition).map ((index, ·)) }

/-- The pass over statements, each with the values bound to its parameters, from a zero-based
index on the connection, with an optional clock. Each statement takes the model's step
({name}`runScriptStepWith`, then {name}`ranScriptStep`). A step that ends the run ends the pass
({name}`RunPass.ended`). A step that continues gives the observation after it
({name}`observeStep`), its output and possible results from its transition, and the run's
output, and the pass goes on from the next connection, also after an error. -/
def runPassFrom (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection) :
    List (Syntax.Statement × List Value) → RunPass
  | [] => { observations := [], outputs := [], possible := [], results := [], supported := true }
  | (statement, parameters) :: rest =>
    runScriptStepWith RunPass.ended (fun resolved foreignKeys value run transition =>
      match ranScriptStep parameters connection resolved foreignKeys value run transition with
      | .ended reason => RunPass.ended reason
      | .continued output next =>
        let later := runPassFrom context clock (index + 1) next rest
        { observations := observeStep index next transition :: later.observations,
          outputs := statementOutput value parameters resolved connection.state run transition :: later.outputs,
          possible := possibleOutput value parameters resolved connection.state transition :: later.possible,
          results := output :: later.results, supported := later.supported })
      context clock index connection statement parameters

end Belay.Sqlite.Model.Conformance
