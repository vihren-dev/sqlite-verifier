import SchemaInputs

/-! Schema declarations come only from the sealed translation of schema.sql.
Handwritten column names below describe the application mapping, not a SQL schema. -/
namespace SchemaBinding
open SqliteVerifier

/-- The complete generated starting application representation. -/
abbrev start : Schema := Generated.startSchema
/-- Resolve the application's history table from the generated starting schema. -/
def history : TableSchema :=
  (start.find? (fun table => table.name == "history")).getD { name := "history", columns := [] }
/-- The eleven pre-migration application fields used by the approved decoder. -/
def fields : List String := ["id", "timestamp", "duration", "exit", "command", "cwd",
  "session", "hostname", "deleted_at", "author", "intent"]

end SchemaBinding
