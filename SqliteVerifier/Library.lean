import SqliteVerifier.Contract

/-! Named projections and representation lemmas hide routine proof bookkeeping
without restricting the general logical/interpretation interfaces. -/

namespace SqliteVerifier

/-- A projection contains every selected field; absent names cannot be filtered out. -/
def Covers (table : Table) (names : List String) : Prop :=
  ∀ name ∈ names, ∃ index, table.columns.findIdx? (fun column => column.name == name) = some index

/-- A represented table exposes every row, its physical identity, and selected fields. -/
abbrev LogicalRows := List (Int × List (Option Value))

/-- Missing tables are undefined; no default empty view can conceal lost records. -/
def observeTable (name : String) (fields : List String) (database : Database) : Option LogicalRows :=
  (database name).map (·.project fields)

/-- The convenience invariant requires exact schema conformance and field coverage. -/
def projectedInterpretation (schema : Schema) (name : String) (fields : List String) :
    Interpretation LogicalRows where
  invariant database := Conforms schema database ∧
    ∃ table, database name = some table ∧ Covers table fields
  observe := observeTable name fields

/-- Success-only conveniences may declare failure interpretations unreachable;
the verification proof must still establish that no modeled failure occurs. -/
def unreachableFailures : FailureRepresentation Logical where
  schema := fun _ _ => []
  interpretation := fun _ _ => ⟨fun _ => False, fun _ => none⟩

/-- The false invariant is sound but cannot be established by an actual failure. -/
theorem unreachableFailures_sound (contract : LogicalContract Logical) (position reason) :
    SoundRepresentation contract ((unreachableFailures (Logical := Logical)).schema position reason)
      (unreachableFailures.interpretation position reason) := by
  intro database impossible
  exact False.elim impossible

/-- Every admitted finite schema has an empty-data witness; extra approved
conditions can require a different witness and are never inferred from this one. -/
theorem Schema.emptyDatabase_conforms (valid : schema.Valid) :
    Conforms schema schema.emptyDatabase := by
  refine ⟨valid, ?_⟩
  intro name
  cases found : schema.lookup name with
  | none => simp [Schema.emptyDatabase, found]
  | some columns =>
    refine ⟨by simp [Schema.emptyDatabase, found], ?_⟩
    intro table present
    have equal : table = ⟨columns, []⟩ := by
      simpa [Schema.emptyDatabase, found] using present.symm
    subst table
    unfold Schema.lookup at found
    obtain ⟨entry, entryFound, rfl⟩ := Option.map_eq_some_iff.mp found
    have supported := (valid.2 entry (List.mem_of_find?_eq_some entryFound)).2
    exact ⟨supported, by simp, by simp⟩

/-- Schema lookup and conformance recover the actual stored table and its validity. -/
theorem Conforms.table (conforms : Conforms schema database)
    (lookup : schema.lookup name = some columns) :
    ∃ table, database name = some table ∧ table.columns = columns ∧ table.Valid := by
  obtain ⟨shape, valid⟩ := conforms.2 name
  cases present : database name with
  | none => simp [present, lookup] at shape
  | some table =>
    refine ⟨table, rfl, ?_, valid table present⟩
    simpa [present, lookup] using shape

/-- Validity of a selected logical view remains an explicit user obligation. -/
theorem projectedInterpretation_sound (contract : LogicalContract LogicalRows)
    (schema : Schema) (name : String) (fields : List String)
    (valid : ∀ table, table.Valid → Covers table fields → contract.valid (table.project fields)) :
    SoundRepresentation contract schema (projectedInterpretation schema name fields) := by
  intro database invariant
  obtain ⟨conforms, table, present, covered⟩ := invariant
  exact ⟨conforms, table.project fields, by simp [projectedInterpretation, observeTable, present],
    valid table ((conforms.2 name).2 table present) covered⟩

/-- NULL extension preserves native rowid validity and exact schema widths. -/
theorem Table.Valid.appendColumns {table : Table} {columns : List Column} (valid : table.Valid)
    (supported : supportedColumns (table.columns ++ columns) = true) :
    (table.appendColumns columns).Valid := by
  refine ⟨supported, ?_, ?_⟩
  · simpa [Table.appendColumns, Row.appendNulls, List.map_map, Function.comp_def] using valid.2.1
  · intro row member
    obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
    obtain ⟨rowid, width⟩ := valid.2.2 original oldMember
    exact ⟨rowid, by simp [Row.appendNulls, Table.appendColumns, width]⟩

/-- Updating one table preserves conformance when the exact new schema is established. -/
theorem Conforms.set {schema nextSchema : Schema} {database : Database} {name : String}
    {table : Table} (conforms : Conforms schema database) (schemaValid : nextSchema.Valid)
    (tableValid : table.Valid)
    (lookup : ∀ other, nextSchema.lookup other =
      if other = name then some table.columns else schema.lookup other) :
    Conforms nextSchema (database.set name table) := by
  refine ⟨schemaValid, ?_⟩
  intro other
  by_cases same : other = name
  · subst other
    simp only [Database.set, ↓reduceIte, Option.map_some, lookup]
    exact ⟨trivial, fun result equal => by cases equal; exact tableValid⟩
  · simpa only [Database.set, same, ↓reduceIte, lookup] using conforms.2 other

/-- Every requested old column remains covered after appending new columns. -/
theorem TableExtends.covers (extension : TableExtends before after)
    (covered : Covers before names) : Covers after names := by
  obtain ⟨columns, rfl⟩ := extension
  intro name member
  obtain ⟨index, found⟩ := covered name member
  exact ⟨index, (List.IsPrefix.findIdx?_eq_some ⟨columns, rfl⟩ found)⟩

/-- Named projection preservation includes row identity, duplicates, and every selected cell. -/
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
