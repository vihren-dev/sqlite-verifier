import Belay.Sqlite.Model.ResolveStatementLink

set_option doc.verso true

/-! The facts that the resolver gives for every resolved statement (ADR 0022, D3, slice 4), for a valid
resolution state in execution mode: the catalog after the statement is valid, a CREATE INDEX has an
index that is supported for the width of its table, an ADD COLUMN has a default that fits the strict type,
and a DROP meets {lit}`Catalog.DropClosed`. They discharge the conditions of the statement theorems of
{lit}`runScriptFrom`. -/

namespace Belay.Sqlite.Model

/-- For every context, state, statement and resolution: if the catalog of the state is valid, the resolved
statement meets {name}`Resolved.Statement.SchemaLink` on the catalog of the state. Proof sketch: a case for
each statement, with the lemma of its resolver ({name}`resolveAddColumn_schemaLink`,
{name}`resolveDropTable_schemaLink`, {name}`resolveDropIndex_schemaLink`,
{name}`resolveDropTrigger_schemaLink` and the lemmas of the other resolvers); a write that checks keys
keeps the link ({name}`ResolveState.withWrite_schemaLink`). -/
theorem resolveStatement_schemaLink {limits : Limits} (context : ResolveContext) (state next : ResolveState)
    (statement : Syntax.Statement) (resolved : Resolved.Statement) (valid : state.catalog.Valid limits)
    (ok : resolveStatement context state statement = .ok (resolved, next)) : resolved.SchemaLink state.catalog := by
  have plain : ∀ result, state.withCatalog result = .ok (resolved, next) →
      (∀ statement after, result = .ok (statement, after) → statement.SchemaLink state.catalog) →
      resolved.SchemaLink state.catalog := by
    intro result ok each
    rcases result with _ | ⟨statement, after⟩
    · cases ok
    · simp only [ResolveState.withCatalog, Except.map, Except.ok.injEq, Prod.mk.injEq] at ok
      obtain ⟨rfl, _⟩ := ok
      exact each _ _ rfl
  cases statement with
  | begin | commit | rollback => cases ok; trivial
  | createTable name columns constraints options =>
    exact plain _ ok fun _ _ found => resolveCreateTable_schemaLink _ _ _ _ _ _ _ _ found
  | createIndex name unique table terms filter =>
    exact plain _ ok fun _ _ found => resolveCreateIndex_schemaLink _ _ _ _ _ _ _ _ _ found
  | addColumn table column =>
    exact plain _ ok fun _ _ found => resolveAddColumn_schemaLink _ _ _ _ _ _ found
  | dropTable name ifExists =>
    exact ResolveState.withWrite_schemaLink ok fun _ _ found => resolveDropTable_schemaLink _ _ _ valid found
  | dropIndex name ifExists =>
    exact plain _ ok fun _ _ found => resolveDropIndex_schemaLink _ _ _ valid found
  | createTrigger name ifNotExists time event table condition body =>
    exact plain _ ok fun _ _ found => resolveCreateTrigger_schemaLink _ _ _ _ _ _ found
  | dropTrigger name ifExists =>
    exact plain _ ok fun _ _ found => resolveDropTrigger_schemaLink _ _ _ valid found
  | insert table columns rows conflicts algorithm returning subqueries =>
    exact ResolveState.withWrite_schemaLink ok fun _ _ found => resolveWriteSubqueries_schemaLink _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveInsert_schemaLink _ _ _ _ _ _ _ _ _ _ _ _ h) found
  | update table assignments filter returning subqueries =>
    exact ResolveState.withWrite_schemaLink ok fun _ _ found => resolveWriteSubqueries_schemaLink _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveUpdate_schemaLink _ _ _ _ _ _ _ _ _ _ h) found
  | delete table filter returning subqueries =>
    exact ResolveState.withWrite_schemaLink ok fun _ _ found => resolveWriteSubqueries_schemaLink _ _ _ _ _ _ _ _ _
      (fun _ _ _ _ h => resolveDelete_schemaLink _ _ _ _ _ _ _ _ _ h) found
  | pragma pragma => exact resolvePragma_schemaLink ok
  | select results source joins filter groupBy orderBy limit offset subqueries having distinct compound =>
    exact plain _ ok fun _ _ found => resolveSelect_schemaLink _ _ _ _ _ _ found

end Belay.Sqlite.Model
