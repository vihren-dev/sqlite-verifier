import Interpretation

/-! Empty and populated accepted states show the protected assumptions are
inhabited, without restricting the universal proof to these fixtures. -/
namespace AtuinWitness
open SqliteVerifier

/-- Canonical application UUIDs and distinct timestamps form decodable histories. -/
def historyRows : List Row := [
  ⟨-1, [.text "00000000000000000000000000000001".toUTF8.toList, .integer 1, .integer 0, .integer 0, .text [97], .text [], .text [],
    .text [], .null, .null, .null]⟩,
  ⟨7, [.text "00000000000000000000000000000002".toUTF8.toList, .integer 2, .integer 0, .integer 0, .text [97], .text [], .text [],
    .text [], .null, .null, .null]⟩]

/-- Independent typed meaning of each populated fixture entry. -/
def businessEntry (id : String) (timestamp : Int) : HistoryModel.History :=
  ⟨⟨id⟩, timestamp, 0, 0, "a", "", "", ⟨"", "unknown-user"⟩, "", none, none⟩
/-- Business expectations contain no physical rowid or bookkeeping fields. -/
def businessRows : List HistoryModel.History := [
  businessEntry "00000000000000000000000000000001" 1,
  businessEntry "00000000000000000000000000000002" 2]

/-- History rows retain all eleven fields and every approved declaration. -/
def history (rows : List Row) : Table :=
  ⟨SchemaBinding.history.columns, rows, SchemaBinding.history.properties⟩
/-- Witnesses contain only the declared application storage. -/
def database (rows : List Row) : Database :=
  SchemaBinding.start.emptyDatabase.set "history" (history rows)
/-- Empty application history is a defined business state. -/
def emptyState : Database := database []
/-- Nonempty application history uses two actual application identities. -/
def populatedState : Database := database historyRows

/-- The complete source-linked baseline is an admitted ordinary schema. -/
theorem start_valid : SchemaBinding.start.Valid := by
  simp [Schema.Valid, SchemaBinding.start]
  decide +kernel
/-- Replacing only row collections preserves the complete declared schema. -/
theorem conforms (rows : List Row) (valid : (history rows).Valid) :
    Conforms SchemaBinding.start (database rows) :=
  (SchemaBinding.start.emptyDatabase_conforms start_valid).replaceRows
    (name := "history") (by rfl) (by rfl) (by rfl) valid

/-- Empty history satisfies storage validity and complete decoder-definedness. -/
theorem empty_admitted : Admitted SchemaBinding.start Interpretation.admitted emptyState :=
  ⟨conforms [] (by simp [history, Table.Valid, validRowid, SchemaBinding.history]; decide +kernel),
    ⟨[], rfl⟩⟩
/-- A populated witness rules out preservation arguments covering only empty histories. -/
theorem populated_admitted : Admitted SchemaBinding.start Interpretation.admitted populatedState :=
  ⟨conforms historyRows (by simp [history, historyRows, Table.Valid, validRowid, SchemaBinding.history]; decide +kernel),
    ⟨businessRows, by decide +kernel⟩⟩
/-- Business observation contains both histories, without physical rowids. -/
theorem populated_observed : ∃ histories, Interpretation.current.observe populatedState = some histories ∧
    histories.length = 2 := by exact ⟨businessRows, by decide +kernel, rfl⟩
/-- Empty history is a defined empty state, not an undefined interpretation. -/
theorem empty_observed : Interpretation.current.observe emptyState = some [] := rfl

end AtuinWitness
