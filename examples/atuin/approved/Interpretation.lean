import Requirements
import AtuinCatalog

/-! Current meaning and readiness depend only on approved inputs, never candidate modules. -/
namespace Interpretation
open SqliteVerifier

/-- Exact prior successful catalog and pending target, including preserved statistics schemas. -/
def admitted (database : Database) : Prop :=
  SqlxReady AtuinCatalog.config AtuinSchema.payload database

/-- Every represented history row is read from the actual database under its complete schema. -/
def current : Interpretation Requirements.LogicalState where
  invariant := Conforms AtuinSchema.start
  observe := observeNullable "history" AtuinSchema.fields none

end Interpretation
