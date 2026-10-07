import Requirements
import SchemaInputs

/-! Approved empty-schema interpretation for the kernel-gate fixture. -/
namespace Interpretation
/-- No additional starting condition is needed for an empty schema. -/
def admitted (_ : Belay.Sqlite.Database) : Prop := True
/-- Preserve exact empty-schema conformance while observing one unit value. -/
def current : SqliteVerifier.Interpretation Requirements.LogicalState :=
  ⟨Belay.Sqlite.Conforms Generated.startSchema, fun _ => some ()⟩
end Interpretation
