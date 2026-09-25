import SqliteVerifier.RunnerProfile

/-! Conservative data-only maintenance preserves exact schemas and all storage
outside explicitly named tables. No maintenance predicate can erase history. -/

namespace SqliteVerifier

/-- Only native statistics rows may be refreshed by optimize-on-close. -/
def statisticsNames : List String := ["sqlite_stat1", "sqlite_stat4"]

/-- A data-only footprint retains definitions, validity, and every unlisted table. -/
structure RowsChange (names : List String) (before after : Database) : Prop where
  columns : ∀ name, (after name).map Table.columns = (before name).map Table.columns
  properties : ∀ name, (after name).map Table.properties = (before name).map Table.properties
  valid : ∀ name table, after name = some table → table.Valid
  other : ∀ name, name ∉ names → after name = before name

/-- Doing no maintenance is always permitted on model-conforming storage. -/
theorem RowsChange.refl (conforms : Conforms schema database) :
    RowsChange names database database :=
  ⟨fun _ => rfl, fun _ => rfl, fun name table present =>
    ((conforms.2 name).2 table present).1, fun _ _ => rfl⟩

/-- A data-only maintenance step preserves the complete finite schema. -/
theorem RowsChange.conforms (change : RowsChange names before after)
    (conforms : Conforms schema before) : Conforms schema after := by
  refine ⟨conforms.1, ?_⟩
  intro name
  refine ⟨(change.columns name).trans (conforms.2 name).1, ?_⟩
  intro table present
  refine ⟨change.valid name table present, ?_⟩
  have shape := change.properties name
  cases old : before name with
  | none => simp [old, present] at shape
  | some previous =>
    have same : table.properties = previous.properties := by simpa [old, present] using shape
    rw [same]
    exact ((conforms.2 name).2 previous old).2

/-- Replacing rows in one existing table cannot alter any other schema object. -/
theorem Conforms.replaceRows {schema : Schema} {database : Database} {name : String}
    {old replacement : Table} (conforms : Conforms schema database)
    (present : database name = some old) (columns : replacement.columns = old.columns)
    (properties : replacement.properties = old.properties) (valid : replacement.Valid) :
    Conforms schema (database.set name replacement) := by
  refine ⟨conforms.1, ?_⟩
  intro other
  by_cases same : other = name
  · subst other
    refine ⟨?_, ?_⟩
    · simpa [Database.set, present, columns] using (conforms.2 name).1
    · intro table stored
      have equal : table = replacement := by simpa [Database.set] using stored.symm
      subst table
      exact ⟨valid, by simpa [properties] using ((conforms.2 name).2 old present).2⟩
  · simpa [Database.set, same] using conforms.2 other

/-- SQLx retains old metadata rows and adds one exact successful record. Native
rowid allocation and physical enumeration are overapproximated by a permutation. -/
structure MetadataInserted (migration : SqlxMigration) (old replacement : Table)
    (elapsed : Int) : Prop where
  columns : replacement.columns = old.columns
  properties : replacement.properties = old.properties
  valid : replacement.Valid
  rows : ∃ rowid timestamp, replacement.rows.Perm (old.rows ++ [
    ⟨rowid, [.integer migration.version, .text migration.description, .text timestamp,
      .integer 1, .blob migration.checksum, .integer elapsed]⟩])
  elapsedBound : validRowid elapsed

end SqliteVerifier
