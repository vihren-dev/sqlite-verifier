import SchemaBinding
import AtuinCatalog
import HistoryDecoding

/-! The approved representation ties the independent application model to actual
schema-derived column reads. Undefined decoding rejects the complete database view. -/
namespace HistoryMapping
open SqliteVerifier HistoryModel

/-- Every stored history contributes one decoded business entry; shell is read when present. -/
def observe (shell : Bool) (database : Database) : Option (List History) := do
  let table ← database "history"
  let histories ← HistoryDecoding.decodeRows (table.project SchemaBinding.fields)
  if shell then HistoryDecoding.attachShell histories (table.project ["shell"])
  else pure histories

/-- Actual successful migration facts accompany the representation, not business entities. -/
def catalog (expected : List AtuinCatalog.Identity) (database : Database) : Prop :=
  ∃ metadata, database "_sqlx_migrations" = some metadata ∧ AtuinCatalog.Invariant expected metadata

/-- Schema conformance, complete decoding, and actual catalog facts establish a representation. -/
def representation (schema : Schema) (shell : Bool) (expected : List AtuinCatalog.Identity)
    (database : Database) : Prop :=
  Conforms schema database ∧ (∃ histories, observe shell database = some histories) ∧ catalog expected database

/-- Every canonical observation lies in the independent business model's domain. -/
theorem observe_valid (observed : observe shell database = some histories) :
    ∀ history ∈ histories, history.Valid := by
  unfold observe at observed
  simp only [bind, Option.bind_eq_some_iff] at observed
  obtain ⟨table, stored, decoded, read, attached⟩ := observed
  cases shell with
  | false =>
    simp only [Bool.false_eq_true, ↓reduceIte, pure, Option.some.injEq] at attached
    subst histories
    exact HistoryDecoding.decodeRows_valid read
  | true =>
    exact HistoryDecoding.attachShell_valid (HistoryDecoding.decodeRows_valid read) attached

end HistoryMapping
