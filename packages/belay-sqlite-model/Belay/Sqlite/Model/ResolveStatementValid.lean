import Belay.Sqlite.Model.ResolveAddColumnCatalog
import Belay.Sqlite.Model.Resolution.NamesSpec

set_option doc.verso true

/-! Resolution keeps the catalog valid (ADR 0022, D3, slice 4): for a valid catalog, every statement
that {lit}`resolveStatement` resolves gives a valid catalog, and so does the catalog that an open
transaction saved. A script that resolves from a valid catalog ends with a valid catalog. These are the
resolver facts of the atom {lit}`Catalog.Valid`. -/

namespace Belay.Sqlite.Model

/-- The resolution state is valid under the limits: the current catalog is valid
({name}`Catalog.Valid`), and so is the catalog that an open transaction saved, if there is one. -/
def ResolveState.Valid (limits : Limits) (state : ResolveState) : Prop :=
  state.catalog.Valid limits ∧ ∀ saved, state.saved = some saved → saved.Valid limits

/-- For every context in execution mode, state and statement: if
* the state is valid under the limits of the profile of the context
  ({name}`ResolveState.Valid`);
* the statement resolves to a resolved statement and a next state;

then the next state is valid under the same limits. Proof sketch:
BEGIN, COMMIT and ROLLBACK only copy valid catalogs, and a pragma keeps them
({name}`resolvePragma_cases`). CREATE, DROP and ADD COLUMN give a valid catalog by their own facts
({name}`resolveCreateTable_valid`, {name}`resolveCreateIndex_valid`, {name}`resolveCreateTrigger_valid`,
{name}`resolveAddColumn_valid`, {name}`resolveDropTable_valid`, {name}`resolveDropIndex_valid`,
{name}`resolveDropTrigger_valid`). A write and a query keep the catalog
({name}`ResolveState.withWrite_cases`). -/
theorem resolveStatement_valid (context : ResolveContext) (state next : ResolveState)
    (statement : Syntax.Statement) (resolved : Resolved.Statement)
    (execution : context.mode = .execution) (valid : state.Valid context.profile.limits)
    (ok : resolveStatement context state statement = .ok (resolved, next)) :
    next.Valid context.profile.limits := by
  obtain ⟨current, saved⟩ := valid
  have keep : ∀ after, after.Valid context.profile.limits →
      ({ state with catalog := after } : ResolveState).Valid context.profile.limits :=
    fun after valid => ⟨valid, saved⟩
  have written : ∀ result, state.withWrite context result = .ok (resolved, next) →
      (∀ statement after, result = .ok (statement, after) → after.Valid context.profile.limits) →
      next.Valid context.profile.limits := by
    intro result ok step
    rcases ResolveState.withWrite_cases ok with ⟨_, _, rfl⟩ | ⟨statement, after, rfl, rfl, _, _⟩
    · exact ⟨current, saved⟩
    · exact keep _ (step statement after rfl)
  cases statement with
  | begin =>
    cases ok
    refine ⟨current, fun copy h => ?_⟩
    cases hsaved : state.saved <;> simp [hsaved] at h <;> subst h
    · exact current
    · exact saved _ hsaved
  | commit => cases ok; exact ⟨current, by simp⟩
  | rollback =>
    cases ok
    refine ⟨?_, by simp⟩
    cases hsaved : state.saved
    · simpa [hsaved] using current
    · simpa [hsaved] using saved _ hsaved
  | createTable name columns constraints options =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateTable_valid _ _ _ _ _ _ _ _ current execution (by assumption))
  | createIndex name unique table terms filter =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateIndex_valid _ _ _ _ _ _ _ _ _ current (by assumption))
  | addColumn table column =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveAddColumn_valid _ _ _ _ _ _ current (by assumption))
  | dropTable name ifExists =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => resolveDropTable_valid _ _ _ _ _ _ current found
  | dropIndex name ifExists =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveDropIndex_valid _ _ _ _ _ _ current (by assumption))
  | createTrigger name ifNotExists time event table condition body =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateTrigger_valid _ _ _ _ _ _ _ current (by assumption))
  | dropTrigger name ifExists =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveDropTrigger_valid _ _ _ _ _ _ current (by assumption))
  | insert table columns rows conflicts algorithm returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => (resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveInsert_same _ _ _ _ _ _ _ _ _ _ _ _ h) found).1 ▸ current
  | update table assignments filter returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => (resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveUpdate_same _ _ _ _ _ _ _ _ _ _ h) found).1 ▸ current
  | delete table filter returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => (resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveDelete_same _ _ _ _ _ _ _ _ _ h) found).1 ▸ current
  | pragma pragma =>
    rcases resolvePragma_cases ok with ⟨setting, _, _, rfl⟩ | ⟨rfl, _, _⟩
    · cases setting <;> exact ⟨current, saved⟩
    · exact ⟨current, saved⟩
  | select results source joins filter groupBy orderBy limit offset subqueries having distinct =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ ((resolveSelect_same _ _ _ _ _ _ (by assumption)).1 ▸ current)

/-- For every context in execution mode, valid starting catalog and script that resolves: the catalog
after the script is valid under the limits of the profile of the context. Proof sketch: induction over
the script with {name}`resolveStatement_valid`; the starting state has no saved catalog. -/
theorem resolve_valid (context : ResolveContext) (catalog after : Catalog) (script : List Syntax.Statement)
    (statements : List Resolved.Statement) (execution : context.mode = .execution)
    (valid : catalog.Valid context.profile.limits)
    (ok : resolve context catalog script = .resolved statements after) :
    after.Valid context.profile.limits := by
  have general : ∀ (script : List Syntax.Statement) index (state final : ResolveState) statements,
      state.Valid context.profile.limits → resolveFrom context index state script = .ok (statements, final) →
      final.Valid context.profile.limits := by
    intro script
    induction script with
    | nil => intro index state final statements valid ok; cases ok; exact valid
    | cons statement rest ih =>
      intro index state final statements valid ok
      simp only [resolveFrom, bind, Except.bind] at ok
      split at ok <;> try contradiction
      rename_i first hfirst
      split at ok <;> try contradiction
      rename_i later hlater
      cases ok
      exact ih _ _ _ _ (resolveStatement_valid _ _ _ _ _ execution valid hfirst) hlater
  unfold resolve at ok
  split at ok <;> try contradiction
  rename_i result hresult
  cases ok
  exact (general _ _ _ _ _ ⟨valid, by simp [ResolveState.initial]⟩ hresult).1

end Belay.Sqlite.Model
