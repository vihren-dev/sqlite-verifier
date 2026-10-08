import SqliteVerifier.ApplicationKeyDemonstration

set_option doc.verso true

/-! This engineering variant chooses distinct non-NULL amounts as logical
invoice keys. Native SQL uniqueness is not inferred from this logical policy. -/

namespace Requirements

/-- Rowid-free key/protected-cell records. The selected key and protected field
are both amount; comparison preserves every record up to permutation. -/
abbrev LogicalState := SqliteVerifier.ApplicationKeyRows

/-- Require the invoice note schema, successful execution, valid keys and
permutation of the original keyed records. Failure safety retains permutation;
the complete proof establishes that modeled failure is unreachable. -/
def contract : SqliteVerifier.LogicalContract LogicalState :=
  SqliteVerifier.ApplicationKeyDemonstration.requirements

end Requirements
