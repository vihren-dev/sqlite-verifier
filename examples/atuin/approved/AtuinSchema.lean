import SqliteVerifier

/-! Complete persisted schema captured from the pinned SQLx runner; no object is omitted. -/
namespace AtuinSchema
open SqliteVerifier
/-- Captured _sqlx_migrations definition, including every retained constraint and index. -/
def metadata : TableSchema := { name := "_sqlx_migrations", columns := [{ name := "version", affinity := .integer, declaredType := .bigInt }, { name := "description", affinity := .text, notNull := true }, { name := "installed_on", affinity := .numeric, declaredType := .timestamp, notNull := true, defaultValue := some .currentTimestamp }, { name := "success", affinity := .numeric, declaredType := .boolean, notNull := true }, { name := "checksum", affinity := .blob, notNull := true }, { name := "execution_time", affinity := .integer, declaredType := .bigInt, notNull := true }], properties := { primaryKey := ["version"], uniqueKeys := [], indexes := [] } }
/-- Captured history definition, including every retained constraint and index. -/
def history : TableSchema := { name := "history", columns := [{ name := "id", affinity := .text }, { name := "timestamp", affinity := .integer, notNull := true }, { name := "duration", affinity := .integer, notNull := true }, { name := "exit", affinity := .integer, notNull := true }, { name := "command", affinity := .text, notNull := true }, { name := "cwd", affinity := .text, notNull := true }, { name := "session", affinity := .text, notNull := true }, { name := "hostname", affinity := .text, notNull := true }, { name := "deleted_at", affinity := .integer }, { name := "author", affinity := .text }, { name := "intent", affinity := .text }], properties := { primaryKey := ["id"], uniqueKeys := [["timestamp", "cwd", "command"]], indexes := [{ name := "idx_history_command", columns := ["command"], unique := false }, { name := "idx_history_command_timestamp", columns := ["command", "timestamp"], unique := false }, { name := "idx_history_timestamp", columns := ["timestamp"], unique := false }] } }
/-- Captured sqlite_stat1 definition, including every retained constraint and index. -/
def stat1 : TableSchema := { name := "sqlite_stat1", columns := [{ name := "tbl", affinity := .blob, declaredType := .untyped }, { name := "idx", affinity := .blob, declaredType := .untyped }, { name := "stat", affinity := .blob, declaredType := .untyped }], properties := { primaryKey := [], uniqueKeys := [], indexes := [] } }
/-- Captured sqlite_stat4 definition, including every retained constraint and index. -/
def stat4 : TableSchema := { name := "sqlite_stat4", columns := [{ name := "tbl", affinity := .blob, declaredType := .untyped }, { name := "idx", affinity := .blob, declaredType := .untyped }, { name := "neq", affinity := .blob, declaredType := .untyped }, { name := "nlt", affinity := .blob, declaredType := .untyped }, { name := "ndlt", affinity := .blob, declaredType := .untyped }, { name := "sample", affinity := .blob, declaredType := .untyped }], properties := { primaryKey := [], uniqueKeys := [], indexes := [] } }
 /-- The original eleven fields, without assuming the TEXT primary key is nonnull. -/
def fields : List String := history.columns.map Column.name
/-- The complete before schema; implicit autoindexes derive from retained keys. -/
def start : Schema := [metadata, history, stat1, stat4]
/-- Nullable default-free extension in the unchanged upstream migration. -/
def shell : Column := { name := "shell", affinity := .text }
/-- Complete resulting schema, preserving definitions of every other object. -/
def next : Schema := [metadata, { history with columns := history.columns ++ [shell] }, stat1, stat4]
/-- The independently reviewed intended statement, separate from generated candidate SQL. -/
def payload : List Statement := [.addColumn "history" shell]
end AtuinSchema
