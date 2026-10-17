import Belay.Sqlite.SchemaPreservation
import Belay.Sqlite.LiteralPreservation

set_option doc.verso true

/-! Bounded structural regressions for the catalog validity checks and the
definition steps. Native SQL comparisons and complete application examples are
checked separately. -/

open Belay.Sqlite

namespace SqliteVerifier.SchemaExamples

/-- A nullable TEXT column used in the retained ordinary primary-key example.
The key does not add a NOT NULL annotation; {assert}`textKey.notNull = false`. -/
def textKey : CatalogColumn := { name := "id", declaredType := some "TEXT" }

/-- An existing NOT NULL TIMESTAMP declaration with a retained {lit}`CURRENT_TIMESTAMP`
default. It illustrates metadata that a schema may describe but that a new column
of a statement that runs may not have; {assert}`timestamp.plain = false`. -/
def timestamp : CatalogColumn := {
  name := "installed_on", declaredType := some "TIMESTAMP"
  notNull := true, defaultValue := some ⟨.currentTime "CURRENT_TIMESTAMP", "CURRENT_TIMESTAMP"⟩ }

/-- A table keyed on {lit}`id`, with a unique index named {lit}`key_index` on the same
column at catalog position 1, illustrating keys and the shared namespace. -/
def keyed : Catalog := [{ name := "items", entry := .table { columns := [textKey], primaryKey := [0] } },
  { name := "key_index", entry := .index { table := 0, columns := [0], unique := true } }]

/-- The documented limits of SQLite; the column limit is 2,000. -/
def limits : Limits := Limits.documentedDefaults

/-- A one-row table with a negative physical rowid and NULL text key. It illustrates
ordinary nullable keys; {assert}`table.rows.length = 1`. An empty row list
represents an empty table. -/
def table : Table := { shape := { columns := [textKey], primaryKey := [0] }, rows := [⟨-9, [.null]⟩] }

#guard keyed.supported limits
-- A rowid alias is admitted (slice 5b); writes to it check its affinity (aliasReady).
#guard ({ columns := [textKey], primaryKey := [0], rowidAlias := some 0 } : CatalogTable).supported limits
#guard ({ columns := [textKey], uniqueKeys := [[1]] } : CatalogTable).supported limits == false
#guard ({ columns := [textKey, { textKey with name := "ID" }] } : CatalogTable).supported limits == false
#guard ({ columns := [timestamp] } : CatalogTable).supported limits
#guard !timestamp.plain
/-- The typeless columns of SQLite's {lit}`sqlite_stat1` table. -/
def statisticsTable : CatalogTable := { columns := ["tbl", "idx", "stat"].map fun name => { name, declaredType := none } }

#guard Catalog.supported limits [{ name := "sqlite_stat1", entry := .table statisticsTable }]
#guard Catalog.supported limits [{ name := "sqlite_stat1", entry := .table { columns := [textKey] } }] == false
#guard Catalog.supported limits [{ name := "sqlite_x", entry := .table { columns := [textKey] } }] == false
-- A table and an index share one folded name, so the catalog is not valid.
#guard Catalog.supported limits [{ name := "KEY_INDEX", entry := .table { columns := [textKey] } },
  { name := "key_index", entry := .index { table := 0, columns := [0], unique := true } }] == false

/-- The concrete {name}`table` satisfies {name}`Table.Valid`, including its
negative rowid and NULL cell. The proof reduces widths and bounds, and computes the
stored form of the row. -/
example : table.Valid := by
  simp only [Table.Valid, Table.RowsValid, table, validRowid]
  refine ⟨by simp, ?_⟩
  intro row member
  simp only [List.mem_singleton] at member
  subst row
  exact ⟨by decide, by simp, Row.Stored.of_storedForm (by decide +kernel), fun _ alias => by simp at alias⟩

/-- Adding a plain {lit}`shell` column to the table at position 0 returns that
table's {name}`Table.appendColumns` at the same position, preserving its keys. The
proof computes this fixed execution in the kernel. -/
example : (step (.addColumn 0 { name := "shell", declaredType := some "TEXT" })
    (fun position => if position = 0 then some table else none)).database 0 =
    some (table.appendColumns [({ name := "shell", declaredType := some "TEXT" }, .null)]) := by
  decide +kernel

/-- The supported-subset check refuses ADD COLUMN of {name}`timestamp`, a model
restriction, because SQLite accepts the column but the model does not describe its
default. Resolution never gives such a statement for a statement that runs. The
proof computes the check in the kernel. -/
example : statementReady (.addColumn 0 timestamp) (fun _ => none) = false := by
  decide +kernel

/-- {name}`step` runs a CREATE TABLE of a keyed table, which is not plain: it
stores an empty table with that shape at the new position, as SQLite does. The
supported-subset check {name}`statementReady` refuses the statement instead,
because the model restricts such tables. The proof computes both in the kernel. -/
example : (step (.createTable 0 "items" { columns := [textKey], primaryKey := [0] }) (fun _ => none)).database 0 =
      some { shape := { columns := [textKey], primaryKey := [0] }, rows := [] } ∧
    statementReady (.createTable 0 "items" { columns := [textKey], primaryKey := [0] }) (fun _ => none) = false := by
  decide +kernel

/-- ADD COLUMN of {name}`timestamp` has unsupported default evaluation.
{name}`step` retains the original table, and {name}`statementReady` refuses the
statement. The proof computes both in the kernel. -/
example : (step (.addColumn 0 timestamp) (fun position => if position = 0 then some table else none)).database 0 =
      some table ∧
    statementReady (.addColumn 0 timestamp) (fun position => if position = 0 then some table else none) = false := by
  decide +kernel

end SqliteVerifier.SchemaExamples
