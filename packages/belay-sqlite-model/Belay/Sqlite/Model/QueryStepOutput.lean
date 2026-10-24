import Belay.Sqlite.Model.ScriptRun
import Belay.Sqlite.Model.Resolution.ResolveState

set_option doc.verso true

/-! The output of one statement of a run, in terms of the steps of its run (ADR 0017, S4): the
output that {name}`Belay.Sqlite.Model.runScriptStep` gives is the reason of a restriction, the
reason of a clock read or of an unknown counter, the reason of a statement that fails the support
check, or {name}`Belay.Sqlite.Model.Output.ofStep` of the statement's run and transition. The
surface reads the first output of a script with these facts. -/

namespace Belay.Sqlite.Model

/-- The output of a step of a run: the output of a statement that ran, or
{name}`Output.unmodeled` with the reason why the run ended at the statement. -/
def RunStep.output : RunStep → Output
  | .continued output _ => output
  | .ended reason => .unmodeled reason

/-- The output of a resolved statement at a zero-based index on the connection with the values
bound to its parameters, as {name}`runScriptStep` gives it: {name}`clockUnmodeled` for a statement
that reads a clock that the run does not have, {name}`counterUnknownReason` for an unknown counter,
{name}`unmodeledHere` for a statement that fails the support check, and otherwise
{name}`Output.ofStep` of its run and its transition. -/
def resolvedStepOutput (clock : Option Clock) (index : Nat) (connection : Connection) (parameters : List Value)
    (resolved : Resolved.Statement) : Output :=
  match statementClock clock index resolved with
  | none => .unmodeled clockUnmodeled
  | some value => match connection.state.counters.firstUnknown resolved.counterReads with
    | some kind => .unmodeled (counterUnknownReason kind)
    | none =>
      let run := connection.state.statementRun value parameters resolved
      if !run.ready then .unmodeled unmodeledHere
      else Output.ofStep value parameters resolved connection.state run (advanceRun index resolved connection.state run)

/-- For every statement that ran, its step ({name}`ranScriptStep`) has the output of
{name}`Output.ofStep`. Proof sketch: an output other than {name}`Output.unmodeled` continues with
it, and {name}`Output.unmodeled` ends the run with the same output. -/
theorem ranScriptStep_output (parameters : List Value) (connection : Connection) (resolved : Resolved.Statement)
    (after : ResolveState) (value : Int) (run : StatementRun) (transition : SqlTransition) :
    (ranScriptStep parameters connection resolved after value run transition).output =
      Output.ofStep value parameters resolved connection.state run transition := by
  unfold ranScriptStep
  split <;> simp_all [RunStep.output]

/-- For every context, clock, index, connection, statement and values, the output of the step
({name}`runScriptStep`) is {name}`Output.unmodeled` with the reason of the restriction when
resolution refuses the statement, and otherwise {name}`resolvedStepOutput` of the resolved
statement. Proof sketch: unfold the step and follow its cases; the cases that end the run give
{name}`Output.unmodeled`, and the others {name}`ranScriptStep_output`. -/
theorem runScriptStep_output (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statement : Syntax.Statement) (parameters : List Value) :
    (runScriptStep context clock index connection statement parameters).output =
      match resolveStatement context connection.resolveState statement with
      | .error restriction => .unmodeled restriction.reason
      | .ok (resolved, _) => resolvedStepOutput clock index connection parameters resolved := by
  unfold runScriptStep runScriptStepWith
  cases found : resolveStatement context connection.resolveState statement with
  | error restriction => simp [RunStep.output]
  | ok pair =>
    obtain ⟨resolved, after⟩ := pair
    simp only []
    unfold resolvedStepOutput
    cases statementClock clock index resolved with
    | none => simp [RunStep.output]
    | some value =>
      simp only []
      cases connection.state.counters.firstUnknown resolved.counterReads with
      | some kind => simp [RunStep.output]
      | none =>
        simp only []
        split
        · simp [RunStep.output]
        · rw [ranScriptStep_output]

/-- For every context, clock, index, connection, statement, values and later statements, the first
output of the run of a script that starts with that statement is the output of its step. Proof
sketch: a step that ends the run is the only output, and a step that continues puts its output
first. -/
theorem runScriptFrom_head_cons (context : ResolveContext) (clock : Option Clock) (index : Nat)
    (connection : Connection) (statement : Syntax.Statement) (parameters : List Value)
    (rest : List (Syntax.Statement × List Value)) :
    (runScriptFrom context clock index connection ((statement, parameters) :: rest)).outputs.head? =
      some (runScriptStep context clock index connection statement parameters).output := by
  unfold runScriptFrom
  cases runScriptStep context clock index connection statement parameters <;> simp [RunStep.output]

end Belay.Sqlite.Model
