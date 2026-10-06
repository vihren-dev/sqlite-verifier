import SqliteVerifier.Contract
import SqliteVerifier.Preservation

set_option doc.verso true

/-! Named projections and representation lemmas hide routine proof bookkeeping
without restricting the general logical/interpretation interfaces. -/

namespace SqliteVerifier

/-- For every requested name, some index is returned by the table's column
lookup. An empty name list requires nothing; repeated names are allowed.
Use this to establish column presence before projection; row width is separate. -/
def Covers (table : Table) (names : List String) : Prop :=
  ∀ name ∈ names, ∃ index, table.columns.findIdx? (fun column => column.name == name) = some index

/-- Ordered physical rowids and optional projected cells. Use
{lean}`([] : LogicalRows)` for no rows; a missing cell differs from observed NULL. -/
abbrev LogicalRows := List (Int × List (Option Value))

/-- Project the requested fields of a stored table, retaining row order and
rowids. An absent table yields {name}`Option.none`; a present empty table yields
{lean}`(some [] : Option LogicalRows)`, so lost tables cannot look empty. -/
def observeTable (name : String) (fields : List String) (database : Database) : Option LogicalRows :=
  (database name).map (·.project fields)

/-- Build an {name}`Interpretation` whose invariant requires {name}`Conforms`
and a table stored at the selected name that satisfies {name}`Covers` for all
requested fields. Observation uses {name}`observeTable`. Use an empty field
list to observe rowids only; the caller proves the logical contract's validity. -/
def projectedInterpretation (schema : Schema) (name : String) (fields : List String) :
    Interpretation LogicalRows where
  invariant database := Conforms schema database ∧
    ∃ table, database name = some table ∧ Covers table fields
  observe := observeTable name fields

/-- Give every failure position and reason an empty schema and an interpretation
with false invariant and absent observation. Use this for success-only proofs;
the verification conditions still require proving modeled failures unreachable. -/
def unreachableFailures : FailureRepresentation Logical where
  schema := fun _ _ => []
  interpretation := fun _ _ => ⟨fun _ => False, fun _ => none⟩

/-- For every logical contract, failure position and reason, the corresponding
{name}`unreachableFailures` representation is sound. Every database obligation
is vacuous because its invariant is false; this does not establish a failure
invariant. The proof eliminates that impossible assumption. -/
theorem unreachableFailures_sound (contract : LogicalContract Logical) (position reason) :
    SoundRepresentation contract ((unreachableFailures (Logical := Logical)).schema position reason)
      (unreachableFailures.interpretation position reason) := by
  intro database impossible
  exact False.elim impossible

/-- For every valid schema, {name}`Schema.emptyDatabase` satisfies {name}`Conforms`
with that schema, including the empty schema. Use it as an empty-data witness;
additional approved conditions require a separate proof.
The proof separates absent and present entries; empty rows satisfy row validity. -/
theorem Schema.emptyDatabase_conforms (valid : schema.Valid) :
    Conforms schema schema.emptyDatabase := by
  refine ⟨valid, ?_⟩
  intro name
  cases found : schema.find? (fun entry => entry.name == name) with
  | none => simp [Schema.emptyDatabase, Schema.lookup, found]
  | some entry =>
    refine ⟨by simp [Schema.emptyDatabase, Schema.lookup, found], ?_⟩
    intro table present
    have equal : table = { columns := entry.columns, rows := [], properties := entry.properties } := by
      simpa [Schema.emptyDatabase, found] using present.symm
    subst table
    have supported := (valid.2 entry (List.mem_of_find?_eq_some found)).2.1
    exact ⟨⟨supported, by simp, by simp⟩, by simp [Schema.lookupProperties, found]⟩

