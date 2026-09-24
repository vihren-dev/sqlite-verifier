import Interpretation

/-! Candidate interpretation for the empty-script test. -/
namespace NextInterpretation
/-- No-op execution keeps the approved interpretation. -/
def next := Interpretation.current
/-- The empty script cannot fail; the declared failure representation is still sound. -/
def failures : SqliteVerifier.FailureRepresentation Requirements.LogicalState :=
  ⟨fun _ _ => [], fun _ _ => Interpretation.current⟩
end NextInterpretation
