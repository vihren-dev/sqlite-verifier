import Belay.Sqlite.SchemaPreservation

set_option doc.verso true

/-! Bounded structural regressions for the reusable schema model. Native SQL
comparisons and complete application examples are checked separately. -/

open Belay.Sqlite

namespace SqliteVerifier.SchemaExamples

/-- A nullable TEXT column used in the retained ordinary primary-key example.
The key does not add a NOT NULL annotation; {assert}`textKey.notNull = false`. -/
def textKey : Column := { name := "id", affinity := .text }
/-- An INTEGER-affinity column retaining BIGINT spelling, so a primary key
cannot alias the physical rowid; {assert}`version.declaredType = DeclaredType.bigInt`. -/
def version : Column := { name := "version", affinity := .integer, declaredType := .bigInt }
/-- An existing NOT NULL TIMESTAMP declaration with a retained {lit}`CURRENT_TIMESTAMP`
default. It illustrates metadata that is admitted on existing columns but not
on a new plain column; {assert}`timestamp.plain = false`. -/
def timestamp : Column := {
  name := "installed_on", affinity := .numeric, declaredType := .timestamp
  notNull := true, defaultValue := some .currentTimestamp }
/-- A primary key and named unique index on {lit}`id`, illustrating retained
properties and the shared table/index namespace. Use
{lean}`TableProperties.mk [] [] []` when no properties are needed. -/
def properties : TableProperties := {
  primaryKey := ["id"]
  indexes := [{ name := "key_index", columns := ["id"], unique := true }] }
/-- A one-row table with a negative physical rowid and NULL text key, retaining
{name}`properties`. It illustrates ordinary nullable keys;
{assert}`table.rows.length = 1`. An empty row list represents an empty table. -/
def table : Table := { columns := [textKey], rows := [⟨-9, [.null]⟩], properties := properties }

#guard supportedProperties [textKey] properties
#guard supportedProperties [version] { primaryKey := ["version"] }
#guard !supportedProperties [{ name := "id", affinity := .integer }] { primaryKey := ["id"] }
#guard supportedColumn timestamp
#guard !timestamp.plain
#guard !supportedColumn { version with affinity := .text }
#guard !supportedProperties [textKey] { uniqueKeys := [["missing"]] }
#guard supportedExistingTable { name := "sqlite_stat1", columns := statisticsColumns ["tbl", "idx", "stat"] }
#guard !supportedExistingTable { name := "sqlite_stat1", columns := [textKey] }
#guard !supportedTableName "sqlite_stat1"

/-- This concrete schema fails {name}`Schema.Valid` because its table and index
share {lit}`key_index`; the proof reduces the global-name duplicate check. -/
example : ¬Schema.Valid [{ name := "key_index", columns := [textKey], properties := properties }] := by
  simp [Schema.Valid, properties]

/-- The concrete {name}`table` satisfies {name}`Table.Valid`, including its
negative rowid and NULL cell. The proof reduces widths, bounds and support. -/
example : table.Valid := by
  simp [Table.Valid, table, validRowid]
  decide +kernel

/-- Adding a plain {lit}`shell` column to the concrete {lit}`history` table
returns that table's {name}`Table.appendColumns` at the same lookup, preserving
its properties. The proof computes this fixed execution in the kernel. -/
example : (step (.addColumn "history" { name := "shell", affinity := .text })
    (fun name => if name = "history" then some table else none)).database "history" =
    some (table.appendColumns [{ name := "shell", affinity := .text }]) := by
  decide +kernel

/-- Adding {name}`timestamp` to the empty database returns an unchanged database
and {name}`ExecutionError.invalidDefinition` at position zero. The plain-column
check rejects the declaration before table lookup; the proof unfolds that check. -/
example : step (.addColumn "history" timestamp) (fun _ => none) =
    .failure 0 .invalidDefinition (fun _ => none) := by
  simp [step, timestamp, Column.plain]

end SqliteVerifier.SchemaExamples
