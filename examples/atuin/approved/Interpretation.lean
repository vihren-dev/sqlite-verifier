import Requirements

/-! The approved initial interpretation is pinned to generated schema.sql.
Complete decoder-definedness is an explicit condition on starting storage. -/
namespace Interpretation
open SqliteVerifier

/-- Every stored history must decode; malformed rows cannot silently disappear. -/
def admitted (database : Database) : Prop :=
  ∃ histories, HistoryMapping.observe database = some histories

/-- The current business reader uses the exact generated starting representation. -/
def current : Interpretation Requirements.LogicalState where
  invariant := HistoryMapping.representation Generated.startSchema
  observe := HistoryMapping.observe

end Interpretation
