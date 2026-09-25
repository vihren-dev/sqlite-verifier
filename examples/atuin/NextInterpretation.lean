import Interpretation
import SqlInputs

/-! Candidate meaning reads the resulting storage; no old database is captured. -/
namespace NextInterpretation
open SqliteVerifier

/-- Successful and committed-error observations include actual resulting shell values. -/
def next : Interpretation Requirements.LogicalState where
  invariant := Conforms Generated.nextSchema
  observe := observeNullable "history" AtuinSchema.fields (some "shell")

/-- Rolled-back errors retain the old representation; committed errors use the new one. -/
def failures : FailureRepresentation Requirements.LogicalState where
  schema _ reason := if Requirements.committed reason then Generated.nextSchema else AtuinSchema.start
  interpretation _ reason := if Requirements.committed reason then next else Interpretation.current

end NextInterpretation
