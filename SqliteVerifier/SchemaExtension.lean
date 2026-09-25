import SqliteVerifier.Library

/-! Finite schema updates keep lookup proofs independent of concrete schema size. -/
namespace SqliteVerifier

/-- Add declarations to a selected existing table while retaining every property. -/
def Schema.appendAt (schema : Schema) (name : String) (columns : List Column) : Schema :=
  schema.map fun entry => if entry.name == name then
    { entry with columns := entry.columns ++ columns } else entry

/-- Column lookup reflects exactly the selected declaration extension. -/
theorem Schema.lookup_appendAt (schema : Schema) (name other : String) (columns : List Column) :
    (schema.appendAt name columns).lookup other =
      if other = name then (schema.lookup other).map (· ++ columns) else schema.lookup other := by
  induction schema with
  | nil => simp [appendAt, lookup]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      by_cases target : other = name <;>
        simp_all [appendAt, lookup, List.find?, beq_iff_eq] <;> split <;> simp_all

/-- A declaration extension cannot replace or erase existing constraints or indexes. -/
theorem Schema.properties_appendAt (schema : Schema) (name other : String) (columns : List Column) :
    (schema.appendAt name columns).lookupProperties other = schema.lookupProperties other := by
  induction schema with
  | nil => simp [appendAt, lookupProperties]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      simp_all [appendAt, lookupProperties, List.find?, beq_iff_eq] <;> split <;> simp_all

/-- A valid extended table and schema establish conformance without inspecting old cells. -/
theorem Conforms.appendAt {schema : Schema} {database : Database} {table : Table}
    (conforms : Conforms schema database) (present : database name = some table)
    (schemaValid : (schema.appendAt name columns).Valid)
    (supported : supportedColumns (table.columns ++ columns) = true) :
    Conforms (schema.appendAt name columns) (database.set name (table.appendColumns columns)) := by
  obtain ⟨valid, properties⟩ := (conforms.2 name).2 table present
  have shape : schema.lookup name = some table.columns := by
    simpa [present] using (conforms.2 name).1.symm
  apply conforms.set schemaValid (valid.appendColumns supported)
  · intro other
    rw [Schema.lookup_appendAt]
    by_cases same : other = name <;> simp [same, shape, Table.appendColumns]
  · intro other
    rw [Schema.properties_appendAt]
    by_cases same : other = name <;> simp [same, properties, Table.appendColumns]

end SqliteVerifier
