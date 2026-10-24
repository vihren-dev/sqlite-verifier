import Belay.Sqlite.Model.CatalogTableLaws
import Belay.Sqlite.Model.Resolution.Definitions

set_option doc.verso true

/-! The invariant of the table that CREATE TABLE builds (ADR 0022, D3, slice 4): the keys name
columns of the table, the rowid alias is as {lit}`CatalogTable.supported` says, and no two columns
have one folded name. {lit}`ResolveDefinitionsShaped` shows that the steps of the resolution keep it,
and {lit}`ResolveCreateTableValid` gets {lit}`Catalog.Valid` from it. The steps change the columns
without changing their names, types and generated flags ({lit}`CatalogColumn.layout`), so the
transfer lemmas of this file carry the invariant along such a change. -/

namespace Belay.Sqlite.Model

/-- The parts of a column that the invariant reads: its name, declared type, strict type and whether
it is generated. A step of the resolution that changes only other parts of the columns keeps the
list of layouts, for example a DEFAULT, a collation, a CHECK or a foreign key. -/
def CatalogColumn.layout (column : CatalogColumn) : Identifier × Option String × Option StrictType × Bool :=
  (column.name, column.declaredType, column.strictType, column.generated.isSome)

/-- The column at the position of the list is not generated and has INTEGER affinity, the column of
a rowid alias. -/
def AliasColumn (columns : List CatalogColumn) (position : Nat) : Prop :=
  ∃ column, columns[position]? = some column ∧ column.generated = none ∧ column.affinity = .integer

/-- For every two columns with one layout, the columns have the same affinity. Proof sketch: the
affinity reads the strict type and the declared type. -/
theorem CatalogColumn.affinity_of_layout {first second : CatalogColumn} (same : first.layout = second.layout) :
    first.affinity = second.affinity := by
  simp only [CatalogColumn.layout, Prod.mk.injEq] at same
  simp only [CatalogColumn.affinity, same.2.1, same.2.2.1]

/-- For every two lists of columns with the same layouts and every position, the alias column of the
first list is the alias column of the second. Proof sketch: the column at the position of the second
list has the layout of the first, which fixes the generated flag and the affinity. -/
theorem AliasColumn.of_layout {old new : List CatalogColumn} {position : Nat} (alias : AliasColumn old position)
    (same : new.map CatalogColumn.layout = old.map CatalogColumn.layout) : AliasColumn new position := by
  obtain ⟨column, found, generated, integer⟩ := alias
  have at_position : (new[position]?).map CatalogColumn.layout = (old[position]?).map CatalogColumn.layout := by
    rw [← List.getElem?_map, ← List.getElem?_map, same]
  rw [found] at at_position
  cases hnew : new[position]? with
  | none => simp [hnew] at at_position
  | some other =>
    simp only [hnew, Option.map_some, Option.some.injEq] at at_position
    refine ⟨other, hnew, ?_, ?_⟩
    · have := congrArg (fun layout => layout.2.2.2) at_position
      simp_all [CatalogColumn.layout]
    · rw [CatalogColumn.affinity_of_layout at_position]
      exact integer

/-- The facts about the keys, the names and the rowid alias that a table needs for
{name}`CatalogTable.supported`, while CREATE TABLE builds it:
* each position of the primary key is below the number of columns;
* each UNIQUE key is not empty and has only positions below the number of columns;
* no two columns have one folded name;
* a rowid alias at a position is the whole primary key, and its column is an alias column
  ({name}`AliasColumn`).

The table need not be complete: the CHECK constraints and the limits are not part of it. -/
structure CatalogTable.Shaped (table : CatalogTable) : Prop where
  /-- Each position of the primary key is below the number of columns. -/
  primaryKey : ∀ position ∈ table.primaryKey, position < table.columns.length
  /-- Each UNIQUE key is not empty and names only columns of the table. -/
  uniqueKeys : ∀ key ∈ table.uniqueKeys, key ≠ [] ∧ ∀ position ∈ key, position < table.columns.length
  /-- No two columns have one folded name. -/
  names : (table.columns.map (·.name.folded)).Nodup
  /-- A rowid alias is the whole primary key, and its column is an alias column. -/
  alias : ∀ position, table.rowidAlias = some position →
    table.primaryKey = [position] ∧ AliasColumn table.columns position

