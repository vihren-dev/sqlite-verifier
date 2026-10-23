import Belay.Sqlite.Model.ScriptRunClock
import Belay.Sqlite.Model.StepCatalogLaws
import Belay.Sqlite.Model.Resolution.ResolveStateSpec

set_option doc.verso true

/-! The run that continues after an error agrees with {name}`Belay.Sqlite.Model.runSqlFrom`
(ADR 0017, D3, amended 2026-10-22). For a script that resolution accepts, on a state whose
clock assignment fits the run's clock ({name}`Belay.Sqlite.Model.ClockFits`), the two runs give
the same output for each statement up to and including the first error, and the same state at
the end of a script without an error, unless the new run ends earlier at a statement that the
model does not describe. {lit}`ScriptRunStates.lean` adds the state before each statement and the
database after the first error. -/

namespace Belay.Sqlite.Model

/-- What {name}`runSqlFrom` gives for each statement: the output of each statement that runs,
up to and including the first that halts, and the state after the last statement when no
statement halts. -/
structure SqlTrace where
  /-- The output of each statement that runs, from its transition ({name}`Output.ofStep`). -/
  outputs : List Output
  /-- The state after the last statement, or {lean}`(none : Option SqlState)` after a halt. -/
  final : Option SqlState

/-- The trace of {name}`runSqlFrom`: each statement advances with its values at its position
with {name}`advance` and gives {name}`Output.ofStep` of its transition; a halt ends the trace. -/
def sqlTraceFrom (position : Nat) : List (Resolved.Statement × List Value) → SqlState → SqlTrace
  | [], state => { outputs := [], final := some state }
  | (statement, parameters) :: rest, state =>
    let output := Output.ofStep (state.clock position) parameters statement state
      (advance position statement parameters state)
    match advance position statement parameters state with
    | .halt _ => { outputs := [output], final := none }
    | .next next =>
      let later := sqlTraceFrom (position + 1) rest next
      { later with outputs := output :: later.outputs }

/-- For every position, script of statements with values, state and final state: if the trace
has the final state, then
{name}`runSqlFrom` gives the success or the pending transaction of {name}`SqlState.finish` of
that state. Proof sketch: induction on the script; a halt has no final state. -/
theorem sqlTraceFrom_final :
    ∀ (position : Nat) (script : List (Resolved.Statement × List Value)) (state final : SqlState),
    (sqlTraceFrom position script state).final = some final →
    runSqlFrom position script state = final.finish (.success final.database)
  | _, [], state, final, ended => by
    simp only [sqlTraceFrom, Option.some.injEq] at ended
    subst ended
    rfl
  | position, (statement, parameters) :: rest, state, final, ended => by
    simp only [sqlTraceFrom] at ended
    simp only [runSqlFrom]
    split at ended
    · cases ended
    · rename_i next continued
      rw [continued]
      exact sqlTraceFrom_final (position + 1) rest next final ended

/-- For every state and resolution state: if the state agrees with the resolution state
({name}`SqlState.Agrees`), the connection with the state and the resolution state's settings
has that resolution state. Proof sketch: the catalogs and the saved catalogs are equal by the
agreement, and the settings are the resolution state's; the structures are then equal field by
field. -/
theorem Connection.resolveState_of_agrees {state : SqlState} {target : ResolveState} (agrees : state.Agrees target) :
    ({ state, foreignKeys := target.foreignKeys, recursiveTriggers := target.recursiveTriggers } : Connection).resolveState = target := by
  obtain ⟨catalog, saved⟩ := agrees
  cases target
  simp_all [Connection.resolveState]

