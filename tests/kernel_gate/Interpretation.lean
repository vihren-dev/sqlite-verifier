import Requirements

/-! Approved empty-schema interpretation for the kernel-gate fixture. -/
namespace Interpretation
/-- No additional starting condition is needed for an empty schema. -/
def admitted (_ : SqliteVerifier.Database) : Prop := True
/-- Preserve exact empty-schema conformance while observing one unit value. -/
def current : SqliteVerifier.Interpretation Requirements.LogicalState :=
  ⟨SqliteVerifier.Conforms [], fun _ => some ()⟩
end Interpretation
