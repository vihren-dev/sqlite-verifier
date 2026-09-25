import SchemaInputs

/-! Schema declarations come only from the sealed translation of schema.sql.
Handwritten column names below describe the application mapping, not a SQL schema. -/
namespace SchemaBinding
open SqliteVerifier
/-- The complete generated starting representation. -/
abbrev start : Schema := Generated.startSchema
/-- Resolve an application's table definition from the generated starting schema. -/
def named (name : String) : TableSchema :=
  (start.find? (fun table => table.name == name)).getD { name := name, columns := [] }
/-- Bookkeeping declarations are generated, including nullable BIGINT key semantics. -/
def metadata : TableSchema := named "_sqlx_migrations"
/-- All history declarations and indexes are generated from the SQL input. -/
def history : TableSchema := named "history"
/-- The eleven old application fields used by the approved decoder. -/
def fields : List String := ["id", "timestamp", "duration", "exit", "command", "cwd",
  "session", "hostname", "deleted_at", "author", "intent"]
/-- The intended new optional application's field has TEXT affinity. -/
def shell : Column := { name := "shell", affinity := .text }
/-- This expected schema is derived by extension, never copied from migration output. -/
def next : Schema := start.appendAt "history" [shell]
end SchemaBinding
