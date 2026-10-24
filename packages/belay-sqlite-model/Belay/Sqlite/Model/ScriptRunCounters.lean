import Belay.Sqlite.Model.StatementCountersLaws

set_option doc.verso true

/-! A run does not depend on the counters of its connection that its statements do not read
(ADR 0024, D1 and D2). A connection that knows fewer counters takes the same steps as one that
knows more, until a statement reads a counter that the first connection does not know: the same
outputs, and next connections that again know fewer counters. A statement that reads such a counter
ends the run with {name}`Belay.Sqlite.Model.counterUnknownReason`, so the law holds for the runs that have no output
with that reason. The laws for one statement are in {lit}`StatementCountersLaws.lean`. -/

namespace Belay.Sqlite.Model

/-- Whether the output is the end of a run at a statement that calls a counter function whose
counter the connection does not know: {name}`Output.unmodeled` with the reason
{name}`counterUnknownReason` of one of the three counters. -/
def Output.endsAtUnknownCounter (output : Output) : Bool :=
  [CounterKind.changes, .totalChanges, .lastInsertRowid].any fun kind =>
    output == .unmodeled (counterUnknownReason kind)

/-- For every counter, the output that ends a run at a read of it is in the set of
{name}`Output.endsAtUnknownCounter`. Proof sketch: check the three counters. -/
theorem Output.endsAtUnknownCounter_of_reason (kind : CounterKind) :
    (Output.unmodeled (counterUnknownReason kind)).endsAtUnknownCounter = true := by
  cases kind <;> simp [Output.endsAtUnknownCounter]

/-- For every output: if it ends a run at an unknown counter, it ends the run
({name}`Output.endsRun`). So a run with no output that ends it has none that ends at an unknown
counter. Proof sketch: only {name}`Output.unmodeled` ends a run, and the first can be nothing
else. -/
theorem Output.endsRun_of_endsAtUnknownCounter {output : Output} (ends : output.endsAtUnknownCounter = true) :
    output.endsRun = true := by
  cases output <;> simp_all [Output.endsAtUnknownCounter, Output.endsRun]

/-- Whether a step ended the run because a statement reads a counter that the connection does not
know ({name}`counterUnknownReason`). -/
def RunStep.endedUnknown (step : RunStep) : Prop :=
  ∃ kind, step = .ended (counterUnknownReason kind)

/-- What a step of a run gives when the first connection knows fewer counters: either the first
step ends the run because it reads a counter that the first connection does not know, or both
steps are the same. The same steps are two ends with the same reason, and two continuations with the
same output and with connections where the first knows fewer counters. -/
def RunStep.LessKnown (first second : RunStep) : Prop :=
  first.endedUnknown ∨ match first, second with
    | .ended firstReason, .ended secondReason => firstReason = secondReason
    | .continued firstOutput firstNext, .continued secondOutput secondNext =>
      firstOutput = secondOutput ∧ firstNext.LessKnown secondNext
    | .ended _, .continued .. | .continued .., .ended _ => False

/-- For every counter and step, a first step that ends the run at a read of that counter is in the
relation {name}`RunStep.LessKnown` with the step. Proof sketch: the first disjunct. -/
theorem RunStep.ended_lessKnown (kind : CounterKind) (step : RunStep) :
    (RunStep.ended (counterUnknownReason kind)).LessKnown step :=
  Or.inl ⟨kind, rfl⟩

/-- For every connection pair in the relation {name}`Connection.LessKnown`, every after-state,
counts and transition pair in the relation {name}`SqlTransition.LessKnown`: the connections after
the step are in the relation. Proof sketch: a transition that continues gives its state; a halt
gives the database of its outcome, which is the same on both sides, and the counters after the
counts ({name}`Counters.LessKnown.apply`). -/
theorem Connection.afterStep_counters {first second : Connection} (after : ResolveState) (counts : Counts)
    {firstStep secondStep : SqlTransition} (same : first.LessKnown second)
    (steps : firstStep.LessKnown secondStep) :
    (first.afterStep after counts firstStep).LessKnown (second.afterStep after counts secondStep) := by
  obtain ⟨⟨database, snapshot, clockOf, counters⟩, _, _⟩ := same
  cases firstStep <;> cases secondStep
  · exact ⟨steps, rfl, rfl⟩
  · exact absurd steps id
  · exact absurd steps id
  · simp only [SqlTransition.LessKnown] at steps
    subst steps
    rename_i outcome
    cases outcome <;>
      exact ⟨⟨rfl, rfl, clockOf, counters.apply counts⟩, rfl, rfl⟩

