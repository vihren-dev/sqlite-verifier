import Belay.Sqlite.Model.Resolution.WriteCatalogSpec
import Belay.Sqlite.Model.Resolution.DropSpec
import Belay.Sqlite.Model.Resolution.TriggerDefinitionSpec

set_option doc.verso true

/-! The resolution state after a resolved statement. Resolution changes the catalog with
the catalog function of each statement ({name}`Belay.Sqlite.Model.Resolved.Statement.applyCatalog`),
and BEGIN, COMMIT and ROLLBACK change the saved catalog. The theorems here state that
{lit}`resolveStatement` and {lit}`resolveFrom` give exactly that state, so the catalog that
resolution predicts is a function of the resolved statements; {lit}`CatalogAgreement`
shows that execution reaches the same catalog. -/

namespace Belay.Sqlite.Model

/-- The resolution state after the statement: BEGIN saves the catalog unless a catalog is
already saved, COMMIT drops the saved catalog, ROLLBACK restores it, a setting pragma sets the
setting that it carries ({name}`ResolveState.set`), and every other statement applies
{name}`Resolved.Statement.applyCatalog` to the catalog and keeps the saved one. Every statement
keeps the settings, except the setting pragma. -/
def ResolveState.after (state : ResolveState) : Resolved.Statement → ResolveState
  | .begin => { state with saved := state.saved.getD state.catalog }
  | .commit => { state with saved := none }
  | .rollback => { state with catalog := state.saved.getD state.catalog, saved := none }
  | .setting setting on => state.set on setting
  | statement@(.createTable ..) | statement@(.createIndex ..) | statement@(.createTrigger ..)
  | statement@(.addColumn ..) | statement@(.drop ..)
  | statement@(.insert ..) | statement@(.update ..) | statement@(.upsert ..) | statement@(.delete ..)
  | statement@(.prepareError _) | statement@(.query ..) =>
    { state with catalog := statement.applyCatalog state.catalog }

/-- For every state and statement that is not transaction control or a setting
({name}`Resolved.Statement.isControl`), {name}`ResolveState.after` applies the statement's
catalog change and keeps the saved catalog and the settings. Proof sketch: case analysis on the
statement: BEGIN, COMMIT, ROLLBACK and the setting contradict the premise, and every other
constructor is the definition. -/
theorem ResolveState.after_of_isControl (state : ResolveState) {statement : Resolved.Statement}
    (ordinary : statement.isControl = false) :
    state.after statement = { state with catalog := statement.applyCatalog state.catalog } := by
  cases statement with
  | begin | commit | rollback | setting => cases ordinary
  | createTable | createIndex | createTrigger | addColumn | drop | insert | update | upsert | delete | prepareError
  | query => rfl

