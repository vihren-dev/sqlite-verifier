import Requirements

/-! Approved current meaning is shared unchanged by every example candidate. -/
namespace Interpretation

/-- All model-conforming starting invoice data are admitted. -/
def admitted (_ : SqliteVerifier.Database) : Prop := True

/-- Read every invoice's physical identity and amount directly from storage. -/
def current : SqliteVerifier.Interpretation Requirements.LogicalState :=
  SqliteVerifier.projectedInterpretation
    [{ name := "invoices", columns := [{ name := "amount", affinity := .integer }] }] "invoices" ["amount"]

end Interpretation
