import HistoryMapping

/-! Business requirements preserve decoded command histories. Representation facts
are kept in the mapping; canonical actual reads prevent candidate fabrication. -/
namespace Requirements
open SqliteVerifier HistoryModel

/-- The application state consists of histories, independent of SQL bookkeeping and rowids. -/
abbrev LogicalState := List History

/-- Application identifiers and numeric fields lie in the documented business domain. -/
def valid (histories : LogicalState) : Prop := ∀ history ∈ histories, history.Valid

/-- The selected migration changes representation without changing business history. -/
def change (before after : LogicalState) : Prop := after = before

/-- The actual new representation and actual business meaning satisfy the approved mapping. -/
def resultValid (before after : Database) : Prop :=
  HistoryMapping.representation SchemaBinding.next true
    (AtuinCatalog.prior ++ [AtuinCatalog.target]) after ∧
  ∃ histories, HistoryMapping.observe false before = some histories ∧
    HistoryMapping.observe true after = some histories

/-- This example requires a closed successful script with unchanged actual business meaning. -/
def applicable (before : Database) : Outcome → Prop
  | .success result => resultValid before result
  | _ => False

/-- Business equality and independent representation checks constrain every accepted outcome. -/
def contract : LogicalContract LogicalState where
  valid := valid
  change := change
  schemaRequirement schema := schema = SchemaBinding.next
  failure := fun _ _ _ _ => False
  applicability := applicable

end Requirements
