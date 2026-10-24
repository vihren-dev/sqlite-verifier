import Belay.Sqlite.Model.ResolveDropValid
import Belay.Sqlite.Model.ResolveAddColumnCatalog
import Belay.Sqlite.Model.ResolveCreateIndexCatalog
import Belay.Sqlite.Model.ResolveCreateTriggerCatalog
import Belay.Sqlite.Model.Resolution.NamesSpec

set_option doc.verso true

/-! The link of a resolved statement to its catalog (ADR 0022, D3, slice 4). The facts that the resolver
gives about an ADD COLUMN or a DROP (the strict default of the column, the positions of the drop) are
stated as {lit}`Resolved.Statement.SchemaLink`, a property of every resolved statement. The resolver of
another statement gives a prepare error, a statement of its own form, or, for CREATE TRIGGER IF NOT EXISTS
of an existing trigger, a DROP of no object, which meets the link by {lit}`Catalog.DropClosed.nil`. -/

namespace Belay.Sqlite.Model

/-- The link of a resolved statement to the catalog that it resolved against:
* ADD COLUMN: the default of the new column fits its strict type ({name}`strictDefaultFits`);
* DROP: the positions of the drop meet {name}`Catalog.DropClosed` on the catalog;
* every other statement: nothing.

For example, {lean}`(Resolved.Statement.begin).SchemaLink []` holds. -/
def Resolved.Statement.SchemaLink (catalog : Catalog) : Resolved.Statement → Prop
  | .addColumn _ column => strictDefaultFits column = true
  | .drop positions _ => catalog.DropClosed positions
  | .createTable .. | .createIndex .. | .createTrigger .. | .begin | .commit | .rollback | .insert ..
  | .update .. | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => True

/-- For every successful resolution of CREATE TABLE, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a
prepare error or a CREATE TABLE. -/
theorem resolveCreateTable_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (columns : List Syntax.ColumnDefinition) (constraints : List Syntax.TableConstraint)
    (options : Syntax.TableOptions) (statement : Resolved.Statement)
    (ok : resolveCreateTable context catalog name columns constraints options = .ok (statement, after)) :
    statement.SchemaLink catalog := by
  unfold resolveCreateTable at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every successful resolution of CREATE INDEX, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a
prepare error or a CREATE INDEX. -/
theorem resolveCreateIndex_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (name : Identifier) (unique : Bool) (tableName : Identifier) (terms : List Syntax.OrderTerm)
    (filter : Option Syntax.Expr) (statement : Resolved.Statement)
    (ok : resolveCreateIndex context catalog name unique tableName terms filter = .ok (statement, after)) :
    statement.SchemaLink catalog := by
  unfold resolveCreateIndex at ok
  simp only [issueResolution, prepareError, restrict] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every successful resolution of CREATE TRIGGER, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a
prepare error, a CREATE TRIGGER, or (CREATE TRIGGER IF NOT EXISTS of an existing trigger) a DROP of no object,
which meets the link by {name}`Catalog.DropClosed.nil`. -/
theorem resolveCreateTrigger_schemaLink (catalog after : Catalog) (name : Identifier)
    (ifNotExists : Bool) (trigger : CatalogTrigger) (statement : Resolved.Statement)
    (ok : resolveCreateTrigger catalog name ifNotExists trigger = .ok (statement, after)) :
    statement.SchemaLink catalog := by
  unfold resolveCreateTrigger at ok
  simp only [prepareError] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every successful resolution of INSERT, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a write
or a prepare error. -/
theorem resolveInsert_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (names : Option (List Identifier)) (rows : List (List Syntax.Expr))
    (conflicts : List Syntax.ConflictClause) (algorithm : Option ConflictAlgorithm)
    (returning : List Syntax.ResultColumn) (subqueries : List Resolved.Query) (shapes : SubqueryShapes)
    (statement : Resolved.Statement)
    (ok : resolveInsert context catalog tableName names rows conflicts algorithm returning subqueries shapes =
      .ok (statement, after)) : statement.SchemaLink catalog := by
  unfold resolveInsert at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every successful resolution of UPDATE, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a write
or a prepare error. -/
theorem resolveUpdate_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (assignments : List (Identifier × Syntax.Expr)) (filter : Option Syntax.Expr)
    (returning : List Syntax.ResultColumn) (subqueries : List Resolved.Query) (shapes : SubqueryShapes)
    (statement : Resolved.Statement)
    (ok : resolveUpdate context catalog tableName assignments filter returning subqueries shapes =
      .ok (statement, after)) : statement.SchemaLink catalog := by
  unfold resolveUpdate at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every successful resolution of DELETE, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a write
or a prepare error. -/
theorem resolveDelete_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (tableName : Identifier) (filter : Option Syntax.Expr) (returning : List Syntax.ResultColumn)
    (subqueries : List Resolved.Query) (shapes : SubqueryShapes) (statement : Resolved.Statement)
    (ok : resolveDelete context catalog tableName filter returning subqueries shapes = .ok (statement, after)) :
    statement.SchemaLink catalog := by
  unfold resolveDelete at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every successful resolution of a {lit}`SELECT`, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog. Proof sketch: every branch of the resolver gives a query
or a prepare error. -/
theorem resolveSelect_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (query : Syntax.Subquery) (subqueries : List Syntax.Subquery) (statement : Resolved.Statement)
    (ok : resolveSelect context catalog query subqueries = .ok (statement, after)) :
    statement.SchemaLink catalog := by
  unfold resolveSelect at ok
  simp only [prepareError, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every pragma, state and successful resolution of the pragma, the resolved statement meets
{name}`Resolved.Statement.SchemaLink` on the catalog of the state. Proof sketch: by cases on the pragma; each branch
is a setting, a query or a prepare error. -/
theorem resolvePragma_schemaLink {state next : ResolveState} {pragma : Syntax.Pragma}
    {resolved : Resolved.Statement} (ok : resolvePragma state pragma = .ok (resolved, next)) :
    resolved.SchemaLink state.catalog := by
  unfold resolvePragma at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok)

/-- For every write resolution that meets {name}`Resolved.Statement.SchemaLink` on the catalog
({lit}`each`), every successful resolution of its subqueries and then of the write
({name}`resolveWriteSubqueries`) meets it. Proof
sketch: the other branches are a prepare error or a restriction. -/
theorem resolveWriteSubqueries_schemaLink (context : ResolveContext) (catalog after : Catalog)
    (field : Nat) (tableName : Identifier) (scopeOf : CatalogTable → Scope) (subqueries : List Syntax.Subquery)
    (resolveWrite : List Resolved.Query → SubqueryShapes → StatementResolution) (statement : Resolved.Statement)
    (each : ∀ resolved shapes after statement, resolveWrite resolved shapes = .ok (statement, after) →
      statement.SchemaLink catalog)
    (ok : resolveWriteSubqueries context catalog field tableName scopeOf subqueries resolveWrite =
      .ok (statement, after)) : statement.SchemaLink catalog := by
  unfold resolveWriteSubqueries at ok
  simp only [prepareError, restrict, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; trivial) | (cases ok; exact Catalog.DropClosed.nil _) | (cases ok) | exact each _ _ _ _ ok

end Belay.Sqlite.Model
