import Belay.Sqlite.Resolve

set_option doc.verso true

/-! The transaction rule of resolution: after ROLLBACK, the catalog equals the
catalog at the matching BEGIN. -/

namespace Belay.Sqlite

/-- Whether a statement is BEGIN, COMMIT or ROLLBACK. -/
def Syntax.Statement.transactionControl : Syntax.Statement → Bool
  | .begin | .commit | .rollback => true
  | .createTable .. | .createIndex .. | .addColumn .. | .insert .. | .update .. => false

/-- For every statement that is not BEGIN, COMMIT or ROLLBACK and that resolves, the
saved catalog of the next state is the saved catalog of the state. -/
theorem resolveStatement_saved (context : ResolveContext) (state next : ResolveState) (index : Nat)
    (statement : Syntax.Statement) (resolved : Resolved.Statement)
    (plain : statement.transactionControl = false)
    (ok : resolveStatement context state index statement = .ok (resolved, next)) :
    next.saved = state.saved := by
  cases statement <;> simp [Syntax.Statement.transactionControl] at plain <;>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok <;>
    split at ok <;> cases ok <;> rfl

/-- For every list of statements without BEGIN, COMMIT or ROLLBACK that resolves, the
saved catalog of the final state is the saved catalog of the first state. -/
theorem resolveFrom_saved (context : ResolveContext) (statements : List Syntax.Statement)
    (plain : ∀ statement ∈ statements, statement.transactionControl = false) :
    ∀ index (state final : ResolveState) resolved,
      resolveFrom context index state statements = .ok (resolved, final) → final.saved = state.saved := by
  induction statements with
  | nil => intro index state final resolved ok; cases ok; rfl
  | cons statement rest ih =>
    intro index state final resolved ok
    simp only [resolveFrom, bind, Except.bind] at ok
    split at ok <;> try contradiction
    rename_i first hfirst
    split at ok <;> try contradiction
    rename_i later hlater
    cases ok
    rw [ih (fun s h => plain s (List.mem_cons_of_mem _ h)) _ _ _ _ hlater,
      resolveStatement_saved _ _ _ _ _ _ (plain _ List.mem_cons_self) hfirst]

/-- For every list of statements without BEGIN, COMMIT or ROLLBACK, followed by
ROLLBACK, from a state whose saved catalog is the given catalog: if the list resolves,
the final catalog is the given catalog and no transaction is open. Proof sketch:
induction on the list; each statement keeps the saved catalog
({name}`resolveStatement_saved`), and ROLLBACK restores it. -/
theorem resolveFrom_rollback (context : ResolveContext) (saved : Catalog) (statements : List Syntax.Statement)
    (plain : ∀ statement ∈ statements, statement.transactionControl = false) :
    ∀ index (state final : ResolveState) resolved, state.saved = some saved →
      resolveFrom context index state (statements ++ [.rollback]) = .ok (resolved, final) →
      final.catalog = saved ∧ final.saved = none := by
  induction statements with
  | nil =>
    intro index state final resolved open_ ok
    simp only [List.nil_append, resolveFrom, resolveStatement, open_, Option.getD_some, bind,
      Except.bind, pure, Except.pure] at ok
    cases ok
    exact ⟨rfl, rfl⟩
  | cons statement rest ih =>
    intro index state final resolved open_ ok
    simp only [List.cons_append, resolveFrom, bind, Except.bind] at ok
    split at ok <;> try contradiction
    rename_i first hfirst
    split at ok <;> try contradiction
    rename_i later hlater
    cases ok
    have keeps := resolveStatement_saved _ _ _ _ _ _ (plain _ List.mem_cons_self) hfirst
    exact ih (fun s h => plain s (List.mem_cons_of_mem _ h)) _ _ _ _ (keeps.trans open_) hlater

/-- The transaction rule ({lit}`lang_transaction.html`): for every context, index and
state outside a transaction, and every list of statements without BEGIN, COMMIT or
ROLLBACK: if BEGIN, those statements and ROLLBACK resolve, the final catalog equals
the state's catalog and no transaction is open. Proof sketch: BEGIN saves the
catalog, and {name}`resolveFrom_rollback` restores it at ROLLBACK. -/
theorem resolve_rollback_restores (context : ResolveContext) (index : Nat) (state final : ResolveState)
    (statements : List Syntax.Statement) (resolved : List Resolved.Statement)
    (idle : state.saved = none) (plain : ∀ statement ∈ statements, statement.transactionControl = false)
    (ok : resolveFrom context index state (.begin :: statements ++ [.rollback]) = .ok (resolved, final)) :
    final.catalog = state.catalog ∧ final.saved = none := by
  simp only [List.cons_append, resolveFrom, resolveStatement, idle, Option.getD_none, bind,
    Except.bind] at ok
  split at ok <;> try contradiction
  rename_i later hlater
  cases ok
  exact resolveFrom_rollback _ _ _ plain _ _ _ _ rfl hlater

end Belay.Sqlite