/-- For every context, optional clock, index, connection, statement, list of values, resolved
statement and resolution state: if the statement resolves against the connection's resolution
state, and the connection's clock assignment gives the statement's clock value
({name}`statementClock`) at the index when it has one, then the step of the run with the clock
and the values either ends, or continues with the output of {name}`Output.ofStep` with the
values of the transition of {name}`advance` with the values, and the next connection is
{name}`Connection.afterStep` of that transition with the resolution state. Proof
sketch: unfold the step with the resolution; a statement without a clock value, the support
check and an {name}`Output.unmodeled` end it; otherwise the clock value is the assignment's, so
the step's transition is {name}`advance` by definition, and its output and its next connection
are the stated ones. -/
theorem runScriptStep_resolved {context : ResolveContext} {clock : Option Clock} {index : Nat}
    {connection : Connection} {statement : Syntax.Statement} {parameters : List Value}
    {resolved : Resolved.Statement} {after : ResolveState}
    (ok : resolveStatement context connection.resolveState statement = .ok (resolved, after))
    (fits : ∀ value, statementClock clock index resolved = some value → connection.state.clock index = value) :
    (∃ reason, runScriptStep context clock index connection statement parameters = .ended reason) ∨
    ∃ next, runScriptStep context clock index connection statement parameters = .continued
        (Output.ofStep (connection.state.clock index) parameters resolved connection.state
          (advance index resolved parameters connection.state)) next ∧
      next = connection.afterStep after (advance index resolved parameters connection.state) := by
  simp only [runScriptStep, runScriptStepWith, ranScriptStep, ok]
  split
  · exact .inl ⟨_, rfl⟩
  · rename_i value valued
    obtain rfl := fits value valued
    split
    · exact .inl ⟨_, rfl⟩
    · split
      · exact .inl ⟨_, rfl⟩
      all_goals
        rename_i stepped
        have unfolded : advance index resolved parameters connection.state = advanceWith index resolved connection.state
            (runStatement (connection.state.clock index) parameters resolved connection.state.database).effect := rfl
        rw [unfolded, stepped]
        exact .inr ⟨_, rfl, rfl⟩

/-- For every context, connection, statement, list of values, resolved statement, resolution
state and state: if the statement resolves against the connection's resolution state to the
resolution state {lit}`after`, and {name}`advance` with the values continues with the state, then the connection with the state
and the settings of {lit}`after` has the resolution state {lit}`after`. Proof sketch: the
transition keeps the state in agreement with the resolution ({name}`advance_agrees`,
{name}`resolveStatement_after`), and {name}`Connection.resolveState_of_agrees` applies. -/
theorem Connection.resolveState_after_next {context : ResolveContext} {index : Nat} {connection : Connection}
    {statement : Syntax.Statement} {resolved : Resolved.Statement} {after : ResolveState} {state : SqlState}
    (ok : resolveStatement context connection.resolveState statement = .ok (resolved, after))
    {parameters : List Value} (advanced : advance index resolved parameters connection.state = .next state) :
    ({ state, foreignKeys := after.foreignKeys, recursiveTriggers := after.recursiveTriggers } : Connection).resolveState = after := by
  have agrees := advance_agrees (state := connection.resolveState) ⟨rfl, rfl⟩ advanced
  rw [← resolveStatement_after context _ _ statement resolved ok] at agrees
  exact Connection.resolveState_of_agrees agrees

/-- The agreement of the two runs (ADR 0017, D3). For every context, optional clock, script of
statements with values, index, connection, resolved statements and final resolution state: if
{name}`resolveFrom` resolves the statements of the script from the index against the
connection's resolution state with the resolved statements, and the clock assignment of the
connection's state fits the run with the clock from the index over the resolved statements
({name}`ClockFits`), then one of the following holds for {name}`runScriptFrom` of the script
with the clock and the trace of {name}`runSqlFrom` of the resolved statements, each with the
values of its statement in the script ({name}`bindValues`), on the connection's state
({name}`sqlTraceFrom`):

* the run ends early: its outputs are some outputs and then one {name}`Output.unmodeled`, and
  those outputs are a prefix of the trace's outputs;
* the run does not end early before the first error: its outputs are the trace's outputs and
  then more outputs; when the trace has a final state (no statement halts), there are no more
  outputs and the run's connection has that state.

