import NextInterpretation

/-! Candidate-independent finite schema facts and arbitrary-row payload correctness. -/
namespace AtuinFacts
open SqliteVerifier

/-- Generated starting data equals the complete independently reviewed baseline. -/
theorem start_bound : Generated.startSchema = SchemaBinding.start := by rfl
/-- Generated result retains all definitions and appends precisely the shell column. -/
theorem next_bound : Generated.nextSchema = SchemaBinding.next := by rfl
/-- The single history extension is a local proof fragment of the explicit script. -/
def payloadScript : List Statement := [.addColumn "history" SchemaBinding.shell]

/-- Both tables, six indexes (three implicit), and declarations are supported. -/
theorem start_valid : SchemaBinding.start.Valid := by
  simp [Schema.Valid, SchemaBinding.start, Generated.startSchema]
  decide +kernel
/-- The complete resulting schema is supported without weakening old constraints. -/
theorem next_valid : SchemaBinding.next.Valid := by
  simp [Schema.Valid, Schema.appendAt, SchemaBinding.next, SchemaBinding.start, Generated.startSchema]
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

/-- This ADD succeeds for arbitrary old rows and preserves exact full-schema conformance. -/
theorem payload {database : Database} (conforms : Conforms SchemaBinding.start database) :
    ∃ table, database "history" = some table ∧ table.columns = SchemaBinding.history.columns ∧
      table.Valid ∧ run payloadScript database =
        .success (database.set "history" (table.appendColumns [SchemaBinding.shell])) ∧
      Conforms SchemaBinding.next (database.set "history" (table.appendColumns [SchemaBinding.shell])) := by
  obtain ⟨table, present, columns, valid⟩ := conforms.table (name := "history") (by rfl)
  refine ⟨table, present, columns, valid, ?_, ?_⟩
  · have size : ¬table.columns.length ≥ maximumColumns := by rw [columns]; decide +kernel
    have fresh : table.columns.any (fun old => old.name == SchemaBinding.shell.name) = false := by
      rw [columns]; decide +kernel
    have nameAllowed : supportedTableName "history" = true := by decide +kernel
    have columnAllowed : supportedColumn SchemaBinding.shell = true := by decide +kernel
    have plain : SchemaBinding.shell.plain = true := by decide +kernel
    simp [run, runFrom, payloadScript, step, nameAllowed, columnAllowed, plain, present, size, fresh]
  · have shape : SchemaBinding.next = SchemaBinding.start.appendAt "history" [SchemaBinding.shell] := rfl
    rw [shape]
    exact conforms.appendAt present (shape ▸ next_valid) (by rw [columns]; decide +kernel)

end AtuinFacts
