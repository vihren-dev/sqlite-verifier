import Interpretation
import SqlInputs

/-! A plausible resulting interpretation cannot repair a missing required column. -/
namespace NextInterpretation

/-- The old values are still readable, but the target schema requirement fails. -/
def next : SqliteVerifier.Interpretation Requirements.LogicalState :=
  SqliteVerifier.projectedInterpretation Generated.nextSchema "invoices" ["amount"]

/-- This example asks for successful applicability, as the approved contract requires. -/
def failures : SqliteVerifier.FailureRepresentation Requirements.LogicalState :=
  SqliteVerifier.unreachableFailures

end NextInterpretation
