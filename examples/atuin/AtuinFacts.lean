import NextInterpretation

set_option doc.verso true

/-! Candidate-specific schema facts and arbitrary-row ADD correctness.
Changing the added column changes these candidate proofs, never approved meaning. -/
namespace AtuinFacts
open Belay.Sqlite SqliteVerifier

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

/-- Every table with the approved history columns covers every name in
{name}`SchemaBinding.fields`. The proof turns membership in the column-name
list into a checked column index; rows impose no premise. -/
theorem covers {table : Table} (columns : table.shape.columns = SchemaBinding.history.shape.columns) :
    Covers table SchemaBinding.fields := by
  intro name member
  have names : SchemaBinding.fields = SchemaBinding.history.shape.columns.map Column.name := rfl
  rw [names] at member
  rw [columns]
  obtain ⟨column, named, equal⟩ := List.mem_map.mp member
  exact ⟨_, List.findIdx?_eq_some_of_exists ⟨column, named, by simp [equal]⟩⟩

/-- For every database conforming to {name}`SchemaBinding.start`, there exists
a present history table with the approved columns and table validity. The computed
SQL result is successful with its NULL extension, and that result conforms to
{name}`Generated.nextSchema`. The proof recovers the table from conformance,
checks ADD applicability and applies schema conformance preservation. -/
theorem payload {database : Database} (conforms : Conforms SchemaBinding.start database) :
    ∃ table, database "history" = some table ∧ table.shape.columns = SchemaBinding.history.shape.columns ∧
      table.Valid ∧ runSql Generated.script database =
        .success (database.set "history" (table.appendColumns [added])) ∧
      Conforms Generated.nextSchema (database.set "history" (table.appendColumns [added])) := by
  obtain ⟨table, present, columns, valid⟩ := conforms.table (name := "history") (by rfl)
  refine ⟨table, present, columns, valid, ?_, ?_⟩
  · have size : ¬table.shape.columns.length ≥ maximumColumns := by rw [columns]; decide +kernel
    have fresh : table.shape.columns.any (fun old => old.name == added.name) = false := by
      rw [columns]; decide +kernel
    have nameAllowed : supportedTableName "history" = true := by decide +kernel
    have columnAllowed : supportedColumn added = true := by decide +kernel
    have plain : added.plain = true := by decide +kernel
    simp [runSql, runSqlFrom, advance, literalStep, SqlState.finish, script_bound, step, nameAllowed, columnAllowed, plain, present, size, fresh]
  · rw [next_bound]
    exact conforms.appendAt present (next_bound ▸ next_valid) (by rw [columns]; decide +kernel)

/-- For every present, valid history table with the approved columns, if the
before database observes a logical value, setting its NULL extension observes
the same value. The premise is vacuous for an undefined before observation.
The proof preserves the named old-field projection and reuses its decoder result. -/
theorem observed (present : database "history" = some history)
    (columns : history.shape.columns = SchemaBinding.history.shape.columns) (valid : history.Valid)
    (before : HistoryMapping.observe database = some logical) :
    HistoryMapping.observe (database.set "history" (history.appendColumns [added])) = some logical := by
  have unchanged : (history.appendColumns [added]).project SchemaBinding.fields =
      history.project SchemaBinding.fields :=
    TableExtends.project ⟨[added], rfl⟩ (fun row member => (valid.2.2 row member).2) (covers columns)
  simpa [HistoryMapping.observe, Database.set, unchanged] using
    (show HistoryDecoding.decodeRows (history.project SchemaBinding.fields) = some logical by
      simpa [HistoryMapping.observe, present] using before)

end AtuinFacts
