import Belay.Sqlite.Preservation

set_option doc.verso true

/-! Structural lookup, update and projection facts need no application contract. -/

namespace Belay.Sqlite

/-- For every requested name, some index is returned by the table's column
lookup. An empty name list requires nothing; repeated names are allowed.
Use this to establish column presence before projection; row width is separate. -/
def Covers (table : Table) (names : List String) : Prop :=
  ∀ name ∈ names, ∃ index, table.shape.columns.findIdx? (fun column => column.name == name) = some index

/-- For every valid schema, {name}`Schema.emptyDatabase` satisfies {name}`Conforms`
with that schema, including the empty schema. Use it as an empty-data witness;
additional invariants require a separate proof.
The proof separates absent and present entries; empty rows satisfy row validity. -/
theorem Schema.emptyDatabase_conforms (valid : schema.Valid) :
    Conforms schema schema.emptyDatabase := by
  refine ⟨valid, ?_⟩
  intro name
  cases found : schema.find? (fun entry => entry.name == name) with
  | none => simp [Schema.emptyDatabase, Schema.lookupShape, found]
  | some entry =>
    refine ⟨by simp [Schema.emptyDatabase, Schema.lookupShape, found], ?_⟩
    intro table present
    have equal : table = { shape := entry.shape, rows := [] } := by
      simpa [Schema.emptyDatabase, found] using present.symm
    subst table
    have supported := (valid.2 entry (List.mem_of_find?_eq_some found)).2.1
    exact ⟨supported, by simp, by simp⟩

/-- For every conforming database and stored table, whole-shape lookup returns
that table's shape. The table-presence premise excludes absence. Use this to
read all declared metadata; the proof selects the conformance equality. -/
theorem Conforms.shape (conforms : Conforms schema database)
    (present : database name = some table) : schema.lookupShape name = some table.shape := by
  simpa [present] using (conforms.2 name).1.symm


/-- For every schema, database, name and columns, assume {name}`Conforms` and a
lookup returning those columns. Then some stored table has exactly those columns
and satisfies {name}`Table.Valid`. An absent schema lookup cannot meet the premise.
The proof projects the whole-shape equality to columns and rules out absence. -/
theorem Conforms.table (conforms : Conforms schema database)
    (lookup : schema.lookup name = some columns) :
    ∃ table, database name = some table ∧ table.shape.columns = columns ∧ table.Valid := by
  obtain ⟨shape, valid⟩ := conforms.2 name
  have columnsEqual : (database name).map (fun table => table.shape.columns) = schema.lookup name := by
    simpa [Schema.lookup, Option.map_map, Function.comp_def] using
      congrArg (Option.map TableShape.columns) shape
  cases present : database name with
  | none => simp [present, lookup] at columnsEqual
  | some table =>
    refine ⟨table, rfl, ?_, valid table present⟩
    simpa [present, lookup] using columnsEqual

/-- For every valid table and added columns, assume {name}`supportedColumns`
accepts the combined columns. Then {name}`Table.appendColumns` remains valid.
With no rows, rowid and width conditions are vacuous; combined-column support
remains. Use this for NULL extension. The proof preserves rowids and adds widths. -/
theorem Table.Valid.appendColumns {table : Table} {columns : List Column} (valid : table.Valid)
    (supported : supportedColumns (table.shape.columns ++ columns) = true) :
    (table.appendColumns columns).Valid := by
  refine ⟨supported, ?_, ?_⟩
  · simpa [Table.appendColumns, Row.appendNulls, List.map_map, Function.comp_def] using valid.2.1
  · intro row member
    obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
    obtain ⟨rowid, width⟩ := valid.2.2 original oldMember
    exact ⟨rowid, by simp [Row.appendNulls, Table.appendColumns, width]⟩

/-- For every original/next schema, database, name and table, assume original
{name}`Conforms`, valid next schema and valid replacement table. For every name,
assume next whole shapes select the replacement at the changed name
and retain original lookups elsewhere. Then setting the table conforms to the
next schema. The old table need not exist; all stated assumptions still apply.
Use this for one-table updates. The proof separates changed and other names. -/
theorem Conforms.set {schema nextSchema : Schema} {database : Database} {name : String}
    {table : Table} (conforms : Conforms schema database) (schemaValid : nextSchema.Valid)
    (tableValid : table.Valid)
    (lookup : ∀ other, nextSchema.lookupShape other =
      if other = name then some table.shape else schema.lookupShape other) :
    Conforms nextSchema (database.set name table) := by
  refine ⟨schemaValid, ?_⟩
  intro other
  by_cases same : other = name
  · subst other
    simp only [Database.set, ↓reduceIte, Option.map_some, lookup]
    exact ⟨trivial, fun result equal => by
      cases equal
      exact tableValid⟩
  · simpa only [Database.set, same, ↓reduceIte, lookup] using conforms.2 other

/-- For every database, two distinct names and two tables, setting the tables
in either order gives the same database. Table validity and rows are unrestricted;
use this equality for independent updates. The proof compares every lookup and
separates its equality with the two distinct names. -/
theorem Database.set_comm (database : Database) (first second : String)
    (firstTable secondTable : Table) (different : first ≠ second) :
    (database.set first firstTable).set second secondTable =
      (database.set second secondTable).set first firstTable := by
  funext name
  by_cases a : name = first <;> by_cases b : name = second <;>
    simp_all [Database.set]

/-- For every before/after table and name list, assume {name}`TableExtends` and
{name}`Covers` before. Then coverage holds after; with no names it is vacuous.
Use this to retain selected columns. The proof keeps each first matching index
through the unchanged prefix of original columns. -/
theorem TableExtends.covers (extension : TableExtends before after)
    (covered : Covers before names) : Covers after names := by
  obtain ⟨columns, rfl⟩ := extension
  intro name member
  obtain ⟨index, found⟩ := covered name member
  exact ⟨index, (List.IsPrefix.findIdx?_eq_some ⟨columns, rfl⟩ found)⟩

/-- For every before/after table and name list, assume {name}`TableExtends`,
one old cell per original column in every old row, and old {name}`Covers`.
Then the two projections are equal, including rowids, duplicates and every cell.
With no rows width is vacuous; with no names coverage is vacuous and rowids remain.
Use this to prove view preservation. The proof retains old column indices and
uses row width to read their cells before the appended NULLs. -/
theorem TableExtends.project (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length)
    (covered : Covers before names) : after.project names = before.project names := by
  obtain ⟨columns, rfl⟩ := extension
  simp only [Table.project, Table.appendColumns, List.map_map]
  apply List.map_congr_left
  intro row member
  apply Prod.ext
  · rfl
  · apply List.map_congr_left
    intro name named
    obtain ⟨index, found⟩ := covered name named
    have afterFound := List.IsPrefix.findIdx?_eq_some (p := fun column => column.name == name)
      (show before.shape.columns <+: before.shape.columns ++ columns from ⟨columns, rfl⟩) found
    have bound : index < row.values.length := by
      rw [width row member]
      exact (List.findIdx?_eq_some_iff_findIdx_eq.mp found).1
    simp [Row.appendNulls, found, afterFound, List.getElem?_append_left bound]

end Belay.Sqlite
