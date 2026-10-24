import Belay.Sqlite.Model.ResolveDraft
import Belay.Sqlite.Model.ResolveKeyCases

set_option doc.verso true

/-! The column constraints of CREATE TABLE keep the invariant of the table (ADR 0022, D3, slice 4):
a table that is {lit}`Building` a column is still building it after {lit}`applyConstraint`, and the
names of the columns and the strictness do not change. -/

namespace Belay.Sqlite.Model

/-- The table {lit}`new` is building the column that the definition describes, and has the names of
the columns and the strictness of the table {lit}`old`. -/
def CatalogTable.BuildStep (definition : Syntax.ColumnDefinition) (old new : CatalogTable) : Prop :=
  new.Building definition ∧ new.columns.map (·.name) = old.columns.map (·.name) ∧ new.strict = old.strict

/-- For every table that is building a column, there is a column that is the last element of the list of columns and the element at the position one below the number of columns, whose declared type is the reported type of the definition ({name}`reportedType`), and the list is not empty. Proof sketch: the building says that the declared type of the last element is the reported type.  -/
theorem CatalogTable.Building.last {definition : Syntax.ColumnDefinition} {table : CatalogTable}
    (building : table.Building definition) :
    ∃ column, table.columns.getLast? = some column ∧ table.columns[table.columns.length - 1]? = some column ∧
      column.declaredType = reportedType definition.declaredType ∧ 0 < table.columns.length := by
  have last := building.2
  cases found : table.columns.getLast? with
  | none => simp [found] at last
  | some column =>
    have indexed := found
    rw [List.getLast?_eq_getElem?] at indexed
    have inside := (List.getElem?_eq_some_iff.mp indexed).1
    refine ⟨column, rfl, ?_, ?_, by omega⟩
    · rw [← List.getLast?_eq_getElem?]; exact found
    rw [found] at last
    simpa using last

/-- For every table that is building a column and every change of a column that keeps the layout of each column, the table with {name}`updateLast` of its columns with the change is a step of the building ({name}`CatalogTable.BuildStep`). Proof sketch: {name}`updateLast` keeps the list of layouts ({name}`map_updateLast`), so {name}`CatalogTable.Building.of_layout` applies.  -/
theorem CatalogTable.BuildStep.of_updateLast {definition : Syntax.ColumnDefinition} {table : CatalogTable}
    (building : table.Building definition) (change : CatalogColumn → CatalogColumn)
    (keeps : ∀ column, (change column).layout = column.layout) :
    CatalogTable.BuildStep definition table { table with columns := updateLast table.columns change } := by
  have same : (updateLast table.columns change).map CatalogColumn.layout = table.columns.map CatalogColumn.layout :=
    map_updateLast _ _ _ keeps
  exact ⟨building.of_layout same rfl rfl rfl rfl, names_eq_of_layout same, rfl⟩

/-- For every table that is building a column and every change of the last column that keeps its
name, strict type and declared type: if the table has no rowid alias at the last column, the table
with the changed last column is a step of the building. Proof sketch: the alias column is not the last
column, so {name}`updateLast` keeps it ({name}`AliasColumn.updateLast`). -/
theorem CatalogTable.BuildStep.of_updateLast_unaliased {definition : Syntax.ColumnDefinition} {table : CatalogTable}
    (building : table.Building definition) (change : CatalogColumn → CatalogColumn)
    (keeps : ∀ column, (change column).name = column.name ∧ (change column).typing = column.typing)
    (unaliased : ∀ position, table.rowidAlias = some position → position + 1 < table.columns.length) :
    CatalogTable.BuildStep definition table { table with columns := updateLast table.columns change } := by
  have names : (updateLast table.columns change).map (·.name) = table.columns.map (·.name) :=
    map_updateLast _ _ _ fun column => (keeps column).1
  refine ⟨building.of_columns (new := { table with columns := updateLast table.columns change })
    (map_updateLast _ _ _ fun column => (keeps column).2) (folded_eq_of_names names) ?_ rfl rfl rfl rfl,
    names, rfl⟩
  exact fun position found alias => alias.updateLast change (unaliased position found)

/-- For every table that is building a column and every second table with the same columns, the same
strictness and the same rowid kind: assume three facts about the second table.
* Each position of its primary key is below the number of columns.
* Each of its UNIQUE keys is not empty and has only positions below the number of columns.
* Each of its rowid alias positions is its whole primary key and is an alias column of the columns.

Then the second table is a step of the building. It is building the column, it has the names of the
columns, and it has the strictness of the first table. Proof sketch: {name}`CatalogTable.Draft.of_keys`;
the last column is unchanged. -/
theorem CatalogTable.BuildStep.of_keys {definition : Syntax.ColumnDefinition} {old new : CatalogTable}
    (building : old.Building definition) (columns : new.columns = old.columns) (strict : new.strict = old.strict)
    (ordinary : new.withoutRowid = old.withoutRowid)
    (primaryKey : ∀ position ∈ new.primaryKey, position < old.columns.length)
    (uniqueKeys : ∀ key ∈ new.uniqueKeys, key ≠ [] ∧ ∀ position ∈ key, position < old.columns.length)
    (alias : ∀ position, new.rowidAlias = some position →
      new.primaryKey = [position] ∧ AliasColumn old.columns position) :
    CatalogTable.BuildStep definition old new :=
  ⟨⟨building.1.of_keys columns ordinary primaryKey uniqueKeys alias, by rw [columns]; exact building.2⟩,
    by rw [columns], strict⟩

