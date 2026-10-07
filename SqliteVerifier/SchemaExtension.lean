import SqliteVerifier.Library

set_option doc.verso true

/-! Finite schema updates keep lookup proofs independent of concrete schema size. -/
namespace SqliteVerifier

/-- Append columns to every schema entry with the given name. Preserve entry
order, names and properties. Use an empty column list to keep the schema unchanged;
{assert}`Schema.appendAt [] "items" [] = []`. An absent name adds no entry. -/
def Schema.appendAt (schema : Schema) (name : String) (columns : List Column) : Schema :=
  schema.map fun entry => if entry.name == name then
    { entry with columns := entry.columns ++ columns } else entry

/-- For every schema, selected name, lookup name and column list, lookup in
{name}`Schema.appendAt` equals the original lookup with the columns appended
when the two names are equal. For different names, the original lookup remains.
An absent original lookup remains absent in either case; schema validity is
not assumed. Use this equality to reduce an updated lookup to the original one.

The proof uses induction on the schema and separates matching names at the
head entry. The induction hypothesis handles the remaining entries. -/
theorem Schema.lookup_appendAt (schema : Schema) (name other : String) (columns : List Column) :
    (schema.appendAt name columns).lookup other =
      if other = name then (schema.lookup other).map (· ++ columns) else schema.lookup other := by
  induction schema with
  | nil => simp [appendAt, lookup]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      by_cases target : other = name <;>
        simp_all [appendAt, lookup, List.find?, beq_iff_eq] <;> split <;> simp_all

/-- For every schema, selected name, lookup name and column list,
{name}`Schema.appendAt` leaves {name}`Schema.lookupProperties` unchanged.
This includes absent lookups and schemas with duplicate names; validity is
not assumed. Use this equality to retain the original property lookup.

The proof uses induction on the schema. Each matching entry retains its
properties, and the induction hypothesis handles the remaining entries. -/
theorem Schema.properties_appendAt (schema : Schema) (name other : String) (columns : List Column) :
    (schema.appendAt name columns).lookupProperties other = schema.lookupProperties other := by
  induction schema with
  | nil => simp [appendAt, lookupProperties]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      simp_all [appendAt, lookupProperties, List.find?, beq_iff_eq] <;> split <;> simp_all

/-- For every schema, database, table, name and column list, assume:
* The original database satisfies {name}`Conforms` with the original schema.
* The database stores the given table at the selected name.
* The schema from {name}`Schema.appendAt` satisfies {name}`Schema.Valid`.
* {name}`supportedColumns` accepts the original table columns plus the additions.
Then {name}`Database.set` of {name}`Table.appendColumns` satisfies {name}`Conforms`
with the extended schema. An empty addition still requires these assumptions;
an absent table cannot satisfy the second assumption. Use this theorem after
checking the new schema and combined columns.

The proof obtains the old table's validity and property lookup from conformance.
It applies the database update theorem with the two lookup equalities above
and the validity theorem for appended columns. -/
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
