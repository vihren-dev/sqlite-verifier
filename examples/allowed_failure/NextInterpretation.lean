import Interpretation
import SqlInputs

/-! The committed prefix is represented after the explicitly allowed modeled error. -/
namespace NextInterpretation

/-- Read every protected invoice row from the resulting prefix storage. -/
def next : SqliteVerifier.Interpretation Requirements.LogicalState :=
  SqliteVerifier.projectedInterpretation Generated.nextSchema "invoices" ["amount"]

/-- Every declared failure representation uses the checked prefix schema and reader. -/
def failures : SqliteVerifier.FailureRepresentation Requirements.LogicalState where
  schema := fun _ _ => Generated.nextSchema
  interpretation := fun _ _ => next

end NextInterpretation
