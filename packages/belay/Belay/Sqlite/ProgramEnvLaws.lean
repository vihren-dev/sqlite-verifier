import Belay.Sqlite.ProgramLaws

set_option doc.verso true

/-! The laws of the environment of a run (ADR 0017, D3; ADR 0024, D1): a run does not depend on
the clock of its environment while no statement reads the clock, and it does not depend on the
counters of its environment while no statement calls a counter function that the run does not
know. {lit}`Script.run_env` states both for the run of a script, {lit}`Sql.run_env` for the run of
a program. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every start database and two model results of programs with the same outputs, value,
database, open transaction and settings: the checked runs ({name}`Run.checked`) are equal. The
counters and the clock assignment of the connections do not appear in a checked run. Proof sketch:
split both results into their fields, replace the equal fields, and unfold {name}`Run.checked`. -/
theorem Run.checked_congr {α : Type} (start : Database) {first second : SqlRun α}
    (outputs : first.outputs = second.outputs) (value : first.value = second.value)
    (database : first.connection.state.database = second.connection.state.database)
    (snapshot : first.connection.state.snapshot = second.connection.state.snapshot)
    (foreignKeys : first.connection.foreignKeys = second.connection.foreignKeys)
    (recursiveTriggers : first.connection.recursiveTriggers = second.connection.recursiveTriggers) :
    Run.checked start first = Run.checked start second := by
  rcases first with ⟨⟨firstOutputs, ⟨⟨firstDatabase, firstSnapshot, firstClock, firstCounters⟩, firstForeign, firstRecursive⟩⟩, firstValue⟩
  rcases second with ⟨⟨secondOutputs, ⟨⟨secondDatabase, secondSnapshot, secondClock, secondCounters⟩, secondForeign, secondRecursive⟩⟩, secondValue⟩
  simp only at outputs value database snapshot foreignKeys recursiveTriggers
  subst outputs value database snapshot foreignKeys recursiveTriggers
  rfl

/-- For every start database and model result of a program, each output of the result is an output
of the checked run ({name}`Run.checked`). Proof sketch: the checked run keeps the outputs of the
result, and adds an output at the end when the database is not valid. -/
theorem Run.mem_checked_outputs {α : Type} {start : Database} {result : SqlRun α} {output : Output}
    (member : output ∈ result.outputs) : output ∈ (Run.checked start result).outputs := by
  unfold Run.checked
  split
  · exact member
  · split
    · exact member
    · exact List.mem_append_left _ member

/-- For every program, optional clock, index and two connections where the first knows fewer
counters ({name}`Belay.Sqlite.Model.Connection.LessKnown`): if no output of the run on the first
connection ends at an unknown counter ({name}`Output.endsAtUnknownCounter`), the runs of the program
({name}`Sql.runFrom`) have the same outputs and the same value, and end on connections where the
first knows fewer counters. Proof sketch: induction on the program; each statement takes
related steps ({name}`Belay.Sqlite.Model.runScriptStep_counters`), and a step that ends the run
ends both runs with the same reason. -/
theorem Sql.runFrom_counters {α : Type} (program : Sql α) (clock : Option Clock) :
    ∀ (index : Nat) {first second : Connection}, first.LessKnown second →
      (∀ output ∈ (program.runFrom clock index first).outputs, output.endsAtUnknownCounter = false) →
        (program.runFrom clock index first).outputs = (program.runFrom clock index second).outputs ∧
          (program.runFrom clock index first).value = (program.runFrom clock index second).value ∧
          (program.runFrom clock index first).connection.LessKnown (program.runFrom clock index second).connection := by
  induction program with
  | pure value => intro index first second same _; exact ⟨rfl, rfl, same⟩
  | exec statement values rest later =>
    intro index first second same modeled
    have step := runScriptStep_counters runContext clock index same statement values
    simp only [Sql.runFrom] at modeled ⊢
    cases firstStep : runScriptStep runContext clock index first statement values with
    | ended reason =>
      rw [firstStep] at step
      simp only [firstStep] at modeled
      rcases step with ⟨kind, known⟩ | sameStep
      · injection known with reasonOf
        have ends := modeled (.unmodeled reason) (by simp)
        rw [reasonOf, Output.endsAtUnknownCounter_of_reason] at ends
        exact absurd ends (by decide)
      · cases secondStep : runScriptStep runContext clock index second statement values with
        | ended other =>
          rw [secondStep] at sameStep
          change reason = other at sameStep
          subst sameStep
          exact ⟨rfl, rfl, same⟩
        | continued otherOutput otherNext => rw [secondStep] at sameStep; exact absurd sameStep id
    | continued output next =>
      rw [firstStep] at step
      rcases step with ⟨kind, known⟩ | sameStep
      · exact absurd known (by simp)
      · cases secondStep : runScriptStep runContext clock index second statement values with
        | ended other => rw [secondStep] at sameStep; exact absurd sameStep id
        | continued otherOutput otherNext =>
          rw [secondStep] at sameStep
          obtain ⟨sameOutput, sameNext⟩ := sameStep
          subst sameOutput
          simp only [firstStep] at modeled ⊢
          have inner := later output (index + 1) sameNext
            (fun found member => modeled found (List.mem_cons_of_mem _ member))
          exact ⟨by simp only [inner.1], inner.2.1, inner.2.2⟩

