import HistoryMapping

/-! Reusable preservation requirements concern only the pre-migration business
model. The resulting storage layout is the candidate interpretation's responsibility. -/
namespace Requirements
open SqliteVerifier HistoryModel

/-- Application state contains histories, independent of SQL bookkeeping and rowids. -/
abbrev LogicalState := List History
/-- Application identifiers and numeric fields lie in the documented business domain. -/
def valid (histories : LogicalState) : Prop := ∀ history ∈ histories, history.Valid
/-- Require successful execution and business equality without prescribing a future schema. -/
def contract : LogicalContract LogicalState := .preservation valid

end Requirements
