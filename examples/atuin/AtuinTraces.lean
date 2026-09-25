import AtuinWitness

/-! Concrete populated traces establish inhabitation of both committed branches.
These are model witnesses; independent SQLx/native trace evidence is reported separately. -/
namespace AtuinTraces
open SqliteVerifier

/-- The witness has one newly allocated physical metadata row and the exact bound target. -/
def recorded (elapsed : Int) : Table :=
  { AtuinWitness.metadata with rows := AtuinWitness.metadata.rows ++ [
    ⟨7, [.integer AtuinCatalog.config.migration.version,
      .text AtuinCatalog.config.migration.description, .text "2026-09-25 00:00:00".toUTF8.toList,
      .integer 1, .blob AtuinCatalog.config.migration.checksum, .integer elapsed]⟩] }

/-- The complete bookkeeping extension is possible for any bounded elapsed value. -/
theorem inserted (elapsed : Int) (bounded : validRowid elapsed) :
    MetadataInserted AtuinCatalog.config.migration AtuinWitness.metadata (recorded elapsed) elapsed := by
  refine ⟨rfl, rfl, ?_, ⟨7, "2026-09-25 00:00:00".toUTF8.toList, List.Perm.refl _⟩, bounded⟩
  simp [recorded, AtuinWitness.metadata, AtuinWitness.metadataRows,
    AtuinCatalog.config, Table.Valid, validRowid]
  decide +kernel

/-- Result storage contains the actual added history values and seven metadata records. -/
def completed (rows : List Row) (elapsed : Int) : Database :=
  ((AtuinWitness.database rows).set "history"
    ((AtuinWitness.history rows).appendColumns [AtuinSchema.shell])).set
      "_sqlx_migrations" (recorded elapsed)

/-- A complete committed run exists without changing statistics rows. -/
theorem committed (rows : List Row) (valid : (AtuinWitness.history rows).Valid)
    (completion : CommittedResult) (bounded : validRowid completion.elapsed) :
    ProfileExecutes (.sqlite346Sqlx AtuinCatalog.config) AtuinSchema.payload
      (AtuinWitness.database rows) (completion.outcome 1 (completed rows completion.elapsed)) := by
  obtain ⟨table, present, _, _, execution, conforming⟩ :=
    AtuinFacts.payload (AtuinWitness.conforms rows valid)
  have equal : table = AtuinWitness.history rows := by
    simpa [AtuinWitness.database, Database.set] using present.symm
  subst table
  have metadataPresent : ((AtuinWitness.database rows).set "history"
      ((AtuinWitness.history rows).appendColumns [AtuinSchema.shell])) "_sqlx_migrations" =
      some AtuinWitness.metadata := by simp [AtuinWitness.database, Database.set]
  have replacement := inserted completion.elapsed bounded
  exact .committed execution metadataPresent replacement (RowsChange.refl
    (conforming.replaceRows metadataPresent replacement.columns replacement.properties replacement.valid))

/-- Nonempty history can reach actual success under the same admitted starting predicate. -/
theorem successful : ProfileExecutes (.sqlite346Sqlx AtuinCatalog.config) AtuinSchema.payload
    (AtuinWitness.database AtuinWitness.historyRows)
    (.success (completed AtuinWitness.historyRows 0)) := by
  apply committed AtuinWitness.historyRows _ (.success 0) (by simp [CommittedResult.elapsed, validRowid])
  exact ((AtuinWitness.populated_admitted.1.2 "history").2 _ (by rfl)).1

/-- Failure of the post-commit timing update still contains the added column and -1 sentinel. -/
theorem timingFailed : ProfileExecutes (.sqlite346Sqlx AtuinCatalog.config) AtuinSchema.payload
    (AtuinWitness.database AtuinWitness.historyRows)
    (.failure 1 (.runnerFailure .timingUpdate true) (completed AtuinWitness.historyRows (-1))) := by
  apply committed AtuinWitness.historyRows _ .timingFailure (by simp [CommittedResult.elapsed, validRowid])
  exact ((AtuinWitness.populated_admitted.1.2 "history").2 _ (by rfl)).1

/-- Both populated outcomes retain two history rows and append exactly one metadata row. -/
theorem counts (elapsed : Int) :
    ((completed AtuinWitness.historyRows elapsed) "history").map (fun table => table.rows.length) = some 2 ∧
    ((completed AtuinWitness.historyRows elapsed) "_sqlx_migrations").map
      (fun table => table.rows.length) = some 7 := by exact ⟨rfl, rfl⟩

#print axioms successful
#print axioms timingFailed
end AtuinTraces
