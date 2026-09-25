import SqliteVerifier.Library

/-! Human-reviewable engineering requirements, independent of candidate inputs. -/
namespace Requirements

/-- Every invoice rowid and selected amount is an approved logical observation. -/
abbrev LogicalState := SqliteVerifier.LogicalRows

/-- Permit precisely the expected third-statement error and preserve invoice observations. -/
def contract : SqliteVerifier.LogicalContract LogicalState where
  valid := fun _ => True
  change := Eq
  schemaRequirement schema := schema.lookup "invoices" =
    some [{ name := "amount", affinity := .integer }, { name := "note", affinity := .text }]
  failure := fun before _ _ after => before = after
  applicability := fun _ outcome =>
    match outcome with
    | .failure 2 (.tableExists "audit") _ => True
    | _ => False

end Requirements
