import Interpretation
import SqlInputs

/-! The new schema reads real shell cells into the same independent business model. -/
namespace NextInterpretation
open SqliteVerifier

/-- The proposed representation includes the new actual column and seventh successful identity. -/
def next : Interpretation Requirements.LogicalState where
  invariant := HistoryMapping.representation Generated.nextSchema true
    (AtuinCatalog.prior ++ [AtuinCatalog.target])
  observe := HistoryMapping.observe true

/-- Success is established by the complete SQL proof, not assumed from an empty failure relation. -/
def failures : FailureRepresentation Requirements.LogicalState := unreachableFailures

end NextInterpretation
