import Requirements

/-! The approved initial interpretation is pinned to generated schema.sql.
Data facts and decoder-definedness are explicit conditions, never profile settings. -/
namespace Interpretation
open SqliteVerifier

/-- Complete decoding and six successful identities hold before the selected pending migration. -/
def admitted (database : Database) : Prop :=
  (∃ histories, HistoryMapping.observe false database = some histories) ∧
  ∃ metadata, database "_sqlx_migrations" = some metadata ∧
    AtuinCatalog.Invariant AtuinCatalog.prior metadata ∧
    validRowid (LiteralData.nextRowid metadata.rows)

/-- The current business reader is attached to the exact generated starting representation. -/
def current : Interpretation Requirements.LogicalState where
  invariant := HistoryMapping.representation Generated.startSchema false AtuinCatalog.prior
  observe := HistoryMapping.observe false

end Interpretation
