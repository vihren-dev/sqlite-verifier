import Belay.Sqlite.Model.StepCatalogLaws
import Belay.Sqlite.Model.Resolution.ResolveFoldSpec

set_option doc.verso true

/-! Resolution and execution agree on the catalog. Resolution predicts the catalog after a
script ({lit}`resolve`); execution carries a catalog in its state and changes it with the
same functions. The final theorem {lit}`runSqlAt_catalog` states that a run without an
error ends with the catalog that resolution predicts. -/

namespace Belay.Sqlite.Model

/-- For every script of statements with values, position, agreeing connection and resolution
states, and outcome of {name}`runSqlFrom` without an error (a success, or a pending transaction
without an error): the catalog of the outcome's visible database is the catalog of the fold of
{name}`ResolveState.after` over the statements of the script. An outcome with an error is not covered. Proof
sketch: induction on the script; a halt has an error ({name}`advance_halt_error`), and a
continuing step keeps the states in agreement ({name}`advance_agrees`). -/
theorem runSqlFrom_agrees :
    ∀ (script : List (Resolved.Statement × List Value)) (position : Nat) (sql : SqlState) (state : ResolveState),
      sql.Agrees state → ∀ outcome, runSqlFrom position script sql = outcome → outcome.error? = none →
      outcome.database.catalog = ((script.map (·.1)).foldl ResolveState.after state).catalog
  | [], position, sql, state, agrees, outcome, run, clean => by
    simp only [runSqlFrom] at run
    subst run
    cases h : sql.snapshot <;> simp [SqlState.finish, h, Outcome.database, agrees.1]
  | (statement, _) :: rest, position, sql, state, agrees, outcome, run, clean => by
    simp only [runSqlFrom] at run
    split at run
    · rename_i halted _ halt
      subst run
      have := advance_halt_error halt
      simp [clean] at this
    · rename_i next continued
      exact runSqlFrom_agrees rest (position + 1) next (state.after statement) (advance_agrees agrees continued)
        outcome run clean

/-- Resolution and execution give the same catalog (ADR 0013, D1). For every context,
catalog, script, resolved statements and resulting catalog of a successful
{name}`resolve`, every database whose catalog is the starting catalog, every list of values of
the statements ({name}`bindValues`) and every clock assignment: if {name}`runSqlAt` gives an outcome without an error (a success, or a pending
transaction without an error), its visible database's catalog is the resulting catalog of
resolution. An outcome with an error is not covered. Proof sketch: resolution's catalog is
the fold of {name}`ResolveState.after` ({name}`resolve_after`), and execution follows it
({name}`runSqlFrom_agrees`); the clock assignment is not part of the agreement. -/
theorem runSqlAt_catalog {context : ResolveContext} {catalog next : Catalog} {script : List Syntax.Statement}
    {resolved : List Resolved.Statement} {database : Database} (clock : Clock)
    (resolution : resolve context catalog script = .resolved resolved next) (start : database.catalog = catalog)
    (values : List (List Value)) (clean : (runSqlAt clock (bindValues resolved values) database).error? = none) :
    (runSqlAt clock (bindValues resolved values) database).database.catalog = next := by
  rw [resolve_after context catalog next script resolved resolution]
  have statements := runSqlFrom_agrees _ 0 { database, clock := scriptClock clock ((bindValues resolved values).map (·.1)) }
    (ResolveState.initial context.profile catalog) ⟨start, rfl⟩ _ rfl clean
  simpa only [runSqlAt, map_fst_bindValues] using statements

end Belay.Sqlite.Model
