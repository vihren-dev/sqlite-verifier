import VerifierConformance.RunPass

set_option doc.verso true

/-! The law that makes the evidence of the pass that continues evidence for the model's run
({name}`Belay.Sqlite.Model.runScriptFrom`). It is a module apart from
{name}`Belay.Sqlite.Model.Conformance.runPassFrom`, so that the classifier of the cases does not
import it: a mutant copy of the model ({lit}`conformance.resolve_mutants`) then builds also when
the mutant breaks this proof. -/

namespace Belay.Sqlite.Model.Conformance

/-- For every context, optional clock, index, connection and list of statements with values:
the results of the pass ({name}`runPassFrom`) are the outputs of the model's run
({name}`runScriptFrom`) with the same arguments. So a verdict that compares the pass with
SQLite compares the run of the model. Proof sketch: induction on the statements; both take
{name}`runScriptStepWith` with {name}`ranScriptStep`, end with
the same {name}`Output.unmodeled`, or give the same output and go on from the same connection. -/
theorem runPassFrom_results (context : ResolveContext) (clock : Option Clock) :
    ∀ (index : Nat) (connection : Connection) (script : List (Syntax.Statement × List Value)),
      (runPassFrom context clock index connection script).results =
        (runScriptFrom context clock index connection script).outputs
  | _, _, [] => rfl
  | index, connection, (statement, parameters) :: rest => by
    simp only [runPassFrom, runScriptFrom, runScriptStep, runScriptStepWith]
    split
    · rfl
    · split
      · rfl
      · split
        · rfl
        · split
          · rfl
          · cases ranScriptStep parameters connection _ _ _ _ _ with
            | ended reason => rfl
            | continued output next => simp [runPassFrom_results context clock (index + 1) next rest]

end Belay.Sqlite.Model.Conformance
