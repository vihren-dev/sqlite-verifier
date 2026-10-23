import Belay.Sqlite.Model.Resolution.ResolveStateSpec

set_option doc.verso true

/-! The resolution state after a script: the fold of {name}`Belay.Sqlite.Model.ResolveState.after`
over its resolved statements, from {name}`Belay.Sqlite.Model.resolveStatement_after`.
{lit}`CatalogAgreement` uses it for the catalog of a script. -/

namespace Belay.Sqlite.Model

/-- For every context, script, index and state with a successful resolution, the final
state is the fold of {name}`ResolveState.after` over the resolved statements. Proof
sketch: induction on the script with {name}`resolveStatement_after`. -/
theorem resolveFrom_after (context : ResolveContext) :
    ∀ (script : List Syntax.Statement) (index : Nat) (state final : ResolveState)
      (resolved : List Resolved.Statement),
      resolveFrom context index state script = .ok (resolved, final) →
      final = resolved.foldl ResolveState.after state
  | [], index, state, final, resolved, ok => by
    simp only [resolveFrom] at ok
    cases ok
    rfl
  | statement :: rest, index, state, final, resolved, ok => by
    simp only [resolveFrom, bind, Except.bind] at ok
    split at ok
    · cases ok
    · rename_i head next headOk
      split at ok
      · cases ok
      · rename_i later restOk
        simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at ok
        obtain ⟨rfl, rfl⟩ := ok
        have head := resolveStatement_after context state next statement head headOk
        have tail := resolveFrom_after context rest (index + 1) next later.2 later.1 restOk
        rw [List.foldl_cons, ← head]
        exact tail

/-- For every context, catalog and script with a successful resolution, the resulting
catalog is the catalog of the fold of {name}`ResolveState.after` over the resolved
statements from the catalog outside a transaction, with the profile's settings of foreign keys
and recursive triggers.
Proof sketch: unfold {name}`resolve`; a restriction contradicts the premise, and a resolution
is the state of {name}`resolveFrom_after` from position zero outside a transaction. -/
theorem resolve_after (context : ResolveContext) (catalog next : Catalog) (script : List Syntax.Statement)
    (resolved : List Resolved.Statement) (ok : resolve context catalog script = .resolved resolved next) :
    next = (resolved.foldl ResolveState.after (ResolveState.initial context.profile catalog)).catalog := by
  unfold resolve at ok
  split at ok
  · rename_i result found
    cases ok
    rw [resolveFrom_after context script 0 _ _ _ found]
  · cases ok

end Belay.Sqlite.Model
