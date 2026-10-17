import NextInterpretation

set_option doc.verso true

/-! Candidate-specific catalog facts and arbitrary-row ADD correctness.
Changing the added column changes these candidate proofs, never approved meaning. -/
namespace AtuinFacts
open Belay.Sqlite SqliteVerifier

/-- The proposed nullable field is a candidate choice, outside the approved contract. -/
def added : CatalogColumn := { name := "shell", declaredType := some "TEXT" }

/-- The supplied SQL resolves to exactly this single supported extension. -/
theorem script_bound : Generated.resolved = [.addColumn 0 added] := by rfl

/-- The generated result retains the starting catalog and appends the proposed column. -/
theorem next_bound : Generated.nextCatalog = SchemaBinding.start.appendAt 0 [added] := by decide +kernel

/-- All actual retained declarations and indexes remain supported. -/
theorem next_valid : Generated.nextCatalog.Valid Generated.profile.limits := by decide +kernel

/-- The history table is at catalog position 0 of the starting catalog. -/
theorem located : tablePosition SchemaBinding.start "history" = some 0 := by decide +kernel

/-- Every table with the approved history columns covers every name in
{name}`SchemaBinding.fields`. The proof decides each name's column lookup; rows
impose no premise. -/
theorem covers {table : Table} (columns : table.shape.columns = SchemaBinding.history.columns) :
    Covers table SchemaBinding.fields := by
  have all : SchemaBinding.fields.all (fun name => (columnPosition SchemaBinding.history.columns name).isSome) = true := by
    decide +kernel
  intro name member
  rw [columns]
  exact Option.isSome_iff_exists.mp (List.all_eq_true.mp all name member)

/-- For every database conforming to {name}`SchemaBinding.start` under the generated
profile, there exists a present history table at position 0 with the approved
entry and table validity. The computed SQL result is successful with its NULL
extension, and that result conforms to {name}`Generated.nextCatalog`. The proof
recovers the table from conformance, computes ADD and applies catalog
conformance preservation. -/
theorem payload {database : Database} (conforms : Conforms Generated.profile SchemaBinding.start database) :
    ∃ table, database 0 = some table ∧ table.shape = SchemaBinding.history ∧
      table.Valid ∧ runSql Generated.resolved database =
        .success (database.set 0 (table.appendColumns [(added, .null)])) ∧
      Conforms Generated.profile Generated.nextCatalog (database.set 0 (table.appendColumns [(added, .null)])) := by
  obtain ⟨table, present, shape, valid⟩ := conforms.table (position := 0) (shape := SchemaBinding.history)
    (by decide +kernel)
  refine ⟨table, present, shape, valid, ?_, ?_⟩
  · simp [runSql, runSqlFrom, advance, literalStep, SqlState.finish, script_bound, step, CatalogColumn.clockDefault, readDefaultValue, Except.toOption, present,
      added]
  · rw [next_bound]
    exact conforms.appendAt (columns := [(added, .null)]) present (next_bound ▸ next_valid)

/-- For every present, valid history table with the approved columns, if the
before database observes a logical value, setting its NULL extension observes
the same value. The premise is vacuous for an undefined before observation.
The proof preserves the named old-field projection and reuses its decoder result. -/
theorem observed (present : database 0 = some history)
    (columns : history.shape.columns = SchemaBinding.history.columns) (valid : history.Valid)
    (before : HistoryMapping.observe database = some logical) :
    HistoryMapping.observe (database.set 0 (history.appendColumns [(added, .null)])) = some logical := by
  have unchanged : (history.appendColumns [(added, .null)]).project SchemaBinding.fields =
      history.project SchemaBinding.fields :=
    TableExtends.project ⟨[(added, .null)], rfl⟩ (fun row member => (valid.2 row member).2.1) (covers columns)
  simpa [HistoryMapping.observe, located, Database.set, unchanged] using
    (show HistoryDecoding.decodeRows (history.project SchemaBinding.fields) = some logical by
      simpa [HistoryMapping.observe, located, present] using before)

end AtuinFacts
