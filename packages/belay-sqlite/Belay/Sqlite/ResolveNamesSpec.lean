import Belay.Sqlite.ResolveCatalogSpec

set_option doc.verso true

/-! The unique-names rule for resolution: each statement changes the catalog by one
{name}`Belay.Sqlite.CatalogStep`, so unique folded names stay unique. -/

namespace Belay.Sqlite

/-- For every successful resolution of CREATE TABLE, the catalog changes by one
{name}`CatalogStep`: it is unchanged after a prepare error, and otherwise gets one
table whose name {name}`Catalog.find` does not find. -/
theorem resolveCreateTable_step (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (name : String) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (statement : Resolved.Statement)
    (ok : resolveCreateTable context catalog index name columns constraints = .ok (statement, after)) :
    CatalogStep catalog after := by
  unfold resolveCreateTable at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .same)
    | (cases ok; exact .append _ (by assumption))
    | (cases ok)

/-- For every successful resolution of CREATE INDEX, the catalog changes by one
{name}`CatalogStep`: unchanged after a prepare error, else one appended index whose
name {name}`Catalog.find` does not find. -/
theorem resolveCreateIndex_step (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (name : String) (unique : Bool) (tableName : String) (columns : List String)
    (statement : Resolved.Statement)
    (ok : resolveCreateIndex context catalog index name unique tableName columns = .ok (statement, after)) :
    CatalogStep catalog after := by
  unfold resolveCreateIndex at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .same)
    | (cases ok; exact .append _ (by assumption))
    | (cases ok)

/-- For every successful resolution of ADD COLUMN, the catalog changes by one
{name}`CatalogStep`: unchanged after a prepare error, else the table's object gets a
new entry and keeps its name. -/
theorem resolveAddColumn_step (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (definition : Syntax.ColumnDefinition) (statement : Resolved.Statement)
    (ok : resolveAddColumn context catalog index tableName definition = .ok (statement, after)) :
    CatalogStep catalog after := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .same)
    | (cases ok; done)
    | cases ok
  rename_i position table found _ _ _ _ _ _ _ _ _
  obtain ⟨object, at_, _, _⟩ := Catalog.findTable_some _ _ _ _ found
  simp only [at_, Option.map_some, Option.getD_some]
  exact .replace position object _ at_

/-- For every successful resolution of INSERT, the catalog is unchanged. -/
theorem resolveInsert_same (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (names : Option (List String)) (rows : List (List Syntax.Expr))
    (statement : Resolved.Statement)
    (ok : resolveInsert context catalog index tableName names rows = .ok (statement, after)) :
    after = catalog := by
  unfold resolveInsert at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | (cases ok)

/-- For every successful resolution of UPDATE, the catalog is unchanged. -/
theorem resolveUpdate_same (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (assignments : List (String × Syntax.Expr)) (filter : Option Syntax.Expr)
    (statement : Resolved.Statement)
    (ok : resolveUpdate context catalog index tableName assignments filter = .ok (statement, after)) :
    after = catalog := by
  unfold resolveUpdate at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | (cases ok)

/-- The resolution state keeps unique names: the current catalog has unique folded
names, and so does the catalog that an open transaction saved, if there is one. -/
def ResolveState.NamesUnique (state : ResolveState) : Prop :=
  state.catalog.NamesUnique ∧ ∀ saved, state.saved = some saved → saved.NamesUnique

/-- The unique-names rule ({lit}`lang_createtable.html`, R-01232-54838): for every
context, state, index and statement, if the state's catalogs have unique folded names
and the statement resolves, then the next state's catalogs have unique folded names.
Proof sketch: BEGIN, COMMIT and ROLLBACK only copy catalogs that have unique names;
every other statement changes the catalog by one {name}`CatalogStep`. -/
theorem resolveStatement_namesUnique (context : ResolveContext) (state next : ResolveState)
    (index : Nat) (statement : Syntax.Statement) (resolved : Resolved.Statement)
    (unique : state.NamesUnique)
    (ok : resolveStatement context state index statement = .ok (resolved, next)) :
    next.NamesUnique := by
  obtain ⟨current, saved⟩ := unique
  have keep : ∀ after, CatalogStep state.catalog after →
      ({ state with catalog := after } : ResolveState).NamesUnique :=
    fun after step => ⟨step.namesUnique current, saved⟩
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
  | createTable name columns constraints =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateTable_step _ _ _ _ _ _ _ _ (by assumption))
  | createIndex name unique table columns =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateIndex_step _ _ _ _ _ _ _ _ _ (by assumption))
  | addColumn table column =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveAddColumn_step _ _ _ _ _ _ _ (by assumption))
  | insert table columns rows =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveInsert_same _ _ _ _ _ _ _ _ (by assumption) ▸ .same)
  | update table assignments filter =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveUpdate_same _ _ _ _ _ _ _ _ (by assumption) ▸ .same)

/-- For every context, starting catalog and script with a successful resolution: if
the starting catalog has unique folded names, so does the resulting catalog.
Proof sketch: induction on the script with {name}`resolveStatement_namesUnique`. -/
theorem resolve_namesUnique (context : ResolveContext) (catalog after : Catalog)
    (script : List Syntax.Statement) (statements : List Resolved.Statement)
    (unique : catalog.NamesUnique)
    (ok : resolve context catalog script = .resolved statements after) : after.NamesUnique := by
  have general : ∀ (script : List Syntax.Statement) index (state final : ResolveState) statements,
      state.NamesUnique → resolveFrom context index state script = .ok (statements, final) →
      final.NamesUnique := by
    intro script
    induction script with
    | nil => intro index state final statements unique ok; cases ok; exact unique
    | cons statement rest ih =>
      intro index state final statements unique ok
      simp only [resolveFrom, bind, Except.bind] at ok
      split at ok <;> try contradiction
      rename_i first hfirst
      split at ok <;> try contradiction
      rename_i later hlater
      cases ok
      exact ih _ _ _ _ (resolveStatement_namesUnique _ _ _ _ _ _ unique hfirst) hlater
  unfold resolve at ok
  split at ok <;> try contradiction
  rename_i result hresult
  cases ok
  exact (general _ _ _ _ _ ⟨unique, by simp⟩ hresult).1

end Belay.Sqlite