/-- For every context, clock, index, statement and values, and two connections where the first knows
fewer counters: the step of {name}`runScriptStep` on the first connection is in the relation
{name}`RunStep.LessKnown` with the step on the second. So the first step ends at a read of a counter
that the first connection does not know, or both steps end with the same reason, or both give the
same output and again connections in the relation. Proof sketch: resolution, the clock value and the support check read the database, the snapshot and the
settings, which are the same; a first connection that does not end the run knows every counter that
the statement reads, so the run of the statement is the same on both
({name}`SqlState.statementRun_counters`); the output and the next connection follow from
{name}`Output.ofStep_counters`, {name}`advanceRun_counters` and {name}`Connection.afterStep_counters`. -/
theorem runScriptStep_counters (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {first second : Connection} (same : first.LessKnown second) (statement : Syntax.Statement)
    (parameters : List Value) :
    (runScriptStep context clock index first statement parameters).LessKnown
      (runScriptStep context clock index second statement parameters) := by
  have resolving : first.resolveState = second.resolveState := by
    obtain ⟨⟨database, snapshot, _⟩, settings, recursive⟩ := same
    simp only [Connection.resolveState, database, snapshot, settings, recursive]
  unfold runScriptStep runScriptStepWith
  rw [resolving]
  cases resolveStatement context second.resolveState statement with
  | error restriction => simp [RunStep.LessKnown]
  | ok resolvedAfter =>
    obtain ⟨resolved, after⟩ := resolvedAfter
    simp only
    cases statementClock clock index resolved with
    | none => simp [RunStep.LessKnown]
    | some value =>
      cases known : first.state.counters.firstUnknown resolved.counterReads with
      | some kind =>
        simp only
        exact RunStep.ended_lessKnown _ _
      | none =>
        have run := SqlState.statementRun_counters same.1 value parameters resolved known
        have secondKnown := (same.1.2.2.2.view_eq known).2
        simp only [secondKnown, run]
        by_cases ready : (first.state.statementRun value parameters resolved).ready = true
        · have steps := advanceRun_counters index resolved (first.state.statementRun value parameters resolved) same.1
          have output := Output.ofStep_counters value parameters resolved
            (first.state.statementRun value parameters resolved) same.1 known steps
          simp only [ready, Bool.not_true, Bool.false_eq_true, ite_false, ranScriptStep, output]
          split
          · simp [RunStep.LessKnown]
          all_goals
            simp only [RunStep.LessKnown]
            exact Or.inr ⟨trivial, Connection.afterStep_counters after _ same steps⟩
        · simp [ready, RunStep.LessKnown]

/-- For every context, clock, statements with values, and two connections where the first knows
fewer counters: if no output of the run on the first connection ends at an unknown counter
({name}`Output.endsAtUnknownCounter`), the runs ({name}`runScriptFrom`) have the same
outputs, and end on connections where the first knows fewer counters. So a script that does not
read an unknown counter has the same outputs on a connection that knows no counter as on one that
knows them. Proof sketch: induction on the statements, with {name}`runScriptStep_counters` for
each step; a step that ends the run with another reason ends both runs with it. -/
theorem runScriptFrom_counters (context : ResolveContext) (clock : Option Clock) :
    ∀ (script : List (Syntax.Statement × List Value)) (index : Nat) {first second : Connection},
      first.LessKnown second →
        (∀ output ∈ (runScriptFrom context clock index first script).outputs, output.endsAtUnknownCounter = false) →
        (runScriptFrom context clock index first script).outputs =
            (runScriptFrom context clock index second script).outputs ∧
          (runScriptFrom context clock index first script).connection.LessKnown
            (runScriptFrom context clock index second script).connection
  | [], _, _, _, same, _ => ⟨rfl, same⟩
  | (statement, parameters) :: rest, index, first, second, same, modeled => by
    have step := runScriptStep_counters context clock index same statement parameters
    unfold runScriptFrom at modeled ⊢
    cases firstStep : runScriptStep context clock index first statement parameters with
    | ended reason =>
      rw [firstStep] at step
      simp only [firstStep] at modeled
      rcases step with ⟨kind, known⟩ | sameStep
      · injection known with reasonOf
        have ends := modeled (.unmodeled reason) (by simp)
        rw [reasonOf, Output.endsAtUnknownCounter_of_reason] at ends
        exact absurd ends (by decide)
      · cases secondStep : runScriptStep context clock index second statement parameters with
        | ended other =>
          rw [secondStep] at sameStep
          change reason = other at sameStep
          subst sameStep
          simp only
          exact ⟨trivial, same⟩
        | continued otherOutput otherNext => rw [secondStep] at sameStep; exact absurd sameStep id
    | continued output next =>
      rw [firstStep] at step
      rcases step with ⟨kind, known⟩ | sameStep
      · exact absurd known (by simp)
      · cases secondStep : runScriptStep context clock index second statement parameters with
        | ended other => rw [secondStep] at sameStep; exact absurd sameStep id
        | continued otherOutput otherNext =>
          rw [secondStep] at sameStep
          obtain ⟨sameOutput, sameNext⟩ := sameStep
          subst sameOutput
          simp only [firstStep] at modeled ⊢
          have later := runScriptFrom_counters context clock rest (index + 1) sameNext
            (fun output found => modeled output (List.mem_cons_of_mem _ found))
          exact ⟨by simp only [later.1], later.2⟩

end Belay.Sqlite.Model
