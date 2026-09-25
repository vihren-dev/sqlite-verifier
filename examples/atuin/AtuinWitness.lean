import AtuinFacts

/-! Explicit empty and nonempty native-shaped witnesses rule out inconsistent readiness.
The universal theorem is independent of these selected rows. -/
namespace AtuinWitness
open SqliteVerifier

/-- Six successful prior records carry the actual approved version/checksum identities. -/
def metadataRows : List Row := AtuinCatalog.config.previous.zipIdx.map fun (identity, index) =>
  ⟨Int.ofNat (index + 1), [.integer identity.version, .text [],
    .text "2026-09-25 00:00:00".toUTF8.toList, .integer 1, .blob identity.checksum, .integer 0]⟩

/-- Bookkeeping fields and constraints match the actual SQLx table exactly. -/
def metadata : Table :=
  ⟨sqlxMetadataColumns, metadataRows, sqlxMetadataProperties⟩

/-- Explicit NULL text primary keys have distinct physical rowids and distinct UNIQUE tuples. -/
def historyRows : List Row := [
  ⟨-1, [.null, .integer 1, .integer 0, .integer 0, .text [97], .text [], .text [],
    .text [], .null, .null, .null]⟩,
  ⟨7, [.null, .integer 2, .integer 0, .integer 0, .text [97], .text [], .text [],
    .text [], .null, .null, .null]⟩]

/-- Arbitrary witnessed history rows do not change catalog readiness or the full schema. -/
def history (rows : List Row) : Table :=
  ⟨AtuinSchema.history.columns, rows, AtuinSchema.history.properties⟩

/-- Both statistics tables exist even when they currently have no sampled rows. -/
def database (rows : List Row) : Database :=
  (AtuinSchema.start.emptyDatabase.set "_sqlx_migrations" metadata).set "history" (history rows)

/-- Actual fixed catalog entries satisfy ordered int64 versions and SHA-384 widths. -/
theorem config_valid : AtuinCatalog.config.Valid := by
  simp [SqlxConfig.Valid, AtuinCatalog.config, validRowid]

/-- The old metadata has unique bounded physical identities and exact row widths. -/
theorem metadata_valid : metadata.Valid := by
  simp [Table.Valid, metadata, metadataRows, AtuinCatalog.config, validRowid]
  decide +kernel

/-- Replacing only rows retains every captured table/index declaration. -/
theorem conforms (rows : List Row) (valid : (history rows).Valid) :
    Conforms AtuinSchema.start (database rows) := by
  have base := AtuinSchema.start.emptyDatabase_conforms AtuinFacts.start_valid
  have catalog := base.replaceRows (name := "_sqlx_migrations") (by rfl) (by rfl) (by rfl) metadata_valid
  exact catalog.replaceRows (name := "history") (by rfl) (by rfl) (by rfl) valid

/-- Readiness witnesses every required catalog/statistics lookup; no empty-metadata shortcut. -/
theorem ready (rows : List Row) : Interpretation.admitted (database rows) := by
  refine ⟨config_valid, by decide +kernel, ?_, metadata, rfl, rfl, rfl, ?_⟩
  · intro name fields member
    simp only [List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨_, rfl, rfl, rfl⟩
    · exact ⟨_, rfl, rfl, rfl⟩
  · exact List.Perm.refl _

/-- The same complete readiness admits zero history records. -/
theorem empty_admitted : Admitted AtuinSchema.start Interpretation.admitted (database []) := by
  exact ⟨conforms [] (by simp [history, Table.Valid]; decide +kernel), ready []⟩

/-- It also admits actual data, including the nullable-primary-key corner case. -/
theorem populated_admitted : Admitted AtuinSchema.start Interpretation.admitted (database historyRows) := by
  refine ⟨conforms historyRows ?_, ready historyRows⟩
  simp [history, historyRows, Table.Valid, AtuinSchema.history, validRowid]
  decide +kernel

/-- The admitted example has two distinct physical records, not a vacuous empty view. -/
theorem populated_rows : ((database historyRows) "history").map (fun table => table.rows.length) = some 2 := rfl

end AtuinWitness