/-- For every table that is building a column, direction and algorithm: if {name}`applyConstraint` of the PRIMARY KEY constraint of the column gives a table, the table is a step of the building ({name}`CatalogTable.BuildStep`). Proof sketch: the checks of the constraint leave a table without a primary key and a last column that is not generated; {name}`setPrimaryKey_cases` shows that the key is the last position, and that the alias, if any, is on a column that is not generated and whose declared type aliases the rowid ({name}`AliasColumn.of_aliasesRowid`).  -/
theorem applyConstraint_primaryKey {tableName : Identifier} {definition : Syntax.ColumnDefinition}
    {table result : CatalogTable} (building : table.Building definition) (descending : Bool)
    (algorithm : Option ConflictAlgorithm)
    (ok : applyConstraint tableName definition table (.primaryKey descending algorithm) = .ok result) :
    CatalogTable.BuildStep definition table result := by
  obtain ⟨column, getLast, indexed, declared, positive⟩ := building.last
  simp only [applyConstraint, getLast, Option.bind_some] at ok
  split at ok
  · cases ok
  split at ok
  · cases ok
  rename_i empty generated
  obtain ⟨columns, strict, ordinary, primaryKey, alias, uniqueKeys⟩ := setPrimaryKey_cases ok
  have unbounded := building.1.shaped
  refine CatalogTable.BuildStep.of_keys building columns strict ordinary ?_ ?_ ?_
  · intro position member
    rw [primaryKey] at member
    simp only [List.mem_singleton] at member
    omega
  · exact fun key member => unbounded.uniqueKeys key (uniqueKeys key member)
  · intro position found
    rw [alias] at found
    split at found
    · rename_i aliases
      cases found
      refine ⟨primaryKey, AliasColumn.of_aliasesRowid indexed ?_ ?_ building.1.declared⟩
      · simpa using generated
      · simp only [Bool.and_eq_true] at aliases
        rw [declared]; exact aliases.1
    · cases found

/-- For every table that is building a column and every constraint of the column: if
{name}`applyConstraint` gives a table, the table is a step of the building. Proof sketch: the
constraints that change a column in place (DEFAULT, NOT NULL, COLLATE, REFERENCES) keep its layout; a
generated column changes only the generated flag, of a column that is not the rowid alias, because the
alias is the primary key, which the check refuses; the key constraints keep the columns. -/
theorem applyConstraint_step {tableName : Identifier} {definition : Syntax.ColumnDefinition}
    {table result : CatalogTable} (building : table.Building definition) (constraint : Syntax.ColumnConstraint)
    (ok : applyConstraint tableName definition table constraint = .ok result) :
    CatalogTable.BuildStep definition table result := by
  obtain ⟨column, getLast, indexed, declared, positive⟩ := building.last
  cases constraint with
  | primaryKey descending algorithm => exact applyConstraint_primaryKey building descending algorithm ok
  | check condition label => cases ok; exact ⟨building, rfl, rfl⟩
  | unique algorithm =>
    obtain ⟨columns, strict, ordinary, primaryKey, alias, uniqueKeys⟩ := addUniqueKey_cases ok
    have shaped := building.1.shaped
    refine CatalogTable.BuildStep.of_keys building columns strict ordinary
      (fun position member => shaped.primaryKey position (by rw [← primaryKey]; exact member)) ?_ ?_
    · intro key member
      rcases uniqueKeys key member with old | new
      · exact shaped.uniqueKeys key old
      · subst new
        exact ⟨by simp, fun position member => by simp at member; omega⟩
    · intro position found
      rw [alias] at found
      obtain ⟨key, aliased⟩ := shaped.alias position found
      exact ⟨primaryKey.trans key, aliased⟩
  | default value text =>
    simp only [applyConstraint] at ok
    repeat' split at ok
    all_goals first | (cases ok; done) | (cases ok; exact .of_updateLast building _ fun _ => rfl)
  | notNull algorithm =>
    simp only [applyConstraint] at ok
    cases ok
    exact .of_updateLast building _ fun _ => rfl
  | collate name =>
    simp only [applyConstraint] at ok
    repeat' split at ok
    all_goals first | (cases ok; done) | (cases ok; exact .of_updateLast building _ fun _ => rfl)
  | references referenced columns onDelete onUpdate =>
    simp only [applyConstraint] at ok
    repeat' split at ok
    all_goals first | (cases ok; done) | (cases ok; exact .of_updateLast building _ fun _ => rfl)
  | deferral deferred =>
    simp only [applyConstraint] at ok
    cases ok
    obtain ⟨columns, primaryKey, uniqueKeys, alias, ordinary, strict⟩ := CatalogTable.deferLast_keeps table deferred
    exact ⟨building.of_layout columns primaryKey uniqueKeys alias ordinary, names_eq_of_layout columns, strict⟩
  | generated expression kind =>
    simp only [applyConstraint] at ok
    repeat' split at ok
    all_goals first | (cases ok; done) | skip
    rename_i _ _ notKey _
    cases ok
    refine .of_updateLast_unaliased building _ (fun _ => ⟨rfl, rfl⟩) fun position found => ?_
    obtain ⟨key, _⟩ := building.1.shaped.alias position found
    have inside := building.1.shaped.primaryKey position (by rw [key]; simp)
    rw [key] at notKey
    simp at notKey
    omega

end Belay.Sqlite.Model