/-- For every schema, database, name and columns, assume {name}`Conforms` and a
lookup returning those columns. Then some stored table has exactly those columns
and satisfies {name}`Table.Valid`. An absent schema lookup cannot meet the premise.
The proof rules out an absent table using conformance's column-lookup equality. -/
theorem Conforms.table (conforms : Conforms schema database)
    (lookup : schema.lookup name = some columns) :
    ∃ table, database name = some table ∧ table.columns = columns ∧ table.Valid := by
  obtain ⟨shape, valid⟩ := conforms.2 name
  cases present : database name with
  | none => simp [present, lookup] at shape
  | some table =>
    refine ⟨table, rfl, ?_, (valid table present).1⟩
    simpa [present, lookup] using shape

/-- For every contract, schema, name and field list, assume the projection of
every valid table covering those fields satisfies the contract's validity.
Then {name}`projectedInterpretation` is a {name}`SoundRepresentation`. An empty
field list still requires that validity premise for its rowid-only projections.
The proof extracts the stored valid table and applies the supplied premise. -/
theorem projectedInterpretation_sound (contract : LogicalContract LogicalRows)
    (schema : Schema) (name : String) (fields : List String)
    (valid : ∀ table, table.Valid → Covers table fields → contract.valid (table.project fields)) :
    SoundRepresentation contract schema (projectedInterpretation schema name fields) := by
  intro database invariant
  obtain ⟨conforms, table, present, covered⟩ := invariant
  exact ⟨conforms, table.project fields, by simp [projectedInterpretation, observeTable, present],
    valid table ((conforms.2 name).2 table present).1 covered⟩

/-- For every valid table and added columns, assume {name}`supportedColumns`
accepts the combined columns. Then {name}`Table.appendColumns` remains valid.
With no rows, rowid and width conditions are vacuous; combined-column support
remains. Use this for NULL extension. The proof preserves rowids and adds widths. -/
theorem Table.Valid.appendColumns {table : Table} {columns : List Column} (valid : table.Valid)
    (supported : supportedColumns (table.columns ++ columns) = true) :
    (table.appendColumns columns).Valid := by
  refine ⟨supported, ?_, ?_⟩
  · simpa [Table.appendColumns, Row.appendNulls, List.map_map, Function.comp_def] using valid.2.1
  · intro row member
    obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
    obtain ⟨rowid, width⟩ := valid.2.2 original oldMember
    exact ⟨rowid, by simp [Row.appendNulls, Table.appendColumns, width]⟩

/-- For every original/next schema, database, name and table, assume original
{name}`Conforms`, valid next schema and valid replacement table. For every name,
assume next columns and properties select the replacement at the changed name
and retain original lookups elsewhere. Then setting the table conforms to the
next schema. The old table need not exist; all stated assumptions still apply.
Use this for one-table updates. The proof separates changed and other names. -/
theorem Conforms.set {schema nextSchema : Schema} {database : Database} {name : String}
    {table : Table} (conforms : Conforms schema database) (schemaValid : nextSchema.Valid)
    (tableValid : table.Valid)
    (lookup : ∀ other, nextSchema.lookup other =
      if other = name then some table.columns else schema.lookup other)
    (properties : ∀ other, nextSchema.lookupProperties other =
      if other = name then some table.properties else schema.lookupProperties other) :
    Conforms nextSchema (database.set name table) := by
  refine ⟨schemaValid, ?_⟩
  intro other
  by_cases same : other = name
  · subst other
    simp only [Database.set, ↓reduceIte, Option.map_some, lookup]
    exact ⟨trivial, fun result equal => by
      cases equal
      exact ⟨tableValid, by simp [properties]⟩⟩
  · simpa only [Database.set, same, ↓reduceIte, lookup, properties] using conforms.2 other

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
    (width : ∀ row ∈ before.rows, row.values.length = before.columns.length)
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
      (show before.columns <+: before.columns ++ columns from ⟨columns, rfl⟩) found
    have bound : index < row.values.length := by
      rw [width row member]
      exact (List.findIdx?_eq_some_iff_findIdx_eq.mp found).1
    simp [Row.appendNulls, found, afterFound, List.getElem?_append_left bound]

end SqliteVerifier
