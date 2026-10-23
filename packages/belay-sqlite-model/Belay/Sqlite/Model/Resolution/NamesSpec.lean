import Belay.Sqlite.Model.Resolution.DropSpec
import Belay.Sqlite.Model.Resolution.WriteCatalogSpec
import Belay.Sqlite.Model.Resolution.TriggerDefinitionSpec

set_option doc.verso true

/-! The unique-names rule for resolution: each statement changes the catalog by one
{name}`Belay.Sqlite.Model.CatalogStep`, so unique folded names stay unique. -/

namespace Belay.Sqlite.Model

/-- For every successful resolution of CREATE TABLE, the catalog changes by one
{name}`CatalogStep`: it is unchanged after a prepare error, and otherwise gets one
table whose name {name}`Catalog.find` does not find. Proof sketch: split every branch
of the resolver; each prepare error returns the catalog, and the only branch that
appends is the one where {name}`Catalog.find` found nothing. -/
theorem resolveCreateTable_step (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (options : Syntax.TableOptions) (statement : Resolved.Statement)
    (ok : resolveCreateTable context catalog name columns constraints options = .ok (statement, after)) :
    CatalogStep catalog after := by
  unfold resolveCreateTable at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .same)
    | (cases ok; exact .append _ (by assumption))
    | (exact absurd (Catalog.find_not_trigger _ _ _ _ (by assumption)) (by simp [CatalogObject.isTrigger,
        CatalogEntry.isTrigger]))
    | (cases ok)

/-- For every successful resolution of CREATE INDEX, the catalog changes by one
{name}`CatalogStep`: unchanged after a prepare error, else one appended index whose
name {name}`Catalog.find` does not find. Proof sketch: as for CREATE TABLE, split
every branch; only the branch where the name is unused appends. -/
theorem resolveCreateIndex_step (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (unique : Bool) (tableName : Identifier) (terms : List Syntax.OrderTerm)
    (filter : Option Syntax.Expr)
    (statement : Resolved.Statement)
    (ok : resolveCreateIndex context catalog name unique tableName terms filter = .ok (statement, after)) :
    CatalogStep catalog after := by
  unfold resolveCreateIndex at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .same)
    | (cases ok; exact .append _ (by assumption))
    | (exact absurd (Catalog.find_not_trigger _ _ _ _ (by assumption)) (by simp [CatalogObject.isTrigger,
        CatalogEntry.isTrigger]))
    | (cases ok)

/-- For every successful resolution of ADD COLUMN, the catalog changes by one
{name}`CatalogStep`: unchanged after a prepare error, else the table's object gets a
new entry and keeps its name. Proof sketch: split every branch; the successful branch
replaces the object that {name}`Catalog.findTable_some` gives at the table's position. -/
theorem resolveAddColumn_step (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (definition : Syntax.ColumnDefinition) (statement : Resolved.Statement)
    (ok : resolveAddColumn context catalog tableName definition = .ok (statement, after)) :
    CatalogStep catalog after := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; exact .same)
    | (cases ok; done)
    | cases ok
  obtain ⟨object, atPosition, _, _⟩ := Catalog.findTable_some _ _ _ _ (by assumption)
  obtain ⟨name, entry⟩ := object
  cases (by assumption : entry = .table _)
  simp only [Catalog.addColumn, atPosition]
  exact .replace _ _ _ atPosition rfl

/-- The resolution state keeps unique names: the current catalog has unique folded
names, and so does the catalog that an open transaction saved, if there is one. -/
def ResolveState.NamesUnique (state : ResolveState) : Prop :=
  state.catalog.NamesUnique ∧ ∀ saved, state.saved = some saved → saved.NamesUnique

/-- The unique-names rule ({lit}`lang_createtable.html`, R-01232-54838): for every
context, state and statement, if the state's catalogs have unique folded names
and the statement resolves, then the next state's catalogs have unique folded names.
Proof sketch: BEGIN, COMMIT and ROLLBACK only copy catalogs that have unique names, and
a pragma keeps them ({name}`resolvePragma_cases`); every other statement changes the catalog by one
{name}`CatalogStep`, or is a prepare error of its foreign keys that keeps the state
({name}`ResolveState.withWrite_cases`). -/
theorem resolveStatement_namesUnique (context : ResolveContext) (state next : ResolveState)
    (statement : Syntax.Statement) (resolved : Resolved.Statement)
    (unique : state.NamesUnique)
    (ok : resolveStatement context state statement = .ok (resolved, next)) :
    next.NamesUnique := by
  obtain ⟨current, saved⟩ := unique
  have keep : ∀ after, CatalogStep state.catalog after →
      ({ state with catalog := after } : ResolveState).NamesUnique :=
    fun after step => ⟨step.namesUnique current, saved⟩
  have written : ∀ result, state.withWrite context result = .ok (resolved, next) →
      (∀ statement after, result = .ok (statement, after) → CatalogStep state.catalog after) → next.NamesUnique := by
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
    exact keep _ (resolveCreateTable_step _ _ _ _ _ _ _ _ (by assumption))
  | createIndex name unique table terms filter =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateIndex_step _ _ _ _ _ _ _ _ _ (by assumption))
  | addColumn table column =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveAddColumn_step _ _ _ _ _ _ (by assumption))
  | dropTable name ifExists =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => resolveDropTable_step _ _ _ _ _ found
  | dropIndex name ifExists =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveDropIndex_step _ _ _ _ _ (by assumption))
  | createTrigger name ifNotExists time event table condition body =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveCreateTrigger_step _ _ _ _ _ _ (by assumption))
  | dropTrigger name ifExists =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ (resolveDropTrigger_step _ _ _ _ _ (by assumption))
  | insert table columns rows conflicts algorithm returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => (resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveInsert_same _ _ _ _ _ _ _ _ _ _ _ _ h) found).1 ▸ .same
  | update table assignments filter returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => (resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveUpdate_same _ _ _ _ _ _ _ _ _ _ h) found).1 ▸ .same
  | delete table filter returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => (resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveDelete_same _ _ _ _ _ _ _ _ _ h) found).1 ▸ .same
  | pragma pragma =>
    rcases resolvePragma_cases ok with ⟨setting, _, _, rfl⟩ | ⟨rfl, _, _⟩
    · cases setting <;> exact ⟨current, saved⟩
    · exact ⟨current, saved⟩
  | select results source joins filter groupBy orderBy limit offset subqueries having distinct =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    exact keep _ ((resolveSelect_same _ _ _ _ _ _ (by assumption)).1 ▸ .same)

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
      exact ih _ _ _ _ (resolveStatement_namesUnique _ _ _ _ _ unique hfirst) hlater
  unfold resolve at ok
  split at ok <;> try contradiction
  rename_i result hresult
  cases ok
  exact (general _ _ _ _ _ ⟨unique, by simp [ResolveState.initial]⟩ hresult).1

end Belay.Sqlite.Model
