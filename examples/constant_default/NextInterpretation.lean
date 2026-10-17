import Interpretation
import SqlInputs

set_option doc.verso true

/-! Read the protected invoice amounts after initializing priority. -/
namespace NextInterpretation

/-- Every resulting invoice remains represented by its rowid and amount.
The invariant requires conformance to the resulting catalog and coverage of amount. -/
def next : SqliteVerifier.Interpretation Requirements.LogicalState :=
  SqliteVerifier.projectedInterpretation Generated.profile Generated.nextCatalog "invoices" ["amount"]

/-- No failure is represented: the proof must establish successful execution. -/
def failures : SqliteVerifier.FailureRepresentation Requirements.LogicalState :=
  SqliteVerifier.unreachableFailures

end NextInterpretation
