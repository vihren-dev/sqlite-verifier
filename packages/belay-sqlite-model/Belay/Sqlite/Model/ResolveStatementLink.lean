import Belay.Sqlite.Model.ResolveStatementForms
import Belay.Sqlite.Model.ResolveStatementValid

set_option doc.verso true

/-! The link of every resolved statement to the catalog (ADR 0022, D3, slice 4): for a valid resolution
state in execution mode, every statement that {lit}`resolveStatement` resolves meets
{lit}`Resolved.Statement.SchemaLink` on the catalog of the state. An ADD COLUMN has a default that fits the
strict type of its column, and a DROP has positions that meet {lit}`Catalog.DropClosed`. -/

namespace Belay.Sqlite.Model

/-- For every successful resolution of ALTER TABLE ADD COLUMN, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a
prepare error, or the ADD COLUMN of a column whose strict default fits
({name}`resolveAddColumn_strictDefaultFits`). -/
theorem resolveAddColumn_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (definition : Syntax.ColumnDefinition) (statement : Resolved.Statement)
    (ok : resolveAddColumn context catalog tableName definition = .ok (statement, after)) :
    statement.SchemaLink catalog := by
  unfold resolveAddColumn at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; trivial)
    | (cases ok; done)
    | (simp only [Except.ok.injEq, Prod.mk.injEq] at ok
       obtain ⟨rfl, _⟩ := ok
       show strictDefaultFits _ = true
       rw [strictDefaultFits_with]
       simpa using (by assumption : ¬(!strictDefaultFits _) = true))

/-- For every valid catalog and successful resolution of DROP TABLE, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: a prepare error and a DROP of nothing
meet it trivially or by {name}`Catalog.DropClosed.nil`; the drop of a table meets
{name}`Catalog.DropClosed.table`. -/
theorem resolveDropTable_schemaLink {limits : Limits} {catalog after : Catalog} (name : Identifier)
    (ifExists : Bool) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropTable catalog name ifExists = .ok (statement, after)) : statement.SchemaLink catalog := by
  unfold resolveDropTable at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; trivial)
    | (cases ok; exact Catalog.DropClosed.nil catalog)
    | (cases ok; exact Catalog.DropClosed.table valid (by assumption))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP INDEX, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: a prepare error and a DROP of nothing
meet it trivially or by {name}`Catalog.DropClosed.nil`; the drop of an index meets
{name}`Catalog.DropClosed.single`, as the position holds no table. -/
theorem resolveDropIndex_schemaLink {limits : Limits} {catalog after : Catalog} (name : Identifier)
    (ifExists : Bool) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropIndex catalog name ifExists = .ok (statement, after)) : statement.SchemaLink catalog := by
  unfold resolveDropIndex at ok
  simp only [prepareError, restrict] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; trivial)
    | (cases ok; exact Catalog.DropClosed.nil catalog)
    | (cases ok
       obtain ⟨object, index, atPosition, entry⟩ := Catalog.findIndex_some (by assumption)
       exact Catalog.DropClosed.single valid atPosition (by simp [entry]))
    | (cases ok; done)

/-- For every valid catalog and successful resolution of DROP TRIGGER, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: a prepare error and a DROP of nothing
meet it trivially or by {name}`Catalog.DropClosed.nil`; the drop of a trigger meets
{name}`Catalog.DropClosed.single`, as the position holds no table. -/
theorem resolveDropTrigger_schemaLink {limits : Limits} {catalog after : Catalog} (name : Identifier)
    (ifExists : Bool) (statement : Resolved.Statement) (valid : catalog.Valid limits)
    (ok : resolveDropTrigger catalog name ifExists = .ok (statement, after)) : statement.SchemaLink catalog := by
  unfold resolveDropTrigger at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first
    | (cases ok; trivial)
    | (cases ok; exact Catalog.DropClosed.nil catalog)
    | (cases ok
       obtain ⟨object, atPosition, entry⟩ := Catalog.findTrigger_some (by assumption)
       exact Catalog.DropClosed.single valid atPosition (by simp [entry]))
    | (cases ok; done)

/-- For every statement, rules and catalog: the write with the rules ({name}`Resolved.Statement.withRules`)
meets {name}`Resolved.Statement.SchemaLink` on the catalog when the statement does. Proof sketch: the rules
change no position of a drop, and no other field that the link reads. -/
theorem Resolved.Statement.schemaLink_withRules {catalog : Catalog} {statement : Resolved.Statement}
    (rules : Resolved.WriteRules) (link : statement.SchemaLink catalog) : (statement.withRules rules).SchemaLink catalog := by
  cases statement <;> exact link

/-- For every context, state, resolution and result of {name}`ResolveState.withWrite`: if every statement
of the resolution meets {name}`Resolved.Statement.SchemaLink` on the catalog of the state, so does the
resolved statement of the result. Proof sketch: unfold the definition; each branch gives a prepare error,
the statement, or the statement with rules ({name}`Resolved.Statement.schemaLink_withRules`). -/
theorem ResolveState.withWrite_schemaLink {context : ResolveContext} {state next : ResolveState}
    {result : StatementResolution} {resolved : Resolved.Statement}
    (ok : state.withWrite context result = .ok (resolved, next))
    (each : ∀ statement catalog, result = .ok (statement, catalog) → statement.SchemaLink state.catalog) :
    resolved.SchemaLink state.catalog := by
  unfold ResolveState.withWrite ResolveState.withCatalog at ok
  rcases result with _ | ⟨statement, catalog⟩
  · cases ok
  · simp only [Except.map, bind, Except.bind, pure, Except.pure] at ok
    repeat' split at ok
    all_goals first
      | (cases ok; trivial)
      | (cases ok; exact each _ _ rfl)
      | (cases ok; exact Resolved.Statement.schemaLink_withRules _ (each _ _ rfl))
      | cases ok

end Belay.Sqlite.Model
