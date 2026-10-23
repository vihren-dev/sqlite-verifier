import Belay.Sqlite.Model.Resolution.ForeignKeyPlan
import Belay.Sqlite.Model.Resolution.Context
import Belay.Sqlite.Model.Resolution.ConflictPolicy

set_option doc.verso true

/-! The foreign keys of a resolved write when foreign keys are on (ADR 0018, D4): the prepare
errors of the keys that SQLite prepares for it ({name}`Belay.Sqlite.Model.Catalog.foreignKeyIssues`), the
restrictions of the slice, and whether the write has a key to check. -/

namespace Belay.Sqlite.Model

/-- Whether the table at the position of the catalog has a foreign key or is referenced by one. -/
def Catalog.keyed (catalog : Catalog) (table : Nat) : Bool :=
  let links := catalog.foreignKeyLinks
  !(childLinks links table).isEmpty || !(parentLinks links table).isEmpty

/-- The foreign-key write of an INSERT of the number of rows with the algorithm into the table at
the position, for {lit}`foreignKeyWrite`: a write of several rows with more than one row, which
may replace rows when an algorithm of its keys is REPLACE, and has a key to check when it
processes a link or may replace rows of a table with keys. -/
def Catalog.insertWrite (catalog : Catalog) (table count : Nat) (algorithm : Option ConflictAlgorithm) :
    Option (Nat × ForeignKeyWrite × Bool × Bool) :=
  (catalog.tableAt table).map fun shape =>
    let replace := (catalog.writePolicy table shape algorithm).keys.contains .replace
    let write := ForeignKeyWrite.insert (count > 1) replace
    (table, write, false, !(processedLinks catalog catalog.foreignKeyLinks table write).isEmpty ||
      (replace && catalog.keyed table))

/-- What SQLite's foreign-key code prepares for a resolved write of the catalog, with whether a
key needs it, or none for a statement that is not a write that checks keys: the table, the
{name}`ForeignKeyWrite`, whether the write is the DELETE of DROP TABLE, and whether the write has
a key to check. An INSERT writes several rows with more than one row, and may replace rows when
an algorithm of its keys is REPLACE; an UPDATE changes the assigned columns
({name}`CatalogTable.changedColumns`). -/
def foreignKeyWrite (catalog : Catalog) : Resolved.Statement → Option (Nat × ForeignKeyWrite × Bool × Bool)
  | .insert table rows _ _ _ => catalog.insertWrite table rows.length none
  | .upsert table rows _ _ algorithm _ _ => catalog.insertWrite table rows.length algorithm
  | .update table assignments _ _ _ _ => (catalog.tableAt table).map fun shape =>
    let changed := shape.changedColumns (assignments.map (·.1))
    let name := ((catalog[table]?).map (·.name)).getD default
    (table, .update changed, false, updateLevel catalog.foreignKeyLinks table name shape changed != 0)
  | .delete table _ _ _ _ => some (table, .delete, false, catalog.keyed table)
  | .drop (table :: _) _ => (catalog.tableAt table).map fun _ =>
    (table, .delete, true, !(parentLinks catalog.foreignKeyLinks table).isEmpty)
  | .drop [] _ | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .begin | .commit | .rollback
  | .prepareError _ | .query .. | .setting .. => none
/-- The write with the rules that it runs row by row ({name}`Resolved.WriteRules`): those of a
write that has a key to check ({name}`foreignKeyWrite`) or a trigger that it may fire. -/
def Resolved.Statement.withRules (rules : Resolved.WriteRules) : Resolved.Statement → Resolved.Statement
  | .insert table rows returning subqueries _ => .insert table rows returning subqueries (some rules)
  | .upsert table rows clauses returning algorithm subqueries _ =>
    .upsert table rows clauses returning algorithm subqueries (some rules)
  | .update table assignments filter returning subqueries _ =>
    .update table assignments filter returning subqueries (some rules)
  | .delete table filter returning subqueries _ => .delete table filter returning subqueries (some rules)
  | .drop positions _ => .drop positions (some rules)
  | statement@(.createTable ..) | statement@(.createIndex ..) | statement@(.createTrigger ..) | statement@(.addColumn ..)
  | statement@.begin
  | statement@.commit | statement@.rollback | statement@(.prepareError _) | statement@(.query ..)
  | statement@(.setting ..) => statement

/-- Whether the statement is an INSERT with a {lit}`DO UPDATE` clause. -/
def Resolved.Statement.updatesOnConflict : Resolved.Statement → Bool
  | .upsert _ _ clauses .. => clauses.any fun clause => (clause.action matches .update ..)
  | .insert .. | .update .. | .delete .. | .drop .. | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn ..
  | .begin | .commit | .rollback | .prepareError _ | .query .. | .setting .. => false

/-- The foreign keys of a resolved write, over the catalog before it,
with foreign keys on: the prepare error of its keys ({name}`Catalog.foreignKeyIssues`); a key
that is deferred is {name}`RestrictionKind.deferredForeignKey`, and a {lit}`DO UPDATE` clause on
a table with a key to check is {name}`RestrictionKind.foreignKeyUpsert`; otherwise whether the
write has a key to check. Every other statement has none. -/
def foreignKeyCheck (catalog : Catalog) (statement : Resolved.Statement) :
    Except NodeRestriction (Except PrepareError Bool) :=
  match foreignKeyWrite catalog statement with
  | none => .ok (.ok false)
  | some (table, write, ignore, checked) =>
    match catalog.foreignKeyIssues table write ignore with
    | .error error => .ok (.error error)
    | .ok deferred =>
      if deferred then .error { path := [], kind := .deferredForeignKey }
      else if !checked then .ok (.ok false)
      else if statement.updatesOnConflict then .error { path := [], kind := .foreignKeyUpsert }
      else .ok (.ok true)

end Belay.Sqlite.Model