/-- For every program, database and environment: if no output of the run under
{name}`Env.default` is {name}`Output.unmodeled` with the reason {name}`clockUnmodeled`, which a
statement that reads the clock gives in a run without a clock, and none ends at an unknown counter
({name}`Output.endsAtUnknownCounter`), which a statement that calls a counter function gives when the
run does not know the counter, the run in the environment is the run under {name}`Env.default`: the
same value, outputs, databases, transaction and settings. Proof sketch: the runs from the counters
of the environment and from unknown counters have the same outputs ({name}`Sql.runFrom_counters`), so
the clock does not change the run from the counters of the environment ({name}`Sql.runFrom_env`);
the checked runs follow ({name}`Run.checked_congr`). -/
theorem Sql.run_env {α : Type} (program : Sql α) (db : Database) (env : Env)
    (clockFree : Output.unmodeled clockUnmodeled ∉ (program.run db).outputs)
    (countersKnown : ∀ output ∈ (program.run db).outputs, output.endsAtUnknownCounter = false) :
    program.run db env = program.run db := by
  have lessKnown : (db.raw.connection {}).LessKnown (db.raw.connection env.counters) :=
    ⟨⟨rfl, rfl, rfl, Or.inl rfl, Or.inl rfl, Or.inl rfl⟩, rfl, rfl⟩
  have counters := Sql.runFrom_counters program none 0 lessKnown
    (fun output member => countersKnown output (Run.mem_checked_outputs member))
  have clock := Sql.runFrom_env program env.clock 0 (db.raw.connection env.counters) (by
    rw [← counters.1]
    exact fun member => clockFree (Run.mem_checked_outputs member))
  obtain ⟨sameOutputs, sameValue, ⟨sameDatabase, sameSnapshot, _, _⟩, sameForeign, sameRecursive⟩ := counters
  unfold Sql.run
  rw [clock]
  exact Run.checked_congr db sameOutputs.symm sameValue.symm sameDatabase.symm sameSnapshot.symm
    sameForeign.symm sameRecursive.symm

/-- {lit}`Script.run_env`: for every script, database and environment, if no output of the run of
the script under {name}`Env.default` is {name}`Output.unmodeled` with the reason
{name}`clockUnmodeled`, which a statement that reads the clock gives in a run without a clock,
and none ends at an unknown counter ({name}`Output.endsAtUnknownCounter`), the run in the
environment is the run under {name}`Env.default`. The hypotheses are about the run, because
whether a statement reads the clock depends on its resolution: a date function of a column or of a
parameter reads it. Proof sketch: {name}`Sql.run_env` of the program {name}`send`. -/
theorem Script.run_env (script : Script) (db : Database) (env : Env)
    (clockFree : Output.unmodeled clockUnmodeled ∉ (db.run script).outputs)
    (countersKnown : ∀ output ∈ (db.run script).outputs, output.endsAtUnknownCounter = false) :
    db.run script env = db.run script :=
  Sql.run_env (send script) db env clockFree countersKnown

end Belay.Sqlite
