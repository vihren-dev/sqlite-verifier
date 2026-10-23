import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! The run of {lit}`ScriptRun.lean` does not depend on the index at which it starts, when the
run has no clock or a clock that gives the same value at every index. The index reaches a
statement's step only through its clock value and the position of a failure
({name}`Belay.Sqlite.Model.Outcome.failure`), and a failure position reaches neither the output
nor the connection after the statement. The surface's runs have no clock, so a script that
follows another one runs as from index 0. -/

namespace Belay.Sqlite.Model

/-- The outcome with every failure position set to the position. -/
def Outcome.atPosition (position : Nat) : Outcome → Outcome
  | .success database => .success database
  | .failure _ reason database => .failure position reason database
  | .pending persisted visible error => .pending persisted visible (error.map fun (_, reason) => (position, reason))

/-- The transition with every failure position set to the position. -/
def SqlTransition.atPosition (position : Nat) : SqlTransition → SqlTransition
  | .next state => .next state
  | .halt outcome => .halt (outcome.atPosition position)

/-- For all positions, a statement, a state and an effect: the transition at the second position
is the transition at the first position with its failure positions set to the second. Proof
sketch: every failure that {name}`advanceWith` gives is at its position; case analysis on the
statement, the open transaction and the effect. -/
theorem advanceWith_atPosition (first second : Nat) (statement : Resolved.Statement) (state : SqlState)
    (effect : Effect) :
    advanceWith second statement state effect = (advanceWith first statement state effect).atPosition second := by
  cases statement <;> cases snapshot : state.snapshot <;> (try cases effect) <;>
    simp_all [advanceWith, SqlState.publish, SqlState.failed, SqlState.finish, SqlTransition.atPosition,
      Outcome.atPosition] <;> split <;> simp_all

/-- For every position and transition, the error of a halt ({name}`haltError`) is the same with
the failure positions set to the position. Proof sketch: case analysis on the transition and its
outcome; {name}`haltError` reads the reason of a failure, never its position. -/
@[simp] theorem haltError_atPosition (position : Nat) (transition : SqlTransition) :
    haltError (transition.atPosition position) = haltError transition := by
  cases transition with
  | next _ => rfl
  | halt outcome => cases outcome with
    | success _ => rfl
    | failure _ _ _ => rfl
    | pending _ _ error => cases error <;> rfl

/-- For every position and transition without a halt error ({name}`haltError`), setting the
failure positions does not change the transition: it has none. -/
theorem SqlTransition.atPosition_of_haltError (position : Nat) {transition : SqlTransition}
    (none : haltError transition = none) : transition.atPosition position = transition := by
  cases transition with
  | next _ => rfl
  | halt outcome => cases outcome with
    | success _ => rfl
    | failure _ _ _ => simp [haltError] at none
    | pending _ _ error => cases error <;> simp_all [haltError, SqlTransition.atPosition, Outcome.atPosition]

/-- For every clock value, list of values, statement, state, position and transition, the
output of the step ({name}`Output.ofStep`) is the same with the failure positions set to the position. Proof sketch:
with a halt error, the output reads only the error ({name}`haltError_atPosition`); without one,
the transition has no failure position ({name}`SqlTransition.atPosition_of_haltError`). -/
@[simp] theorem Output.ofStep_atPosition (clock : Int) (parameters : List Value) (statement : Resolved.Statement)
    (before : SqlState) (position : Nat) (transition : SqlTransition) :
    Output.ofStep clock parameters statement before (transition.atPosition position) =
      Output.ofStep clock parameters statement before transition := by
  cases error : haltError transition with
  | none => rw [SqlTransition.atPosition_of_haltError position error]
  | some failure => simp only [Output.ofStep, haltError_atPosition, error]; cases failure <;> rfl

/-- For every connection, resolution state, position and transition, the connection after the step
({name}`Connection.afterStep`) is the same with the failure positions set to the position: it
reads no failure position. -/
@[simp] theorem Connection.afterStep_atPosition (connection : Connection) (after : ResolveState) (position : Nat)
    (transition : SqlTransition) :
    connection.afterStep after (transition.atPosition position) = connection.afterStep after transition := by
  cases transition with
  | next _ => rfl
  | halt outcome => cases outcome <;> rfl

