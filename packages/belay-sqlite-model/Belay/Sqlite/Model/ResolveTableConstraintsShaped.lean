import Belay.Sqlite.Model.ResolveDefinitionsShaped

set_option doc.verso true

/-! The table constraints of CREATE TABLE keep the invariant of the table (ADR 0022, D3, slice 4):
a draft stays a draft after {lit}`addTableConstraints`, and the names of the columns do not change. -/

namespace Belay.Sqlite.Model

/-- For every draft table and key positions that are below the number of columns and name no generated
column: if the table PRIMARY KEY makes the positions a rowid alias at a position, the key is that
position alone and its column is an alias column. Proof sketch: only a key of one position can be an
alias, and its column is not generated and has a declared type that aliases the rowid
({name}`AliasColumn.of_aliasesRowid`). -/
theorem tableKeyAlias {table : CatalogTable} (draft : table.Draft) {positions : List Nat} {alias : Nat}
    (found : (match positions with
      | [position] => if aliasesRowid (table.columns[position]?.bind fun x => x.declaredType) = true then some position
        else none
      | _ => none) = some alias)
    (below : ∀ position ∈ positions, position < table.columns.length)
    (noGenerated : ¬(positions.any fun position => (table.columns[position]?.bind fun x => x.generated).isSome) = true) :
    positions = [alias] ∧ AliasColumn table.columns alias := by
  rcases positions with _ | ⟨place, _ | ⟨other, tail⟩⟩ <;> try (simp at found; done)
  by_cases aliases : aliasesRowid (table.columns[place]?.bind fun x => x.declaredType) = true
  · simp only [aliases, ite_true, Option.some.injEq] at found
    subst found
    have inside := below place (by simp)
    obtain ⟨column, hcolumn⟩ : ∃ column, table.columns[place]? = some column :=
      ⟨_, List.getElem?_eq_getElem inside⟩
    simp only [hcolumn, Option.bind_some, List.any_cons, List.any_nil, Bool.or_false] at aliases noGenerated
    refine ⟨rfl, AliasColumn.of_aliasesRowid hcolumn ?_ aliases draft.declared⟩
    simpa using noGenerated
  · simp [aliases] at found

