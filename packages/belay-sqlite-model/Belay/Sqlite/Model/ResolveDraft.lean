import Belay.Sqlite.Model.ResolveTableShaped

set_option doc.verso true

/-! The invariant of a table while CREATE TABLE builds it (ADR 0022, D3, slice 4). On top of
{lit}`CatalogTable.Shaped`, a table is a {lit}`Draft` when it is not WITHOUT ROWID and a STRICT
column of type ANY has the declared type ANY. While the constraints of one column apply, the table is
{lit}`Building` that column: its last column has the reported type of the definition. The two extra
facts give a rowid alias an INTEGER affinity: a declared type that aliases the rowid is not ANY and
has the affinity INTEGER. -/

namespace Belay.Sqlite.Model

/-- For every declared type that aliases the rowid ({name}`aliasesRowid`), the affinity of the type
({name}`affinityOf`) is INTEGER. Proof sketch: the type in capitals is INTEGER, which contains INT. -/
theorem affinityOf_of_aliasesRowid {declared : Option String} (aliases : aliasesRowid declared = true) :
    affinityOf declared = .integer := by
  cases declared with
  | none => simp [aliasesRowid] at aliases
  | some text =>
    simp only [aliasesRowid, Option.map_some, beq_iff_eq, Option.some.injEq] at aliases
    have upper : String.ofList (text.toList.map Char.toUpper) = text.toUpper := by
      simp [String.toUpper, String.map_eq_internal]
    simp only [affinityOf, upper, aliases]
    decide

/-- For every declared type that {name}`StrictType.ofReported` reads as ANY, the type is the text
{lit}`ANY`. Proof sketch: only the case for {lit}`ANY` gives that strict type. -/
theorem eq_any_of_ofReported {declared : Option String} (any : StrictType.ofReported declared = some .any) :
    declared = some "ANY" := by
  unfold StrictType.ofReported at any
  split at any <;> simp_all

/-- The strict type and the declared type of a column, which the affinity of the column reads. -/
def CatalogColumn.typing (column : CatalogColumn) : Option StrictType × Option String :=
  (column.strictType, column.declaredType)

/-- Every column of the list with the strict type ANY has the declared type {lit}`ANY`. -/
def AnyDeclared (columns : List CatalogColumn) : Prop :=
  ∀ column ∈ columns, column.strictType = some .any → column.declaredType = some "ANY"

/-- For every two lists of columns with the same list of strict types and declared types: if every column of
the first list with the strict type ANY has the declared type {lit}`ANY`, so has every column of the second
list. Proof sketch: a column of the second list has the strict type and the declared type of a column of
the first list. -/
theorem AnyDeclared.of_typing {old new : List CatalogColumn} (declared : AnyDeclared old)
    (same : new.map CatalogColumn.typing = old.map CatalogColumn.typing) : AnyDeclared new := by
  intro column member strict
  have : column.typing ∈ old.map CatalogColumn.typing := same ▸ List.mem_map_of_mem member
  obtain ⟨other, inOld, equal⟩ := List.mem_map.mp this
  simp only [CatalogColumn.typing, Prod.mk.injEq] at equal
  rw [← equal.2]
  exact declared other inOld (equal.1.trans strict)

/-- For every two lists of columns with the same layouts, the lists have the same strict types and declared types. Proof sketch: the strict type and the declared type are parts of the layout.  -/
theorem typing_eq_of_layout {old new : List CatalogColumn}
    (same : new.map CatalogColumn.layout = old.map CatalogColumn.layout) :
    new.map CatalogColumn.typing = old.map CatalogColumn.typing := by
  have := congrArg (List.map fun (layout : Identifier × Option String × Option StrictType × Bool) =>
    (layout.2.2.1, layout.2.1)) same
  have typing : ∀ columns : List CatalogColumn,
      columns.map CatalogColumn.typing = columns.map fun column => (column.strictType, column.declaredType) :=
    fun _ => rfl
  rw [typing, typing]
  simpa [List.map_map, Function.comp_def, CatalogColumn.layout] using this

/-- For every column with a position in a list whose strict ANY columns have the declared type ANY: if
the column is not generated and its declared type aliases the rowid, the column is an alias column.
Proof sketch: the strict type is not ANY, because then the declared type is {lit}`ANY`, which does not
alias the rowid; so the affinity is the affinity of the declared type, INTEGER
({name}`affinityOf_of_aliasesRowid`). -/
theorem AliasColumn.of_aliasesRowid {columns : List CatalogColumn} {position : Nat} {column : CatalogColumn}
    (found : columns[position]? = some column) (generated : column.generated = none)
    (aliases : aliasesRowid column.declaredType = true) (declared : AnyDeclared columns) :
    AliasColumn columns position := by
  refine ⟨column, found, generated, ?_⟩
  have notAny : (column.strictType == some StrictType.any) = false := by
    cases hstrict : column.strictType with
    | none => rfl
    | some strict =>
      cases strict <;> try rfl
      have := declared column (List.mem_of_getElem? found) hstrict
      have upper : "ANY".toUpper ≠ "INTEGER" := by
        rw [String.toUpper, String.map_eq_internal]; decide
      simp [this, aliasesRowid, upper] at aliases
  simp [CatalogColumn.affinity, notAny, affinityOf_of_aliasesRowid aliases]

/-- The facts that CREATE TABLE keeps while it builds a table:
* the table satisfies {name}`CatalogTable.Shaped`;
* the table is not WITHOUT ROWID;
* every column of the table with the strict type ANY has the declared type {lit}`ANY`. -/
structure CatalogTable.Draft (table : CatalogTable) : Prop where
  /-- The keys, the names and the rowid alias are as CatalogTable.supported needs. -/
  shaped : table.Shaped
  /-- The table is not WITHOUT ROWID. -/
  ordinary : table.withoutRowid = false
  /-- A strict ANY column has the declared type ANY. -/
  declared : AnyDeclared table.columns

