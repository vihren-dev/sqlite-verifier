import NextInterpretation

/-! Candidate-specific schema facts and arbitrary-row ADD correctness.
Changing the added column changes these candidate proofs, never approved meaning. -/
namespace AtuinFacts
open SqliteVerifier

/-- The proposed nullable field is a candidate choice, outside the approved contract. -/
def added : Column := { name := "shell", affinity := .text }
/-- The supplied SQL is exactly this single supported extension. -/
theorem script_bound : Generated.script = [.addColumn "history" added] := by rfl
/-- The generated result retains the starting declarations and appends the proposed column. -/
theorem next_bound : Generated.nextSchema = SchemaBinding.start.appendAt "history" [added] := by rfl
/-- All actual retained declarations and indexes remain supported. -/
theorem next_valid : Generated.nextSchema.Valid := by
  simp [Schema.Valid, Generated.nextSchema]
  decide +kernel

/-- Any represented history table covers all eleven protected names. -/
theorem covers {table : Table} (columns : table.columns = SchemaBinding.history.columns) :
    Covers table SchemaBinding.fields := by
  intro name member
  have names : SchemaBinding.fields = SchemaBinding.history.columns.map Column.name := rfl
  rw [names] at member
  rw [columns]
  obtain ⟨column, named, equal⟩ := List.mem_map.mp member
  exact ⟨_, List.findIdx?_eq_some_of_exists ⟨column, named, by simp [equal]⟩⟩

/-- ADD succeeds for arbitrary old rows and preserves full resulting-schema conformance. -/
theorem payload {database : Database} (conforms : Conforms SchemaBinding.start database) :
    ∃ table, database "history" = some table ∧ table.columns = SchemaBinding.history.columns ∧
      table.Valid ∧ run Generated.script database =
        .success (database.set "history" (table.appendColumns [added])) ∧
      Conforms Generated.nextSchema (database.set "history" (table.appendColumns [added])) := by
  obtain ⟨table, present, columns, valid⟩ := conforms.table (name := "history") (by rfl)
  refine ⟨table, present, columns, valid, ?_, ?_⟩
  · have size : ¬table.columns.length ≥ maximumColumns := by rw [columns]; decide +kernel
    have fresh : table.columns.any (fun old => old.name == added.name) = false := by
      rw [columns]; decide +kernel
    have nameAllowed : supportedTableName "history" = true := by decide +kernel
    have columnAllowed : supportedColumn added = true := by decide +kernel
    have plain : added.plain = true := by decide +kernel
    simp [run, runFrom, script_bound, step, nameAllowed, columnAllowed, plain, present, size, fresh]
  · rw [next_bound]
    exact conforms.appendAt present (next_bound ▸ next_valid) (by rw [columns]; decide +kernel)

/-- Reading the old business fields ignores new columns and preserves every row in order. -/
theorem observed (present : database "history" = some history)
    (columns : history.columns = SchemaBinding.history.columns) (valid : history.Valid)
    (before : HistoryMapping.observe database = some logical) :
    HistoryMapping.observe (database.set "history" (history.appendColumns [added])) = some logical := by
  have unchanged : (history.appendColumns [added]).project SchemaBinding.fields =
      history.project SchemaBinding.fields :=
    TableExtends.project ⟨[added], rfl⟩ (fun row member => (valid.2.2 row member).2) (covers columns)
  simpa [HistoryMapping.observe, Database.set, unchanged] using
    (show HistoryDecoding.decodeRows (history.project SchemaBinding.fields) = some logical by
      simpa [HistoryMapping.observe, present] using before)

end AtuinFacts