/-- For every table name, draft table and list of table constraints: if {name}`addTableConstraints`
gives a table, the table is a draft with the names of the columns of the table. Proof sketch:
induction over the constraints; a key constraint names positions below the number of columns
({name}`keyPositions_cases`) and sets a rowid alias only for one column that is not generated and
whose declared type aliases the rowid ({name}`AliasColumn.of_aliasesRowid`); the other constraints
keep the columns, the keys and the alias, or keep the layouts of the columns. -/
theorem addTableConstraints_draft {tableName : Identifier} :
    ∀ {constraints : List Syntax.TableConstraint} {table result : CatalogTable}, table.Draft →
      addTableConstraints tableName table constraints = .ok result →
      result.Draft ∧ result.columns.map (·.name) = table.columns.map (·.name)
  | [], table, result, draft, ok => by cases ok; exact ⟨draft, rfl⟩
  | .check .. :: rest, table, result, draft, ok => addTableConstraints_draft draft (by simpa [addTableConstraints] using ok)
  | .primaryKey [] _ :: rest, table, result, draft, ok => by cases ok
  | .unique [] _ :: rest, table, result, draft, ok => by cases ok
  | .primaryKey (name :: names) algorithm :: rest, table, result, draft, ok => by
    rw [addTableConstraints] at ok
    rotate_left
    · simp
    split at ok
    · cases ok
    dsimp only at ok
    simp only [exceptBind_eq_ok] at ok
    obtain ⟨positions, found, ok⟩ := ok
    split at ok
    · cases ok
    rename_i _ noGenerated
    simp only [exceptBind_eq_ok] at ok
    obtain ⟨keyed, hset, hrest⟩ := ok
    obtain ⟨_, below⟩ := keyPositions_cases found
    obtain ⟨columns, strict, ordinary, primaryKey, alias, uniqueKeys⟩ := setPrimaryKey_cases hset
    have unbounded := draft.shaped
    have keyedDraft : keyed.Draft := by
      refine draft.of_keys columns ordinary ?_ ?_ ?_
      · intro position member; rw [primaryKey] at member; exact below position member
      · exact fun key member => unbounded.uniqueKeys key (uniqueKeys key member)
      · intro position found'
        rw [alias] at found'
        obtain ⟨key, aliased⟩ := tableKeyAlias draft found' below noGenerated
        exact ⟨primaryKey.trans key, columns ▸ aliased⟩
    obtain ⟨final, names⟩ := addTableConstraints_draft keyedDraft hrest
    exact ⟨final, names.trans (by rw [columns])⟩
  | .unique (name :: names) algorithm :: rest, table, result, draft, ok => by
    rw [addTableConstraints] at ok
    rotate_left
    · simp
    simp only [exceptBind_eq_ok] at ok
    obtain ⟨positions, found, keyed, hset, hrest⟩ := ok
    obtain ⟨lengths, below⟩ := keyPositions_cases found
    obtain ⟨columns, strict, ordinary, primaryKey, alias, uniqueKeys⟩ := addUniqueKey_cases hset
    have unbounded := draft.shaped
    have keyedDraft : keyed.Draft := by
      refine draft.of_keys columns ordinary ?_ ?_ ?_
      · intro position member; rw [primaryKey] at member; exact unbounded.primaryKey position member
      · intro key member
        rcases uniqueKeys key member with old | new
        · exact unbounded.uniqueKeys key old
        · subst new
          refine ⟨fun empty => ?_, below⟩
          subst empty
          simp at lengths
      · intro position found'
        rw [alias] at found'
        obtain ⟨key, aliased⟩ := unbounded.alias position found'
        exact ⟨primaryKey.trans key, aliased⟩
    obtain ⟨final, names⟩ := addTableConstraints_draft keyedDraft hrest
    exact ⟨final, names.trans (by rw [columns])⟩
  | .foreignKey columns target referenced onDelete onUpdate :: rest, table, result, draft, ok => by
    rw [addTableConstraints] at ok
    split at ok
    · cases ok
    dsimp only at ok
    simp only [exceptBind_eq_ok] at ok
    obtain ⟨positions, _, hrest⟩ := ok
    have same : ∀ new : CatalogTable, new.columns = table.columns → new.primaryKey = table.primaryKey →
        new.uniqueKeys = table.uniqueKeys → new.rowidAlias = table.rowidAlias →
        new.withoutRowid = table.withoutRowid → addTableConstraints tableName new rest = .ok result →
        result.Draft ∧ result.columns.map (·.name) = table.columns.map (·.name) := by
      intro new columns primaryKey uniqueKeys alias ordinary hnew
      obtain ⟨final, names⟩ := addTableConstraints_draft (draft.of_keys columns ordinary
        (fun position member => draft.shaped.primaryKey position (primaryKey ▸ member))
        (fun key member => draft.shaped.uniqueKeys key (uniqueKeys ▸ member))
        (fun position found => by
          rw [alias] at found
          obtain ⟨key, aliased⟩ := draft.shaped.alias position found
          exact ⟨primaryKey.trans key, aliased⟩)) hnew
      exact ⟨final, names.trans (by rw [columns])⟩
    exact same { table with foreignKeys := table.foreignKeys ++
      [{ table := target, columns := positions, referenced, onDelete, onUpdate }] } rfl rfl rfl rfl rfl hrest
  | .deferral deferred :: rest, table, result, draft, ok => by
    obtain ⟨columns, primaryKey, uniqueKeys, alias, ordinary, _⟩ := CatalogTable.deferLast_keeps table deferred
    have deferred : (table.deferLast deferred).Draft :=
      ⟨draft.shaped.of_layout columns primaryKey uniqueKeys alias, ordinary.trans draft.ordinary,
        draft.declared.of_typing (typing_eq_of_layout columns)⟩
    obtain ⟨final, names⟩ := addTableConstraints_draft deferred (by simpa [addTableConstraints] using ok)
    exact ⟨final, names.trans (names_eq_of_layout columns)⟩
termination_by constraints => constraints.length

end Belay.Sqlite.Model
