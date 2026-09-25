import Interpretation
import SqlInputs

/-! The candidate reads the old business model solely from resulting storage.
New columns need not be business fields in the protected pre-migration model. -/
namespace NextInterpretation
open SqliteVerifier

/-- Recover all pre-migration business fields from the actual resulting schema. -/
def next : Interpretation Requirements.LogicalState where
  invariant := HistoryMapping.representation Generated.nextSchema
  observe := HistoryMapping.observe

/-- Successful execution is proved separately; no failing state is assumed inhabited. -/
def failures : FailureRepresentation Requirements.LogicalState := unreachableFailures

end NextInterpretation
