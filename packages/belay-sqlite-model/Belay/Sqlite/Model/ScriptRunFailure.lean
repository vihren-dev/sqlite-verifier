import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! The error of a statement whose output in a run ({name}`Belay.Sqlite.Model.runScriptStep`) is
{name}`Belay.Sqlite.Model.Output.error`, so that a diagnostic can give its message. The output
keeps only the result code; {lit}`runScriptStepFailure` gives the error, and
two theorems tie it to the output in both directions. -/

namespace Belay.Sqlite.Model

/-- The error of a statement that fails with the values bound to its parameters on the
connection, with an optional clock, with the statement as it resolves. It takes the same steps
as {name}`runScriptStep`: it resolves the statement, takes its clock value
({name}`statementClock`), runs the statement with the values at that value
({name}`runStatement`) and advances with {name}`advanceWith`, and gives the error with which
the transition stops ({name}`haltError`). It is
{lean}`(none : Option (Resolved.Statement × ExecutionError))` for a statement that has a
restriction, reads the clock in a run without a clock, fails the support check or does not
stop with an error. A diagnostic uses it to tell which error the output {name}`Output.error`
of the run has. -/
def runScriptStepFailure (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statement : Syntax.Statement) (parameters : List Value) : Option (Resolved.Statement × ExecutionError) :=
  match resolveStatement context connection.resolveState statement with
  | .error _ => none
  | .ok (resolved, _) =>
    match statementClock clock index resolved with
    | none => none
    | some value =>
      let run := runStatement value parameters resolved connection.state.database
      if !run.ready then none
      else (haltError (advanceWith index resolved connection.state run.effect)).map ((resolved, ·))

/-- For every list of results and code, {name}`Output.ofResults` of the results is not
{name}`Output.error` of the code. Proof sketch: each case of the sort gives
{name}`Output.rows`, {name}`Output.unmodeled` or {name}`Output.oneOf`. -/
theorem Output.ofResults_ne_error (results : List (List (List Value))) (code : Nat) :
    Output.ofResults results ≠ .error code := by
  unfold Output.ofResults
  split <;> simp

/-- For every clock, list of values, statement, state and transition: if {name}`Output.ofStep`
gives
{name}`Output.error` with a code, then the transition stops with an error
({name}`haltError`) whose {name}`ExecutionError.primaryCode` is that code. Proof sketch: split
each match of {name}`Output.ofStep`; only the case of an error that is not
{name}`ExecutionError.unmodeled` gives {name}`Output.error`, and a query's output is not one
({name}`Output.ofResults_ne_error`). -/
theorem Output.ofStep_error {clock : Int} {parameters : List Value} {statement : Resolved.Statement}
    {before : SqlState} {transition : SqlTransition} {code : Nat}
    (output : Output.ofStep clock parameters statement before transition = .error code) :
    ∃ failure, haltError transition = some failure ∧ failure.primaryCode = code := by
  unfold Output.ofStep at output
  split at output <;> (repeat' split at output) <;> simp_all [Output.ofResults_ne_error]

/-- For every context, optional clock, index, connection, statement, list of values, code and
connection {lit}`next`: if {name}`runScriptStep` with the clock and the values gives the output {name}`Output.error`
with the code and continues with {lit}`next`, then {name}`runScriptStepFailure` with the clock and
the values gives some resolved statement and error, and the
error's {name}`ExecutionError.primaryCode` is that code. So the error that a diagnostic names is
the one of the run's output. Proof sketch: both functions take the same steps; the output is
{name}`Output.error` only for a transition that stops with an error of that code
({name}`Output.ofStep_error`). -/
theorem runScriptStep_error_failure {context : ResolveContext} {clock : Option Clock} {index : Nat}
    {connection next : Connection} {statement : Syntax.Statement} {parameters : List Value} {code : Nat}
    (step : runScriptStep context clock index connection statement parameters = .continued (.error code) next) :
    ∃ resolved failure, runScriptStepFailure context clock index connection statement parameters =
      some (resolved, failure) ∧ failure.primaryCode = code := by
  unfold runScriptStep runScriptStepWith ranScriptStep at step
  unfold runScriptStepFailure
  cases resolution : resolveStatement context connection.resolveState statement with
  | error restriction => simp [resolution] at step
  | ok pair =>
    obtain ⟨resolved, after⟩ := pair
    simp only [resolution] at step ⊢
    cases valued : statementClock clock index resolved with
    | none => simp [valued] at step
    | some value =>
      by_cases ready : (runStatement value parameters resolved connection.state.database).ready
      · simp only [valued, ready, Bool.not_true, Bool.false_eq_true, ite_false] at step ⊢
        generalize ofStep : Output.ofStep _ parameters resolved connection.state _ = output at step
        cases output <;> simp at step
        obtain ⟨failure, halted, primary⟩ := Output.ofStep_error (step.1 ▸ ofStep)
        exact ⟨resolved, failure, by simp [halted], primary⟩
      · simp [valued, ready] at step

/-- For every clock, list of values, statement, state, transition and error: if the transition
stops with the error ({name}`haltError`) and the error is not {name}`ExecutionError.unmodeled`,
then {name}`Output.ofStep` with the values gives {name}`Output.error` with the error's
{name}`ExecutionError.primaryCode`. Proof sketch: rewrite the halt error into
{name}`Output.ofStep`, then split on the constructors of the error. -/
theorem Output.ofStep_halted {clock : Int} {parameters : List Value} {statement : Resolved.Statement}
    {before : SqlState} {transition : SqlTransition} {failure : ExecutionError} (halted : haltError transition = some failure)
    (modeled : failure ≠ .unmodeled) :
    Output.ofStep clock parameters statement before transition = .error failure.primaryCode := by
  unfold Output.ofStep
  rw [halted]
  cases failure <;> simp_all

/-- For every context, optional clock, index, connection, statement, list of values, resolved
statement and error: if {name}`runScriptStepFailure` with the clock and the values gives the
resolved statement and the error, and the error is not {name}`ExecutionError.unmodeled`, then
{name}`runScriptStep` with the clock and the values continues with the output
{name}`Output.error` of the error's {name}`ExecutionError.primaryCode`, with some next
connection. This is the converse of {name}`runScriptStep_error_failure`: the two functions take
the same steps. -/
theorem runScriptStepFailure_continued {context : ResolveContext} {clock : Option Clock} {index : Nat}
    {connection : Connection} {statement : Syntax.Statement} {parameters : List Value} {resolved : Resolved.Statement}
    {failure : ExecutionError}
    (found : runScriptStepFailure context clock index connection statement parameters = some (resolved, failure))
    (modeled : failure ≠ .unmodeled) :
    ∃ next, runScriptStep context clock index connection statement parameters =
      .continued (.error failure.primaryCode) next := by
  unfold runScriptStepFailure at found
  unfold runScriptStep runScriptStepWith ranScriptStep
  cases resolution : resolveStatement context connection.resolveState statement with
  | error restriction => simp [resolution] at found
  | ok pair =>
    obtain ⟨first, after⟩ := pair
    simp only [resolution] at found ⊢
    cases valued : statementClock clock index first with
    | none => simp [valued] at found
    | some value =>
      by_cases ready : (runStatement value parameters first connection.state.database).ready
      · simp only [valued, ready, Bool.not_true, Bool.false_eq_true, ite_false] at found ⊢
        obtain ⟨error, halted, same⟩ := Option.map_eq_some_iff.mp found
        cases same
        rw [Output.ofStep_halted halted modeled]
        exact ⟨_, rfl⟩
      · simp [valued, ready] at found

end Belay.Sqlite.Model