/-- For every optional clock, two indexes and resolved statement: if the clock, when the run
has one, gives the same value at both indexes, the statement's clock value
({name}`statementClock`) is the same at both. Proof sketch: case analysis on the clock; without
one, the value does not depend on the index. -/
theorem statementClock_index {clock : Option Clock} {first second : Nat}
    (same : ∀ assignment ∈ clock, assignment first = assignment second) (statement : Resolved.Statement) :
    statementClock clock first statement = statementClock clock second statement := by
  cases clock <;> simp_all [statementClock]

/-- For every context, optional clock, two indexes, connection, statement and list of values:
if the clock, when the run has one, gives the same value at both indexes, the statement's step
with the values ({name}`runScriptStep`) is the same at both. Proof sketch: resolution takes no
index, and the clock value is the same ({name}`statementClock_index`); the step at the first
index is the step at the second with its failure positions set ({name}`advanceWith_atPosition`),
and neither the output nor the next connection reads a failure position. -/
theorem runScriptStep_index (context : ResolveContext) (clock : Option Clock) (first second : Nat)
    (connection : Connection) (statement : Syntax.Statement) (parameters : List Value)
    (same : ∀ assignment ∈ clock, assignment first = assignment second) :
    runScriptStep context clock first connection statement parameters =
      runScriptStep context clock second connection statement parameters := by
  simp only [runScriptStep, runScriptStepWith, ranScriptStep, statementClock_index same, advanceWith_atPosition second first, Output.ofStep_atPosition,
    Connection.afterStep_atPosition]

/-- For every state, position, effect and next state: if the effect's transition
({name}`SqlState.publish`) continues with the next state, the next state has the clock of the
state. Proof sketch: only an effect without an error continues, and it changes only the
database. -/
theorem SqlState.publish_clock {state next : SqlState} {position : Nat} {effect : Effect}
    (continued : state.publish position effect = .next next) : next.clock = state.clock := by
  cases effect with
  | ok database => simp only [SqlState.publish, SqlTransition.next.injEq] at continued; subst continued; rfl
  | error failure => simp [SqlState.publish] at continued

/-- For every position, statement, state, effect and next state: if the transition continues
with the next state, the next state has the clock of the state. Proof sketch: a transaction
statement changes only the database and the snapshot; every other statement continues through
{name}`SqlState.publish` ({name}`SqlState.publish_clock`). -/
theorem advanceWith_clock {position : Nat} {statement : Resolved.Statement} {state next : SqlState} {effect : Effect}
    (continued : advanceWith position statement state effect = .next next) : next.clock = state.clock := by
  cases statement <;> first
    | exact SqlState.publish_clock continued
    | (cases snapshot : state.snapshot <;> simp [advanceWith, snapshot] at continued <;> subst continued <;> rfl)

/-- For every connection, resolution state, position, statement and effect, the connection after the
statement's transition ({name}`Connection.afterStep`) has the clock of the connection. Proof
sketch: a transition that continues keeps the clock ({name}`advanceWith_clock`); after a halt,
{name}`Connection.afterError` builds the state with the connection's clock. -/
theorem Connection.afterStep_clock (connection : Connection) (after : ResolveState) (position : Nat)
    (statement : Resolved.Statement) (effect : Effect) :
    (connection.afterStep after (advanceWith position statement connection.state effect)).state.clock =
      connection.state.clock := by
  cases transition : advanceWith position statement connection.state effect with
  | next state => exact advanceWith_clock transition
  | halt outcome => cases outcome <;> rfl

/-- For every context, optional clock, index, connection, statement and list of values: if the
step with the values continues with an output and a next connection, the next connection has
the clock assignment of the connection, and the output does not end the run
({name}`Output.endsRun`). Proof sketch: unfold the step; a continuing step's output is one of
the four outputs that do not end the run, and its connection is {name}`Connection.afterStep` of
a transition ({name}`Connection.afterStep_clock`). -/
theorem runScriptStep_continued {context : ResolveContext} {clock : Option Clock} {index : Nat}
    {connection next : Connection} {statement : Syntax.Statement} {parameters : List Value} {output : Output}
    (continued : runScriptStep context clock index connection statement parameters = .continued output next) :
    next.state.clock = connection.state.clock ∧ output.endsRun = false := by
  unfold runScriptStep runScriptStepWith ranScriptStep at continued
  split at continued
  · cases continued
  · split at continued
    · cases continued
    · dsimp only at continued
      split at continued
      · cases continued
      · split at continued <;> cases continued <;> exact ⟨Connection.afterStep_clock .., rfl⟩

end Belay.Sqlite.Model
