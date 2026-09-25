import NextInterpretation

/-! Candidate-independent finite schema facts and arbitrary-row payload correctness. -/
namespace AtuinFacts
open SqliteVerifier

/-- Generated starting data equals the complete independently reviewed baseline. -/
theorem start_bound : Generated.startSchema = AtuinSchema.start := by rfl
/-- Generated result retains all definitions and appends precisely the shell column. -/
theorem next_bound : Generated.nextSchema = AtuinSchema.next := by rfl
/-- Original SQL and manifest produce the reviewed pending profile and statement. -/
theorem inputs_bound : Generated.script = AtuinSchema.payload ∧
    Generated.profile = .sqlite346Sqlx AtuinCatalog.config := by exact ⟨rfl, rfl⟩

/-- All four tables, six indexes (three implicit), and declarations are supported. -/
theorem start_valid : AtuinSchema.start.Valid := by
  simp [Schema.Valid, AtuinSchema.start, AtuinSchema.metadata, AtuinSchema.history,
    AtuinSchema.stat1, AtuinSchema.stat4]
  decide +kernel
/-- The complete resulting schema is supported without weakening old constraints. -/
theorem next_valid : AtuinSchema.next.Valid := by
  simp [Schema.Valid, AtuinSchema.next, AtuinSchema.metadata, AtuinSchema.history,
    AtuinSchema.stat1, AtuinSchema.stat4]
  decide +kernel

/-- Any represented history table covers all eleven protected names. -/
theorem covers {table : Table} (columns : table.columns = AtuinSchema.history.columns) :
    Covers table AtuinSchema.fields := by
  intro name member
  rw [AtuinSchema.fields] at member
  rw [columns]
  obtain ⟨column, named, equal⟩ := List.mem_map.mp member
  exact ⟨_, List.findIdx?_eq_some_of_exists ⟨column, named, by simp [equal]⟩⟩

/-- This ADD succeeds for arbitrary old rows and preserves exact full-schema conformance. -/
theorem payload {database : Database} (conforms : Conforms AtuinSchema.start database) :
    ∃ table, database "history" = some table ∧ table.columns = AtuinSchema.history.columns ∧
      table.Valid ∧ run AtuinSchema.payload database =
        .success (database.set "history" (table.appendColumns [AtuinSchema.shell])) ∧
      Conforms AtuinSchema.next (database.set "history" (table.appendColumns [AtuinSchema.shell])) := by
  obtain ⟨table, present, columns, valid⟩ := conforms.table (name := "history") (by rfl)
  refine ⟨table, present, columns, valid, ?_, ?_⟩
  · have size : ¬table.columns.length ≥ maximumColumns := by rw [columns]; decide +kernel
    have fresh : table.columns.any (fun old => old.name == AtuinSchema.shell.name) = false := by
      rw [columns]; decide +kernel
    have nameAllowed : supportedTableName "history" = true := by decide +kernel
    have columnAllowed : supportedColumn AtuinSchema.shell = true := by decide +kernel
    have plain : AtuinSchema.shell.plain = true := by decide +kernel
    simp [run, runFrom, AtuinSchema.payload, step, nameAllowed, columnAllowed, plain, present, size, fresh]
  · have shape : AtuinSchema.next = AtuinSchema.start.appendAt "history" [AtuinSchema.shell] := rfl
    rw [shape]
    exact conforms.appendAt present (shape ▸ next_valid) (by rw [columns]; decide +kernel)

/-- Any schema-conforming current interpretation reads actual history storage. -/
theorem current_sound : SoundRepresentation Requirements.contract AtuinSchema.start Interpretation.current := by
  intro database conforms
  obtain ⟨table, present, _, _⟩ := conforms.table (name := "history") (by rfl)
  exact ⟨conforms, ⟨table.project AtuinSchema.fields, none⟩,
    by simp [Interpretation.current, observeNullable, present], trivial⟩

/-- The new reader is defined by the full result schema, including shell. -/
theorem next_sound : SoundRepresentation Requirements.contract Generated.nextSchema NextInterpretation.next := by
  intro database conforms
  obtain ⟨table, present, _, _⟩ := conforms.table (name := "history") (by rfl)
  exact ⟨conforms, ⟨table.project AtuinSchema.fields, some (table.project ["shell"])⟩,
    by simp [NextInterpretation.next, observeNullable, present], trivial⟩

/-- Failure representations use exactly their rollback/committed schema. -/
theorem failures_sound (position reason) : SoundRepresentation Requirements.contract
    (NextInterpretation.failures.schema position reason)
    (NextInterpretation.failures.interpretation position reason) := by
  simp only [NextInterpretation.failures]
  split <;> first | exact next_sound | exact current_sound

end AtuinFacts
