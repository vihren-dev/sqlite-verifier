import SchemaInputs

set_option doc.verso true

/-! Schema declarations come only from the sealed translation of schema.sql.
Handwritten column names below describe the application mapping, not a SQL schema. -/
namespace SchemaBinding
open Belay.Sqlite SqliteVerifier

/-- The complete sealed {name}`Generated.startSchema`; use it for schema-bound
application interpretation rather than duplicating declarations. -/
abbrev start : Schema := Generated.startSchema
/-- Return the first history entry from the sealed schema, or a history entry
with empty shape columns when absent. The latter does not satisfy column support;
{name}`Conforms` and decoder validity remain separate proof obligations. -/
def history : TableSchema :=
  (start.find? (fun table => table.name == "history")).getD { name := "history", shape.columns := [] }
/-- The eleven pre-migration application fields used by the approved decoder. -/
def fields : List String := ["id", "timestamp", "duration", "exit", "command", "cwd",
  "session", "hostname", "deleted_at", "author", "intent"]

end SchemaBinding