/-- For every table that satisfies {name}`CatalogTable.Shaped` and every table with the same keys, the
same alias, the same number of columns, the same folded names, and an alias column wherever the first
table has one, the second table satisfies it. Proof sketch: each clause of the structure reads
only these parts. -/
theorem CatalogTable.Shaped.of_columns {old new : CatalogTable} (shaped : old.Shaped)
    (length : new.columns.length = old.columns.length)
    (named : new.columns.map (·.name.folded) = old.columns.map (·.name.folded))
    (aliased : ∀ position, old.rowidAlias = some position → AliasColumn old.columns position →
      AliasColumn new.columns position)
    (primaryKey : new.primaryKey = old.primaryKey) (uniqueKeys : new.uniqueKeys = old.uniqueKeys)
    (alias : new.rowidAlias = old.rowidAlias) : new.Shaped := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · rw [primaryKey, length]; exact shaped.primaryKey
  · rw [uniqueKeys, length]; exact shaped.uniqueKeys
  · rw [named]; exact shaped.names
  · intro position found
    rw [alias] at found
    obtain ⟨key, column⟩ := shaped.alias position found
    exact ⟨primaryKey.trans key, aliased position found column⟩

/-- For every table that satisfies {name}`CatalogTable.Shaped` and every table with the same keys,
the same alias and columns with the same layouts, the second table satisfies it. Proof sketch: the
number of columns, their names and the alias column depend only on the layouts. -/
theorem CatalogTable.Shaped.of_layout {old new : CatalogTable} (shaped : old.Shaped)
    (columns : new.columns.map CatalogColumn.layout = old.columns.map CatalogColumn.layout)
    (primaryKey : new.primaryKey = old.primaryKey) (uniqueKeys : new.uniqueKeys = old.uniqueKeys)
    (alias : new.rowidAlias = old.rowidAlias) : new.Shaped := by
  refine shaped.of_columns (by simpa using congrArg List.length columns) ?_
    (fun _ _ column => column.of_layout columns) primaryKey uniqueKeys alias
  have := congrArg (List.map fun (layout : Identifier × Option String × Option StrictType × Bool) =>
    layout.1.folded) columns
  simpa [List.map_map, Function.comp_def, CatalogColumn.layout] using this

/-- For every list and function, {name}`updateLast` of the list with the function has the length of the list. Proof sketch: induction over the list; the cases for the empty list and for one element keep the length.  -/
theorem length_updateLast (items : List α) (change : α → α) : (updateLast items change).length = items.length := by
  induction items with
  | nil => rfl
  | cons first rest ih =>
    cases rest with
    | nil => rfl
    | cons second more => simp [updateLast, ih]

/-- For every list, function and position with at least one element after it, {name}`updateLast` of the list with the function has at the position the element of the list. Proof sketch: induction over the list; only the last element changes.  -/
theorem getElem?_updateLast (items : List α) (change : α → α) {position : Nat} (inside : position + 1 < items.length) :
    (updateLast items change)[position]? = items[position]? := by
  induction items generalizing position with
  | nil => simp at inside
  | cons first rest ih =>
    cases rest with
    | nil => simp at inside
    | cons second more =>
      cases position with
      | zero => simp [updateLast]
      | succ place => simpa [updateLast] using ih (by simpa using inside)

/-- For every list, function that changes an element, and function on the elements whose value the change keeps, the values of the function on {name}`updateLast` of the list with the change are the values of the function on the list. Proof sketch: induction over the list; only the last element changes, and its value is kept.  -/
theorem map_updateLast (items : List α) (change : α → α) (value : α → β) (keeps : ∀ item, value (change item) = value item) :
    (updateLast items change).map value = items.map value := by
  induction items with
  | nil => rfl
  | cons first rest ih =>
    cases rest with
    | nil => simp [updateLast, keeps]
    | cons second more => simpa [updateLast] using ih

/-- For every alias column that is not the last column, and every change of the last column, the column
is still an alias column of the list after {name}`updateLast`. Proof sketch: {name}`getElem?_updateLast`. -/
theorem AliasColumn.updateLast {columns : List CatalogColumn} {position : Nat} (alias : AliasColumn columns position)
    (change : CatalogColumn → CatalogColumn) (inside : position + 1 < columns.length) :
    AliasColumn (Belay.Sqlite.Model.updateLast columns change) position := by
  obtain ⟨column, found, rest⟩ := alias
  exact ⟨column, by rw [getElem?_updateLast columns change inside]; exact found, rest⟩

end Belay.Sqlite.Model