/-- The table is a {name}`CatalogTable.Draft` while the constraints of the column that the definition
describes apply: the table has a last column, and its declared type is the reported type of the
definition ({name}`reportedType`). -/
def CatalogTable.Building (definition : Syntax.ColumnDefinition) (table : CatalogTable) : Prop :=
  table.Draft ∧ table.columns.getLast?.map (·.declaredType) = some (reportedType definition.declaredType)

/-- For every table that is building a column and every table with the same strict types and declared
types of the columns, the same folded names, the same number of columns, the same keys, alias and
rowid kind, and an alias column wherever the first table has one, the second table is building the
column. Proof sketch: each fact reads only these parts ({name}`CatalogTable.Shaped.of_columns`). -/
theorem CatalogTable.Building.of_columns {definition : Syntax.ColumnDefinition} {old new : CatalogTable}
    (building : old.Building definition)
    (typing : new.columns.map CatalogColumn.typing = old.columns.map CatalogColumn.typing)
    (named : new.columns.map (·.name.folded) = old.columns.map (·.name.folded))
    (aliased : ∀ position, old.rowidAlias = some position → AliasColumn old.columns position →
      AliasColumn new.columns position)
    (primaryKey : new.primaryKey = old.primaryKey) (uniqueKeys : new.uniqueKeys = old.uniqueKeys)
    (alias : new.rowidAlias = old.rowidAlias) (ordinary : new.withoutRowid = old.withoutRowid) :
    new.Building definition := by
  obtain ⟨⟨shaped, off, declared⟩, last⟩ := building
  have length : new.columns.length = old.columns.length := by
    simpa [CatalogColumn.typing] using congrArg List.length typing
  refine ⟨⟨shaped.of_columns length named aliased primaryKey uniqueKeys alias, ordinary.trans off,
    declared.of_typing typing⟩, ?_⟩
  rw [← last]
  have := congrArg (fun items => items.getLast?.map Prod.snd) typing
  simpa [List.getLast?_map, Option.map_map, Function.comp_def, CatalogColumn.typing] using this

/-- For every table that is building a column and every table with the same layouts of the columns, the same primary key, UNIQUE keys, rowid alias and rowid kind, the second table is building the column. Proof sketch: {name}`CatalogTable.Building.of_columns`, with the strict types, the declared types and the names taken from the layouts, and the alias column kept by {name}`AliasColumn.of_layout`.  -/
theorem CatalogTable.Building.of_layout {definition : Syntax.ColumnDefinition} {old new : CatalogTable}
    (building : old.Building definition)
    (columns : new.columns.map CatalogColumn.layout = old.columns.map CatalogColumn.layout)
    (primaryKey : new.primaryKey = old.primaryKey) (uniqueKeys : new.uniqueKeys = old.uniqueKeys)
    (alias : new.rowidAlias = old.rowidAlias) (ordinary : new.withoutRowid = old.withoutRowid) :
    new.Building definition := by
  refine building.of_columns (typing_eq_of_layout columns) ?_ (fun _ _ column => column.of_layout columns)
    primaryKey uniqueKeys alias ordinary
  have := congrArg (List.map fun (layout : Identifier × Option String × Option StrictType × Bool) =>
    layout.1.folded) columns
  simpa [List.map_map, Function.comp_def, CatalogColumn.layout] using this

/-- For every two lists of columns with the same layouts, the lists have the same names. Proof sketch: the name is a part of the layout.  -/
theorem names_eq_of_layout {old new : List CatalogColumn}
    (same : new.map CatalogColumn.layout = old.map CatalogColumn.layout) :
    new.map (·.name) = old.map (·.name) := by
  have := congrArg (List.map fun (layout : Identifier × Option String × Option StrictType × Bool) => layout.1) same
  simpa [List.map_map, Function.comp_def, CatalogColumn.layout] using this

/-- For every two lists of columns with the same names, the lists have the same folded names. Proof sketch: map the folding over the equal lists of names.  -/
theorem folded_eq_of_names {old new : List CatalogColumn} (same : new.map (·.name) = old.map (·.name)) :
    new.map (·.name.folded) = old.map (·.name.folded) := by
  have := congrArg (List.map Identifier.folded) same
  simpa [List.map_map, Function.comp_def] using this

/-- For every draft table and every second table with the same columns and the same rowid kind: if each position of the primary key of the second table is below the number of columns, each UNIQUE key of the second table is not empty and has only positions below the number of columns, and each rowid alias position of the second table has the primary key that is that position alone and is an alias column ({name}`AliasColumn`) of the columns, the second table is a draft. Proof sketch: the columns, and so the names and the strict ANY columns, are those of the first table.  -/
theorem CatalogTable.Draft.of_keys {old new : CatalogTable} (draft : old.Draft) (columns : new.columns = old.columns)
    (ordinary : new.withoutRowid = old.withoutRowid)
    (primaryKey : ∀ position ∈ new.primaryKey, position < old.columns.length)
    (uniqueKeys : ∀ key ∈ new.uniqueKeys, key ≠ [] ∧ ∀ position ∈ key, position < old.columns.length)
    (alias : ∀ position, new.rowidAlias = some position →
      new.primaryKey = [position] ∧ AliasColumn old.columns position) : new.Draft := by
  exact ⟨⟨by rw [columns]; exact primaryKey, by rw [columns]; exact uniqueKeys,
    by rw [columns]; exact draft.shaped.names, fun position found => by rw [columns]; exact alias position found⟩,
    ordinary.trans draft.ordinary, by rw [columns]; exact draft.declared⟩

end Belay.Sqlite.Model
