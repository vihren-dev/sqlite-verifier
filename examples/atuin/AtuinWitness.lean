import Interpretation

/-! Concrete accepted databases show that the proposed SQL-only assumptions are
inhabited. They do not restrict the arbitrary-history universal obligation. -/
namespace AtuinWitness
open SqliteVerifier

/-- Six successful identities retain ordinary metadata values and distinct physical rowids. -/
def metadataRows : List Row := AtuinCatalog.prior.zipIdx.map fun (identity, index) =>
  ⟨Int.ofNat (index + 1), [.integer identity.1, .text [],
    .text "2026-09-25 00:00:00".toUTF8.toList, .integer 1, .blob identity.2, .integer 0]⟩

/-- The selected rows inhabit the approved ordinary bookkeeping schema. -/
def metadata : Table :=
  ⟨SchemaBinding.metadata.columns, metadataRows, SchemaBinding.metadata.properties⟩

/-- Canonical application UUIDs and distinct timestamps form decodable histories. -/
def historyRows : List Row := [
  ⟨-1, [.text "00000000000000000000000000000001".toUTF8.toList, .integer 1, .integer 0, .integer 0, .text [97], .text [], .text [],
    .text [], .null, .null, .null]⟩,
  ⟨7, [.text "00000000000000000000000000000002".toUTF8.toList, .integer 2, .integer 0, .integer 0, .text [97], .text [], .text [],
    .text [], .null, .null, .null]⟩]

/-- Independent typed meaning of each populated fixture entry. -/
def businessEntry (id : String) (timestamp : Int) : HistoryModel.History :=
  ⟨⟨id⟩, timestamp, 0, 0, "a", "", "", ⟨"", "unknown-user"⟩, "", none, none, none⟩
/-- Business expectations contain no physical rowid or metadata fields. -/
def businessRows : List HistoryModel.History := [
  businessEntry "00000000000000000000000000000001" 1,
  businessEntry "00000000000000000000000000000002" 2]

/-- History rows retain all eleven fields and every approved declaration. -/
def history (rows : List Row) : Table :=
  ⟨SchemaBinding.history.columns, rows, SchemaBinding.history.properties⟩

/-- No undeclared tables or hidden framework state enter these witnesses. -/
def database (rows : List Row) : Database :=
  (SchemaBinding.start.emptyDatabase.set "_sqlx_migrations" metadata).set "history" (history rows)

/-- Empty application history still has all six actual prior records. -/
def emptyState : Database := database []
/-- Nonempty application history uses two actual application identities. -/
def populatedState : Database := database historyRows

/-- The complete source-linked baseline is an admitted ordinary schema. -/
theorem start_valid : SchemaBinding.start.Valid := by
  simp [Schema.Valid, SchemaBinding.start]
  decide +kernel
/-- Existing metadata widths and physical identities satisfy model schema validity. -/
theorem metadata_valid : metadata.Valid := by
  simp [Table.Valid, metadata, metadataRows, AtuinCatalog.prior, validRowid]
  decide +kernel
/-- Successful identity coverage and native key/NULL constraints are simultaneously inhabited. -/
theorem metadata_invariant : AtuinCatalog.Invariant AtuinCatalog.prior metadata := by
  unfold AtuinCatalog.Invariant AtuinCatalog.recorded
  decide +kernel
/-- The normal allocator has a signed representable next identity. -/
theorem allocation_valid : validRowid (LiteralData.nextRowid metadata.rows) := by
  unfold validRowid
  decide +kernel

/-- Replacing only row collections preserves the full declared schema. -/
theorem conforms (rows : List Row) (valid : (history rows).Valid) :
    Conforms SchemaBinding.start (database rows) := by
  have base := SchemaBinding.start.emptyDatabase_conforms start_valid
  have catalog := base.replaceRows (name := "_sqlx_migrations") (by rfl) (by rfl) (by rfl) metadata_valid
  exact catalog.replaceRows (name := "history") (by rfl) (by rfl) (by rfl) valid

/-- Admission includes complete typed decoding, not merely storage validity. -/
theorem ready (rows : List Row)
    (defined : ∃ histories, HistoryMapping.observe false (database rows) = some histories) :
    Interpretation.admitted (database rows) :=
  ⟨defined, metadata, rfl, metadata_invariant, allocation_valid⟩

/-- Empty history still satisfies all six catalog identities and decoding-definedness. -/
theorem empty_admitted : Admitted SchemaBinding.start Interpretation.admitted emptyState :=
  ⟨conforms [] (by simp [history, Table.Valid, validRowid, SchemaBinding.history]; decide +kernel),
    ready [] ⟨_, rfl⟩⟩
/-- The populated witness rules out a preservation argument covering only empty histories. -/
theorem populated_admitted : Admitted SchemaBinding.start Interpretation.admitted populatedState :=
  ⟨conforms historyRows (by simp [history, historyRows, Table.Valid, validRowid, SchemaBinding.history]; decide +kernel),
    ready historyRows ⟨businessRows, by decide +kernel⟩⟩

/-- The actual current representation combines schema, typed decoding and metadata facts. -/
theorem current_invariant (rows : List Row) (valid : (history rows).Valid)
    (defined : ∃ histories, HistoryMapping.observe false (database rows) = some histories) :
    Interpretation.current.invariant (database rows) :=
  ⟨conforms rows valid, defined, metadata, rfl, metadata_invariant⟩
/-- Empty history is accepted by the actual current interpretation. -/
theorem empty_current : Interpretation.current.invariant emptyState :=
  current_invariant [] (by simp [history, Table.Valid, validRowid, SchemaBinding.history]; decide +kernel) ⟨_, rfl⟩
/-- Populated history is accepted by the actual current interpretation. -/
theorem populated_current : Interpretation.current.invariant populatedState :=
  current_invariant historyRows
    (by simp [history, historyRows, Table.Valid, validRowid, SchemaBinding.history]; decide +kernel) ⟨businessRows, by decide +kernel⟩

/-- Business observation contains both histories, without physical rowids or bookkeeping rows. -/
theorem populated_observed : ∃ histories, Interpretation.current.observe populatedState = some histories ∧
    histories.length = 2 := by exact ⟨businessRows, by decide +kernel, rfl⟩
/-- Empty history is a defined empty business state, not an undefined interpretation. -/
theorem empty_observed : Interpretation.current.observe emptyState = some [] := rfl
/-- The representation independently retains all six actual bookkeeping records. -/
theorem metadata_count : metadata.rows.length = 6 := rfl

end AtuinWitness