The statement says nothing about the outputs after the first error, which the trace does not
have. From index 0, the clock assignment of {name}`scriptClock` fits the run with its
assignment and the run without a clock ({name}`ClockFits.scriptClock`), so the trace is that of
{name}`runSqlAt`. Proof sketch: induction on the script. Each step resolves against the
connection's resolution state and runs at the assignment's clock value ({name}`ClockFits.head`);
a step that continues keeps the states in agreement ({name}`advance_agrees`) and the clock
assignment ({name}`advanceWith_clock`), so the next statement resolves against the state that
{name}`resolveFrom` gives ({name}`resolveStatement_after`) and the rest fits
({name}`ClockFits.tail`). -/
theorem runScriptFrom_agrees (context : ResolveContext) (clock : Option Clock) :
    ∀ (script : List (Syntax.Statement × List Value)) (index : Nat) (connection : Connection)
      (resolved : List Resolved.Statement) (final : ResolveState),
      resolveFrom context index connection.resolveState (script.map (·.1)) = .ok (resolved, final) →
      ClockFits clock index resolved connection.state.clock →
      (∃ before reason, (runScriptFrom context clock index connection script).outputs = before ++ [.unmodeled reason] ∧
        before <+: (sqlTraceFrom index (bindValues resolved (script.map (·.2))) connection.state).outputs) ∨
      (∃ later, (runScriptFrom context clock index connection script).outputs =
          (sqlTraceFrom index (bindValues resolved (script.map (·.2))) connection.state).outputs ++ later ∧
        ∀ state, (sqlTraceFrom index (bindValues resolved (script.map (·.2))) connection.state).final = some state →
          later = [] ∧ (runScriptFrom context clock index connection script).connection.state = state)
  | [], index, connection, resolved, final, ok, _ => by
    simp only [List.map_nil, resolveFrom, Except.ok.injEq, Prod.mk.injEq] at ok
    obtain ⟨rfl, rfl⟩ := ok
    refine .inr ⟨[], ?_, fun state ended => ?_⟩
    · rfl
    · simp only [bindValues, sqlTraceFrom, Option.some.injEq] at ended
      exact ⟨rfl, ended⟩
  | (statement, parameters) :: rest, index, connection, resolved, final, ok, fits => by
    simp only [List.map_cons, resolveFrom, bind, Except.bind] at ok
    split at ok
    · cases ok
    · rename_i head headState headOk
      split at ok
      · cases ok
      · rename_i later restOk
        simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at ok
        obtain ⟨rfl, rfl⟩ := ok
        rcases runScriptStep_resolved (index := index) (parameters := parameters) headOk (fun _ => fits.head) with
          ⟨reason, ended⟩ | ⟨next, continued, afterStep⟩
        · refine .inl ⟨[], reason, ?_, List.nil_prefix⟩
          simp [runScriptFrom, ended]
        · simp only [List.map_cons, bindValues_cons_cons, runScriptFrom, continued, sqlTraceFrom]
          split
          · exact .inr ⟨_, rfl, fun _ ended => by cases ended⟩
          · rename_i state advanced
            have nextState : next = { state, foreignKeys := headState.foreignKeys, recursiveTriggers := headState.recursiveTriggers } := by
              rw [afterStep, advanced]; rfl
            rw [← Connection.resolveState_after_next headOk advanced, ← nextState] at restOk
            rw [nextState] at restOk ⊢
            have restFits : ClockFits clock (index + 1) later.1 state.clock := by
              rw [advanceWith_clock advanced]; exact fits.tail
            rcases runScriptFrom_agrees context clock rest (index + 1) _ later.1 later.2 restOk restFits with
              ⟨before, reason, outputs, isPrefix⟩ | ⟨more, outputs, ending⟩
            · exact .inl ⟨_ :: before, reason, by simp [outputs], List.cons_prefix_cons.mpr ⟨rfl, isPrefix⟩⟩
            · exact .inr ⟨more, by simp [outputs], ending⟩

end Belay.Sqlite.Model
