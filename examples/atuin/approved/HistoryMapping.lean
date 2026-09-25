import SchemaBinding
import HistoryDecoding

/-! The approved mapping reads the complete pre-migration business model from
storage. Undefined decoding rejects the complete observation. -/
namespace HistoryMapping
open SqliteVerifier HistoryModel

/-- Every physical history row contributes one decoded business entry. -/
def observe (database : Database) : Option (List History) := do
  let table ← database "history"
  HistoryDecoding.decodeRows (table.project SchemaBinding.fields)

/-- Schema conformance and complete decoding establish the represented business state. -/
def representation (schema : Schema) (database : Database) : Prop :=
  Conforms schema database ∧ ∃ histories, observe database = some histories

/-- Every canonical observation lies in the independent business model's domain. -/
theorem observe_valid (observed : observe database = some histories) :
    ∀ history ∈ histories, history.Valid := by
  unfold observe at observed
  simp only [bind, Option.bind_eq_some_iff] at observed
  obtain ⟨table, _, decoded⟩ := observed
  exact HistoryDecoding.decodeRows_valid decoded

end HistoryMapping
