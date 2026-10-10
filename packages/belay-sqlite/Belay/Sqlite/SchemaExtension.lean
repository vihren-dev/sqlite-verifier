import Belay.Sqlite.ModelFacts

set_option doc.verso true

/-! Finite schema updates keep lookup proofs independent of concrete schema size. -/
namespace Belay.Sqlite

/-- Append columns to every schema entry with the given name. Preserve entry
order, names and properties. Use an empty column list to keep the schema unchanged;
{assert}`Schema.appendAt [] "items" [] = []`. An absent name adds no entry. -/
def Schema.appendAt (schema : Schema) (name : String) (columns : List Column) : Schema :=
  schema.map fun entry => if entry.name == name then
    { entry with shape.columns := entry.shape.columns ++ columns } else entry

/-- For every schema, selected name, lookup name and column list, whole-shape
lookup after {name}`Schema.appendAt` appends only the columns at the selected
name. Every other shape field and unmatched lookup remains unchanged. An absent
lookup stays absent; schema validity is not assumed. Use this for conformance.
The proof inducts on schema entries and separates the matching names. -/
theorem Schema.shape_appendAt (schema : Schema) (name other : String) (columns : List Column) :
    (schema.appendAt name columns).lookupShape other =
      if other = name then (schema.lookupShape other).map
        (fun shape => { shape with columns := shape.columns ++ columns }) else schema.lookupShape other := by
  induction schema with
  | nil => simp [appendAt, lookupShape]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      by_cases target : other = name <;>
        simp_all [appendAt, lookupShape, List.find?, beq_iff_eq] <;> split <;> simp_all

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
  | nil => simp [appendAt, lookup, lookupShape]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      by_cases target : other = name <;>
        simp_all [appendAt, lookup, lookupShape, List.find?, beq_iff_eq] <;> split <;> simp_all

/-- For every schema, selected name, lookup name and column list,
{name}`Schema.appendAt` leaves {name}`Schema.lookupProperties` unchanged.
This includes absent lookups and schemas with duplicate names; validity is
not assumed. Use this equality to retain the original property lookup.

The proof uses induction on the schema. Each matching entry retains its
properties, and the induction hypothesis handles the remaining entries. -/
theorem Schema.properties_appendAt (schema : Schema) (name other : String) (columns : List Column) :
    (schema.appendAt name columns).lookupProperties other = schema.lookupProperties other := by
  induction schema with
  | nil => simp [appendAt, lookupProperties, lookupShape]
  | cons entry rest ih =>
    by_cases selected : entry.name = name <;> by_cases matched : entry.name = other <;>
      simp_all [appendAt, lookupProperties, lookupShape, List.find?, beq_iff_eq] <;> split <;> simp_all

/-- For every schema, database, table, name and column list, assume:
* The original database satisfies {name}`Conforms` with the original schema.
* The database stores the given table at the selected name.
* The schema from {name}`Schema.appendAt` satisfies {name}`Schema.Valid`.
* {name}`supportedColumns` accepts the original table columns plus the additions.
Then {name}`Database.set` of {name}`Table.appendColumns` satisfies {name}`Conforms`
with the extended schema. An empty addition still requires these assumptions;
an absent table cannot satisfy the second assumption. Use this theorem after
checking the new schema and combined columns.

The proof obtains the old table's validity and whole shape from conformance.
It applies the database update theorem with the whole-shape lookup equality
and the validity theorem for appended columns. -/
theorem Conforms.appendAt {schema : Schema} {database : Database} {table : Table}
    (conforms : Conforms schema database) (present : database name = some table)
    (schemaValid : (schema.appendAt name columns).Valid)
    (supported : supportedColumns (table.shape.columns ++ columns) = true) :
    Conforms (schema.appendAt name columns) (database.set name (table.appendColumns columns)) := by
  have valid := (conforms.2 name).2 table present
  have shape := conforms.shape present
  apply conforms.set schemaValid (valid.appendColumns supported)
  · intro other
    rw [Schema.shape_appendAt]
    by_cases same : other = name <;> simp [same, shape, Table.appendColumns]

end Belay.Sqlite