/-- For every successful resolution of CREATE TABLE, the catalog after it is
{name}`Resolved.Statement.applyCatalog` of the resolved statement, which is not
transaction control. Proof sketch: every branch returns the input catalog with a prepare
error, or the CREATE TABLE at the end of the catalog with {name}`Catalog.createTable`. -/
theorem resolveCreateTable_applyCatalog (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (options : Syntax.TableOptions) (statement : Resolved.Statement)
    (ok : resolveCreateTable context catalog name columns constraints options = .ok (statement, after)) :
    after = statement.applyCatalog catalog ∧ statement.isControl = false := by
  unfold resolveCreateTable at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first | (cases ok; exact ⟨rfl, rfl⟩) | (cases ok)

/-- For every successful resolution of CREATE INDEX, the catalog after it is
{name}`Resolved.Statement.applyCatalog` of the resolved statement, which is not
transaction control. Proof sketch: as for CREATE TABLE, with {name}`Catalog.createIndex`.
-/
theorem resolveCreateIndex_applyCatalog (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (unique : Bool) (tableName : Identifier) (terms : List Syntax.OrderTerm)
    (filter : Option Syntax.Expr)
    (statement : Resolved.Statement)
    (ok : resolveCreateIndex context catalog name unique tableName terms filter = .ok (statement, after)) :
    after = statement.applyCatalog catalog ∧ statement.isControl = false := by
  unfold resolveCreateIndex at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first | (cases ok; exact ⟨rfl, rfl⟩) | (cases ok)

/-- For every successful resolution of ADD COLUMN, the catalog after it is
{name}`Resolved.Statement.applyCatalog` of the resolved statement, which is not
transaction control. Proof sketch: as for CREATE TABLE, with {name}`Catalog.addColumn`. -/
theorem resolveAddColumn_applyCatalog (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (definition : Syntax.ColumnDefinition) (statement : Resolved.Statement)
    (ok : resolveAddColumn context catalog tableName definition = .ok (statement, after)) :
    after = statement.applyCatalog catalog ∧ statement.isControl = false := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first | (cases ok; exact ⟨rfl, rfl⟩) | (cases ok)

/-- For every context, state and statement that resolves, the next state is
{name}`ResolveState.after` of the resolved statement. Proof sketch: transaction control
resolves to itself and {lit}`PRAGMA setting = value` to its setting; every other statement
gives a resolved statement that is not control and the catalog of
{name}`Resolved.Statement.applyCatalog`, by the lemma of its resolver, and a write that checks
foreign keys keeps both or is a prepare error that keeps the state
({name}`ResolveState.withWrite_cases`).
-/
theorem resolveStatement_after (context : ResolveContext) (state next : ResolveState)
    (statement : Syntax.Statement) (resolved : Resolved.Statement)
    (ok : resolveStatement context state statement = .ok (resolved, next)) :
    next = state.after resolved := by
  have ordinary : ∀ after, resolved.isControl = false → after = resolved.applyCatalog state.catalog →
      ({ state with catalog := after } : ResolveState) = state.after resolved := by
    intro after control equal
    rw [state.after_of_isControl control, equal]
  have written : ∀ result, state.withWrite context result = .ok (resolved, next) →
      (∀ statement after, result = .ok (statement, after) →
        after = statement.applyCatalog state.catalog ∧ statement.isControl = false) →
      next = state.after resolved := by
    intro result ok base
    rcases ResolveState.withWrite_cases ok with ⟨error, rfl, rfl⟩ | ⟨statement, after, rfl, rfl, catalog, kind⟩
    · rfl
    · obtain ⟨equal, control⟩ := base statement after rfl
      have resolvedControl : resolved.isControl = false := by
        simp only [Resolved.Statement.isControl, kind] at control ⊢
        exact control
      rw [state.after_of_isControl resolvedControl, catalog, equal]
  cases statement with
  | begin => cases ok; rfl
  | commit => cases ok; rfl
  | rollback => cases ok; rfl
  | createTable name columns constraints options =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨equal, control⟩ := resolveCreateTable_applyCatalog _ _ _ _ _ _ _ _ (by assumption)
    exact ordinary _ control equal
  | createIndex name unique table terms filter =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨equal, control⟩ := resolveCreateIndex_applyCatalog _ _ _ _ _ _ _ _ _ (by assumption)
    exact ordinary _ control equal
  | addColumn table column =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨equal, control⟩ := resolveAddColumn_applyCatalog _ _ _ _ _ _ (by assumption)
    exact ordinary _ control equal
  | dropTable name ifExists =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found => resolveDropTable_applyCatalog _ _ _ _ _ found
  | dropIndex name ifExists =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨equal, control⟩ := resolveDropIndex_applyCatalog _ _ _ _ _ (by assumption)
    exact ordinary _ control equal
  | createTrigger name ifNotExists time event table condition body =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨equal, control⟩ := resolveCreateTrigger_applyCatalog _ _ _ _ _ _ (by assumption)
    exact ordinary _ control equal
  | dropTrigger name ifExists =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨equal, control⟩ := resolveDropTrigger_applyCatalog _ _ _ _ _ (by assumption)
    exact ordinary _ control equal
  | insert table columns rows conflicts algorithm returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found =>
      let ⟨same, unchanged, control⟩ := resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
        (fun _ _ _ _ h => resolveInsert_same _ _ _ _ _ _ _ _ _ _ _ _ h) found
      ⟨same.trans unchanged.symm, control⟩
  | update table assignments filter returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found =>
      let ⟨same, unchanged, control⟩ := resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
        (fun _ _ _ _ h => resolveUpdate_same _ _ _ _ _ _ _ _ _ _ h) found
      ⟨same.trans unchanged.symm, control⟩
  | delete table filter returning subqueries =>
    simp only [resolveStatement] at ok
    exact written _ ok fun _ _ found =>
      let ⟨same, unchanged, control⟩ := resolveWriteSubqueries_same _ _ _ _ _ _ _ _ _
        (fun _ _ _ _ h => resolveDelete_same _ _ _ _ _ _ _ _ _ h) found
      ⟨same.trans unchanged.symm, control⟩
  | pragma pragma =>
    rcases resolvePragma_cases ok with ⟨_, _, rfl, rfl⟩ | ⟨rfl, unchanged, control⟩
    · rfl
    · exact ordinary _ control unchanged.symm
  | select results source joins filter groupBy orderBy limit offset subqueries having distinct =>
    simp only [resolveStatement, ResolveState.withCatalog, Except.map] at ok
    split at ok <;> cases ok
    obtain ⟨same, unchanged, control⟩ := resolveSelect_same _ _ _ _ _ _ (by assumption)
    exact ordinary _ control (same.trans unchanged.symm)

end Belay.Sqlite.Model
