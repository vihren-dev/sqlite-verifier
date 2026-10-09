import Belay.Sqlite.SqlExecution

set_option doc.verso true

/-! Schema-only proof laws for the full SQL executor. Keeping these guarded
conveniences separate leaves the statement and transaction semantics in one module. -/

namespace Belay.Sqlite

/-- Every statement in the script is CREATE TABLE or ADD COLUMN. This is a syntax
guard, not a validity or success claim. The empty script satisfies it; transaction
control and literal writes do not. Use it for schema preservation laws. -/
def SchemaOnly (script : List Statement) : Prop :=
  ∀ statement ∈ script, match statement with
    | .createTable .. | .addColumn .. => True
    | .beginTransaction => False
    | .commit => False
    | .rollback => False
    | .insert .. => False
    | .update .. => False

/-- For every position and connection state, a {name}`SchemaOnly` script passes
the reached-statement data-domain check. Schema/index admission remains a separate
obligation. The proof inducts over the script and follows each actual transition. -/
theorem supportedSqlFrom_schemaOnly (guard : SchemaOnly script) :
    supportedSqlFrom position script state = true := by
  induction script generalizing position state with
  | nil => rfl
  | cons statement rest ih =>
    have first := guard statement (by simp)
    have tail : SchemaOnly rest := fun item member => guard item (by simp [member])
    have ready : statementReady statement state.database = true := by
      cases statement <;> simp_all [statementReady]
    simp only [supportedSqlFrom, ready, Bool.true_and]
    cases advance position statement state with
    | halt outcome => rfl
    | next next => exact ih tail

/-- For every position and idle database, a guarded schema statement uses the
primitive transition. The proof splits on the statement and uses the guard to
exclude transaction control and literal-write constructors. -/
theorem advance_schemaOnly
    (guard : SchemaOnly [statement]) :
    advance position statement { database := database } =
      match step statement database position with
      | .success result => .next { database := result }
      | outcome => .halt outcome := by
  have first := guard statement (by simp)
  cases statement <;> simp_all [advance, literalStep, SqlState.finish]
  all_goals rfl

/-- For every idle starting database and position, appending a suffix to a
{name}`SchemaOnly` prefix resumes at its next position after success and retains
its stopped error otherwise. The prefix cannot open a transaction. This law does
not describe transaction prefixes; their EOF pending state must be resumed with
its committed snapshot. The proof inducts over primitive schema transitions. -/
theorem runSqlFrom_schemaOnly_append (guard : SchemaOnly initial) :
    runSqlFrom position (initial ++ suffix) { database := database } =
      match runSqlFrom position initial { database := database } with
      | .success result => runSqlFrom (position + initial.length) suffix { database := result }
      | .failure index reason result => .failure index reason result
      | .pending persisted visible error => .pending persisted visible error := by
  induction initial generalizing database position with
  | nil => simp [runSqlFrom, SqlState.finish]
  | cons statement rest ih =>
    have first : SchemaOnly [statement] := fun item member => by
      simp only [List.mem_singleton] at member
      subst item
      exact guard statement (by simp)
    have tail : SchemaOnly rest := fun item member => guard item (by simp [member])
    simp only [List.cons_append, runSqlFrom, advance_schemaOnly first]
    cases executed : step statement database position with
    | failure index reason result => rfl
    | pending persisted visible error => rfl
    | success result => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        (ih tail (database := result) (position := position + 1))

/-!
```lean
example : Belay.Sqlite.SchemaOnly [] := by
  intro statement member
  simp at member
example : ¬ Belay.Sqlite.SchemaOnly [Belay.Sqlite.Statement.beginTransaction] := by
  intro guard
  exact guard .beginTransaction (by simp)
```
-/

end Belay.Sqlite
