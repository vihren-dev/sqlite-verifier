import SqliteVerifier.SchemaPreservation

/-! Bounded structural regressions, not a substituted Atuin pilot. Real captured
schemas and native correspondence are checked separately by the pilot workflow. -/

namespace SqliteVerifier.SchemaExamples

/-- Ordinary TEXT primary keys remain nullable unless explicitly constrained. -/
def textKey : Column := { name := "id", affinity := .text }
/-- BIGINT preserves SQLx's spelling and must not become INTEGER rowid aliasing. -/
def version : Column := { name := "version", affinity := .integer, declaredType := .bigInt }
/-- Existing SQLx defaults are retained without being evaluated by ADD COLUMN. -/
def timestamp : Column := {
  name := "installed_on", affinity := .numeric, declaredType := .timestamp
  notNull := true, defaultValue := some .currentTimestamp }
/-- A representative unique secondary index shares SQLite's global object namespace. -/
def properties : TableProperties := {
  primaryKey := ["id"]
  indexes := [{ name := "key_index", columns := ["id"], unique := true }] }
/-- A signed physical rowid and a NULL text key are distinct observations. -/
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

/-- The full schema detects collisions between table names and named indexes. -/
example : ¬Schema.Valid [{ name := "key_index", columns := [textKey], properties := properties }] := by
  simp [Schema.Valid, properties]

/-- A valid nullable text key is not silently strengthened to a nonnull key. -/
example : table.Valid := by
  simp [Table.Valid, table, validRowid]
  decide +kernel

/-- Executed nullable additions preserve all existing schema properties. -/
example : (step (.addColumn "history" { name := "shell", affinity := .text })
    (fun name => if name = "history" then some table else none)).database "history" =
    some (table.appendColumns [{ name := "shell", affinity := .text }]) := by
  decide +kernel

/-- A constrained new column is not misrepresented as a successful NULL extension. -/
example : step (.addColumn "history" timestamp) (fun _ => none) =
    .failure 0 .invalidDefinition (fun _ => none) := by
  simp [step, timestamp, Column.plain]

end SqliteVerifier.SchemaExamples
