import Interpretation
import SqlInputs

set_option doc.verso true

/-! Candidate observations select the generated next schema and retain the
approved logical key policy over actual result storage. -/

namespace NextInterpretation

/-- Observe the same application-key policy under the generated next schema.
The invariant requires conformance and a defined read of every keyed invoice. -/
def next : SqliteVerifier.Interpretation Requirements.LogicalState :=
  SqliteVerifier.applicationKeyInterpretation Generated.nextSchema
    SqliteVerifier.ApplicationKeyDemonstration.invoiceTableName
    SqliteVerifier.ApplicationKeyDemonstration.invoiceKeyNames
    SqliteVerifier.ApplicationKeyDemonstration.invoiceProtectedFields

/-- Every failure position and reason uses an impossible invariant. The full
certificate must establish successful applicability for every admitted database. -/
def failures : SqliteVerifier.FailureRepresentation Requirements.LogicalState :=
  SqliteVerifier.unreachableFailures

end NextInterpretation
