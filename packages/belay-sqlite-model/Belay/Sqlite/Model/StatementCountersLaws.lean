import Belay.Sqlite.Model.ScriptRunAppend

set_option doc.verso true

/-! A statement does not depend on the counters of its connection that it does not read
(ADR 0024, D1 and D2). A state that knows fewer counters takes the same transition as one that
knows more, and its output is the same, unless the statement reads a counter that the first state
does not know. The laws for whole runs are in {lit}`ScriptRunCounters.lean`. -/

namespace Belay.Sqlite.Model

/-- The first state is the second state with fewer known counters: the same database, snapshot
and clock assignment, and each counter that the first state knows has the same value in the
second ({name}`Counters.LessKnown`). For example, the idle state of a database with unknown counters
is below the same state with known counters. -/
def SqlState.LessKnown (first second : SqlState) : Prop :=
  first.database = second.database ∧ first.snapshot = second.snapshot ∧ first.clock = second.clock ∧
    first.counters.LessKnown second.counters

/-- Two transitions where the first knows fewer counters: both continue with states where the first
state knows fewer counters ({name}`SqlState.LessKnown`), or both halt with the same outcome. -/
def SqlTransition.LessKnown : SqlTransition → SqlTransition → Prop
  | .next first, .next second => first.LessKnown second
  | .halt first, .halt second => first = second
  | .next _, .halt _ | .halt _, .next _ => False

/-- The first connection is the second connection with fewer known counters: its state is below
the state of the second ({name}`SqlState.LessKnown`) and it has the same settings. For example, a
connection and the same connection after a write are not in this relation when the write
changed the database. -/
def Connection.LessKnown (first second : Connection) : Prop :=
  first.state.LessKnown second.state ∧ first.foreignKeys = second.foreignKeys ∧
    first.recursiveTriggers = second.recursiveTriggers

/-- For every statement and effect, and two states where the first knows fewer counters: the
transitions of {name}`advanceWith` for the effect are in the same relation
({name}`SqlTransition.LessKnown`). Proof sketch: no case reads the counters; split on the
statement and the snapshot. -/
theorem advanceWith_counters (position : Nat) (statement : Resolved.Statement) (effect : Effect) {first second : SqlState}
    (same : first.LessKnown second) :
    (advanceWith position statement first effect).LessKnown (advanceWith position statement second effect) := by
  obtain ⟨database, snapshot, clockOf, counters⟩ := same
  cases first
  cases second
  simp only at database snapshot clockOf counters
  subst database snapshot clockOf
  cases statement <;>
    first
    | (cases effect with
        | ok database =>
          simp [advanceWith, SqlState.publish, SqlTransition.LessKnown, SqlState.LessKnown, counters]
        | error failure =>
          obtain ⟨reason, reached⟩ := failure
          simp [advanceWith, SqlState.publish, SqlState.failed, SqlState.finish, SqlTransition.LessKnown])
    | (simp only [advanceWith]
       split <;> simp [SqlState.finish, SqlTransition.LessKnown, SqlState.LessKnown, counters])

/-- For every transition pair in the relation {name}`SqlTransition.LessKnown` and every counts: the
transitions after the counts ({name}`SqlTransition.counted`) are in the relation. Proof sketch: a
halt stays, and the counts change only the counters of a state, in the same way for both
({name}`Counters.LessKnown.apply`). -/
theorem SqlTransition.counted_counters (counts : Counts) {first second : SqlTransition}
    (same : first.LessKnown second) : (first.counted counts).LessKnown (second.counted counts) := by
  cases first <;> cases second
  · obtain ⟨database, snapshot, clockOf, counters⟩ := same
    exact ⟨database, snapshot, clockOf, counters.apply counts⟩
  · exact absurd same id
  · exact absurd same id
  · simp only [SqlTransition.LessKnown] at same
    simp [SqlTransition.counted, SqlTransition.LessKnown, same]

/-- For every position, statement and run, and two states where the first knows fewer counters: the
transitions of {name}`advanceRun` are in the relation {name}`SqlTransition.LessKnown`. Proof
sketch: {name}`advanceWith_counters` and {name}`SqlTransition.counted_counters`. -/
theorem advanceRun_counters (position : Nat) (statement : Resolved.Statement) (run : StatementRun)
    {first second : SqlState} (same : first.LessKnown second) :
    (advanceRun position statement first run).LessKnown (advanceRun position statement second run) :=
  SqlTransition.counted_counters run.counts (advanceWith_counters position statement run.effect same)

/-- For every value of the clock, statement, values and run, and two states where the first knows
fewer counters, and every statement whose counters the first state knows: the run of the statement
on the second state is its run on the first ({name}`SqlState.statementRun`). Proof sketch: the
database is the same, and the views of the counters that the statement reads are the same
({name}`Counters.LessKnown.view_eq`), so the statement sees the same values. -/
theorem SqlState.statementRun_counters {first second : SqlState} (same : first.LessKnown second)
    (value : Int) (parameters : List Value) (statement : Resolved.Statement)
    (known : first.counters.firstUnknown statement.counterReads = none) :
    second.statementRun value parameters statement = first.statementRun value parameters statement := by
  obtain ⟨database, _, _, counters⟩ := same
  obtain ⟨view, secondKnown⟩ := counters.view_eq known
  simp only [SqlState.statementRun, database, view, secondKnown, known]

/-- For every clock value, values, statement and run, two states where the first knows fewer
counters and the first state knows every counter that the statement reads, and two transitions in
the relation {name}`SqlTransition.LessKnown`: the outputs of {name}`Output.ofStep` are equal. Proof
sketch: the output reads the states only for their database and for the counters that the statement
reads, which are the same ({name}`Counters.LessKnown.view_eq`), and the transitions only for whether
they continue or how they halt. -/
theorem Output.ofStep_counters (clock : Int) (parameters : List Value) (statement : Resolved.Statement)
    (run : StatementRun) {first second : SqlState} {firstStep secondStep : SqlTransition}
    (same : first.LessKnown second) (known : first.counters.firstUnknown statement.counterReads = none)
    (steps : firstStep.LessKnown secondStep) :
    Output.ofStep clock parameters statement first run firstStep =
      Output.ofStep clock parameters statement second run secondStep := by
  obtain ⟨database, snapshot, clockOf, counters⟩ := same
  obtain ⟨view, _⟩ := counters.view_eq known
  cases first
  cases second
  simp only at database snapshot clockOf view
  subst database snapshot clockOf
  simp only [Output.ofStep, statementOutput, possibleOutput, view]
  cases firstStep <;> cases secondStep
  · cases statement <;> rfl
  · exact absurd steps id
  · exact absurd steps id
  · simp only [SqlTransition.LessKnown] at steps
    subst steps
    rfl

end Belay.Sqlite.Model
