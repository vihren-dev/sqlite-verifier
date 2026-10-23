import Belay.Sqlite.Model.ScriptRunIndex

set_option doc.verso true

/-! The run of two scripts one after the other ({lit}`ScriptRun.lean`): the run of {lit}`p ++ q`
is the run of {lit}`p`, then the run of {lit}`q` from the connection that {lit}`p` left, unless
the run of {lit}`p` ends with {name}`Belay.Sqlite.Model.Output.unmodeled`. When the run has no
clock, or a clock that gives the same value at every index, the run of {lit}`q` is the same from
every index ({lit}`ScriptRunIndex.lean`), so it is the run of {lit}`q` on its own. -/

namespace Belay.Sqlite.Model

/-- For every context, optional clock, index, connection and statements with values, the
connection at the end of the run ({name}`runScriptFrom`) has the clock assignment of the
connection at its start. Proof sketch: induction on the statements; each step that continues
keeps the clock assignment ({name}`runScriptStep_continued`). -/
theorem runScriptFrom_clock (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statements : List (Syntax.Statement × List Value)) :
    (runScriptFrom context clock index connection statements).connection.state.clock = connection.state.clock := by
  induction statements generalizing index connection with
  | nil => rfl
  | cons entry rest later =>
    simp only [runScriptFrom]
    split
    · rfl
    · rename_i output next continued
      rw [later, (runScriptStep_continued continued).1]

/-- For every context, optional clock, two indexes, connection and statements with values: if
the clock, when the run has one, gives the same value at every index, the run from the first
index is the run from the second. Proof sketch: induction on the statements; each step is the
same at both indexes ({name}`runScriptStep_index`). -/
theorem runScriptFrom_index (context : ResolveContext) (clock : Option Clock) (first second : Nat)
    (connection : Connection) (statements : List (Syntax.Statement × List Value))
    (constant : ∀ assignment ∈ clock, ∀ one other, assignment one = assignment other) :
    runScriptFrom context clock first connection statements =
      runScriptFrom context clock second connection statements := by
  induction statements generalizing first second connection with
  | nil => rfl
  | cons entry rest later =>
    obtain ⟨statement, parameters⟩ := entry
    simp only [runScriptFrom, runScriptStep_index context clock first second connection statement parameters
      (fun assignment member => constant assignment member _ _)]
    split
    · rfl
    · rw [later (first + 1) (second + 1)]

/-- Whether the run ended at a statement that the model does not describe: one of its outputs
ends the run ({name}`Output.endsRun`). For example, {assert}`!({ outputs := [], connection :=
{ state := { database := {} } } } : ScriptRun).ended`. -/
def ScriptRun.ended (run : ScriptRun) : Bool := run.outputs.any Output.endsRun

/-- The run, then the later run from the connection at its end, unless the run ended
({name}`ScriptRun.ended`): the outputs of both, and the later run's connection. -/
def ScriptRun.andThen (run : ScriptRun) (later : Connection → ScriptRun) : ScriptRun :=
  if run.ended then run
  else
    let next := later run.connection
    { outputs := run.outputs ++ next.outputs, connection := next.connection }

/-- For every context, optional clock, index, connection and statements with values {lit}`p`
and {lit}`q`: the run of {lit}`p ++ q` from the index is the run of {lit}`p`, then
({name}`ScriptRun.andThen`) the run of {lit}`q` from the index after {lit}`p`, on the connection
that {lit}`p` left, with the same clock. When the run of {lit}`p` ends with
{name}`Output.unmodeled`, it is the run of {lit}`p` alone. Proof sketch: induction on {lit}`p`;
a step that continues gives an output that does not end the run
({name}`runScriptStep_continued`), so the run after it ends exactly when the rest does. -/
theorem runScriptFrom_append (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (p q : List (Syntax.Statement × List Value)) :
    runScriptFrom context clock index connection (p ++ q) =
      (runScriptFrom context clock index connection p).andThen
        (runScriptFrom context clock (index + p.length) · q) := by
  induction p generalizing index connection with
  | nil => simp [runScriptFrom, ScriptRun.andThen, ScriptRun.ended]
  | cons entry rest later =>
    simp only [List.cons_append, runScriptFrom]
    split
    · simp [ScriptRun.andThen, ScriptRun.ended, Output.endsRun]
    · rename_i output next continued
      have quiet := (runScriptStep_continued continued).2
      rw [later (index + 1) next]
      simp only [ScriptRun.andThen, ScriptRun.ended, List.any_cons, quiet, Bool.false_or, List.length_cons,
        Nat.add_assoc, Nat.add_comm 1 rest.length]
      split <;> rfl

/-- For every context, optional clock, index, connection and statements with values {lit}`p`
and {lit}`q`: if the clock, when the run has one, gives the same value at every index, the run
of {lit}`p ++ q` from the index is the run of {lit}`p`, then ({name}`ScriptRun.andThen`) the run
of {lit}`q` from index 0 with the same clock, on the connection that {lit}`p` left. A run
without a clock satisfies the hypothesis. Proof sketch: {name}`runScriptFrom_append`, and the
run of {lit}`q` does not depend on its index ({name}`runScriptFrom_index`). -/
theorem runScriptFrom_append_constant (context : ResolveContext) (clock : Option Clock) (index : Nat)
    (connection : Connection) (p q : List (Syntax.Statement × List Value))
    (constant : ∀ assignment ∈ clock, ∀ one other, assignment one = assignment other) :
    runScriptFrom context clock index connection (p ++ q) =
      (runScriptFrom context clock index connection p).andThen (runScriptFrom context clock 0 · q) := by
  rw [runScriptFrom_append]
  simp only [ScriptRun.andThen]
  split
  · rfl
  · rw [runScriptFrom_index context clock (index + p.length) 0 _ q constant]

end Belay.Sqlite.Model
