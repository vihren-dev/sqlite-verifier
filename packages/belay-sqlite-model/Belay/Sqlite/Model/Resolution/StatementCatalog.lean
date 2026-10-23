import Belay.Sqlite.Model.Resolution.Resolved
import Belay.Sqlite.Model.Resolution.CatalogDrop

set_option doc.verso true

/-! The catalog that a resolved statement leaves when it succeeds. Resolution and
execution change the catalog with the same functions ({lit}`Catalog.createTable`,
{lit}`Catalog.createIndex`, {lit}`Catalog.addColumn`, {lit}`Catalog.drop`), and this function names that
change once, so the theorems that relate them can state it. -/

namespace Belay.Sqlite.Model.Resolved

/-- The catalog after the statement succeeds on the given catalog: CREATE TABLE, CREATE
INDEX, CREATE TRIGGER, ADD COLUMN and DROP apply their catalog function, and every other statement leaves the catalog unchanged. Transaction control is not a
catalog change here; {lit}`ResolveState.after` handles it. For example,
{lean}`(Statement.begin.applyCatalog [] : Catalog)` is the empty catalog. -/
def Statement.applyCatalog : Statement → Catalog → Catalog
  | .createTable _ name table, catalog => catalog.createTable name table
  | .createIndex _ name index, catalog => catalog.createIndex name index
  | .createTrigger _ name trigger, catalog => catalog.createTrigger name trigger
  | .addColumn position column, catalog => catalog.addColumn position column
  | .drop positions _, catalog => catalog.drop positions
  | .begin, catalog | .commit, catalog | .rollback, catalog | .insert .., catalog | .update .., catalog
  | .upsert .., catalog | .delete .., catalog | .prepareError _, catalog | .query .., catalog
  | .setting .., catalog => catalog

/-- The form of a resolved statement, for the rules that only classify statements (ADR
0013, D7). -/
inductive Statement.Kind where
  /-- CREATE TABLE or ADD COLUMN: a definition that changes a table. -/
  | definition
  /-- CREATE INDEX. -/
  | index
  /-- CREATE TRIGGER (ADR 0018, D5). -/
  | trigger
  /-- DROP INDEX or DROP TABLE: a removal from the catalog. -/
  | drop
  /-- BEGIN, COMMIT or ROLLBACK: transaction control. -/
  | control
  /-- INSERT, INSERT with {lit}`ON CONFLICT` or a conflict algorithm, UPDATE or DELETE. -/
  | write
  /-- A query. -/
  | query
  /-- A statement that SQLite refuses to prepare. -/
  | prepareError
  /-- {lit}`PRAGMA setting = value`: it changes the setting that resolution follows. -/
  | setting
  deriving Repr, DecidableEq

/-- The form of the statement ({name}`Statement.Kind`). Every rule that only asks which form
a statement has reads it, so a new statement form gets a form here first. -/
@[simp] def Statement.kind : Statement → Statement.Kind
  | .createTable .. | .addColumn .. => .definition
  | .createIndex .. => .index
  | .createTrigger .. => .trigger
  | .drop .. => .drop
  | .begin | .commit | .rollback => .control
  | .insert .. | .upsert .. | .update .. | .delete .. => .write
  | .query .. => .query
  | .prepareError _ => .prepareError
  | .setting .. => .setting

/-- Whether the statement is transaction control ({name}`Statement.Kind.control`), BEGIN,
COMMIT or ROLLBACK, or a setting ({name}`Statement.Kind.setting`). These change the saved
catalog of a transaction or a setting of the connection instead of the catalog; every other
statement is not control. -/
def Statement.isControl (statement : Statement) : Bool :=
  match statement.kind with
  | .control | .setting => true
  | .definition | .index | .trigger | .drop | .write | .query | .prepareError => false

end Belay.Sqlite.Model.Resolved
