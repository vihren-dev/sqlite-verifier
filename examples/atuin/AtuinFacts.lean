import NextInterpretation

/-! Candidate-independent finite schema facts and arbitrary-row payload correctness. -/
namespace AtuinFacts
open SqliteVerifier

/-- Generated starting data equals the complete independently reviewed baseline. -/
theorem start_bound : Generated.startSchema = AtuinSchema.start := by rfl
/-- Generated result retains all definitions and appends precisely the shell column. -/
theorem next_bound : Generated.nextSchema = AtuinSchema.next := by rfl
/-- The single history extension is a local proof fragment of the explicit script. -/
def payloadScript : List Statement := [.addColumn "history" AtuinSchema.shell]

/-- Both tables, six indexes (three implicit), and declarations are supported. -/
theorem start_valid : AtuinSchema.start.Valid := by
  simp [Schema.Valid, AtuinSchema.start, AtuinSchema.metadata, AtuinSchema.history]
  decide +kernel
/-- The complete resulting schema is supported without weakening old constraints. -/
theorem next_valid : AtuinSchema.next.Valid := by
  simp [Schema.Valid, AtuinSchema.next, AtuinSchema.metadata, AtuinSchema.history]
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
      table.Valid ∧ run payloadScript database =
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
    simp [run, runFrom, payloadScript, step, nameAllowed, columnAllowed, plain, present, size, fresh]
  · have shape : AtuinSchema.next = AtuinSchema.start.appendAt "history" [AtuinSchema.shell] := rfl
    rw [shape]
    exact conforms.appendAt present (shape ▸ next_valid) (by rw [columns]; decide +kernel)

/-- The approved current representation reads actual history and all six catalog records. -/
theorem current_sound : SoundRepresentation Requirements.contract AtuinSchema.start Interpretation.current := by
  intro database invariant
  obtain ⟨conforms, metadata, stored, recorded⟩ := invariant
  obtain ⟨table, present, _, _⟩ := conforms.table (name := "history") (by rfl)
  refine ⟨conforms, ⟨⟨table.project AtuinSchema.fields,
    some (nullExtension (table.project AtuinSchema.fields))⟩, metadata.rows⟩, ?_, ?_⟩
  · simp [Interpretation.current, Interpretation.observe, observeNullable, present, stored]
  · exact Or.inl recorded.2

/-- The proposed representation reads actual shell and all seven catalog records. -/
theorem next_sound : SoundRepresentation Requirements.contract Generated.nextSchema NextInterpretation.next := by
  intro database invariant
  obtain ⟨conforms, metadata, stored, recorded⟩ := invariant
  obtain ⟨table, present, _, _⟩ := conforms.table (name := "history") (by rfl)
  refine ⟨conforms, ⟨⟨table.project AtuinSchema.fields,
    some (table.project ["shell"])⟩, metadata.rows⟩, ?_, ?_⟩
  · simp [NextInterpretation.next, Interpretation.observe, observeNullable, present, stored]
  · exact Or.inr recorded.2

/-- The universal execution proof must rule out all failures for this contract. -/
theorem failures_sound (position reason) : SoundRepresentation Requirements.contract
    (NextInterpretation.failures.schema position reason)
    (NextInterpretation.failures.interpretation position reason) :=
  unreachableFailures_sound Requirements.contract position reason

end AtuinFacts
