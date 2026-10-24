import Belay.Sqlite.Model.ResolveTableShaped
import Belay.Sqlite.Model.ResolveCallsBelow
import Belay.Sqlite.Model.Resolution.KeyMerge
import Belay.Sqlite.Model.Resolution.ParentKeys
import Belay.Sqlite.Model.ResolveNamesBelow

set_option doc.verso true

/-! The small facts about the steps of CREATE TABLE that {lit}`ResolveDefinitionsShaped` combines
(ADR 0022, D3, slice 4): what the key steps ({lit}`setPrimaryKey`, {lit}`addUniqueKey`,
{lit}`keyPositions`) and the steps that change the columns ({lit}`CatalogTable.deferLast`) leave
unchanged. -/

namespace Belay.Sqlite.Model

/-- For every fold over a list that can fail, property, and step that keeps the property: if the
property holds for the start value and the fold gives a value, the property holds for the value.
Proof sketch: induction over the list. -/
theorem foldlM_except_invariant {ε α β : Type} (step : β → α → Except ε β) (property : β → Prop)
    (keeps : ∀ before item after, property before → step before item = .ok after → property after) :
    ∀ (items : List α) (start final : β), property start → items.foldlM step start = .ok final → property final
  | [], start, final, h, ok => by
    simp only [List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at ok; subst ok; exact h
  | item :: rest, start, final, h, ok => by
    simp only [List.foldlM_cons, exceptBind_eq_ok] at ok
    obtain ⟨next, hnext, hrest⟩ := ok
    exact foldlM_except_invariant step property keeps rest next final (keeps _ _ _ h hnext) hrest

/-- For every table, positions, alias, direction and algorithm: if {name}`setPrimaryKey` gives a
table, the table has the columns, the strictness and the rowid kind of the old table, the positions
as primary key, the alias, and no UNIQUE key that the old table did not have. Proof sketch: both
cases of {name}`setPrimaryKey` update only keys. -/
theorem setPrimaryKey_cases {table result : CatalogTable} {positions : List Nat} {alias : Option Nat}
    {descending : Bool} {algorithm : Option ConflictAlgorithm}
    (ok : setPrimaryKey table positions alias descending algorithm = .ok result) :
    result.columns = table.columns ∧ result.strict = table.strict ∧ result.withoutRowid = table.withoutRowid ∧
      result.primaryKey = positions ∧ result.rowidAlias = alias ∧ ∀ key ∈ result.uniqueKeys, key ∈ table.uniqueKeys := by
  unfold setPrimaryKey at ok
  rcases alias with _ | place
  · cases hfind : table.uniqueKeys.idxOf? positions with
    | none =>
      simp only [hfind] at ok
      cases ok
      exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ member => member⟩
    | some index =>
      simp only [hfind, exceptBind_eq_ok] at ok
      obtain ⟨_, _, same⟩ := ok
      cases same
      exact ⟨rfl, rfl, rfl, rfl, rfl, fun key member => List.mem_of_mem_eraseIdx member⟩
  · cases hfind : table.uniqueKeys.idxOf? positions <;> (simp only at ok; cases ok)
    all_goals exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ member => member⟩

/-- For every table, positions and algorithm: if {name}`addUniqueKey` gives a table, the table has the
columns, the strictness, the rowid kind, the primary key and the alias of the old table, and each of
its UNIQUE keys is a UNIQUE key of the old table or the new positions. Proof sketch: a key that is
already there changes only an algorithm, and a new key is appended. -/
theorem addUniqueKey_cases {table result : CatalogTable} {positions : List Nat} {algorithm : Option ConflictAlgorithm}
    (ok : addUniqueKey table positions algorithm = .ok result) :
    result.columns = table.columns ∧ result.strict = table.strict ∧ result.withoutRowid = table.withoutRowid ∧
      result.primaryKey = table.primaryKey ∧ result.rowidAlias = table.rowidAlias ∧
      ∀ key ∈ result.uniqueKeys, key ∈ table.uniqueKeys ∨ key = positions := by
  unfold addUniqueKey at ok
  split at ok
  · simp only [exceptBind_eq_ok] at ok
    obtain ⟨_, _, same⟩ := ok
    cases same
    exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ member => .inl member⟩
  · split at ok
    · simp only [exceptBind_eq_ok] at ok
      obtain ⟨_, _, same⟩ := ok
      cases same
      exact ⟨rfl, rfl, rfl, rfl, rfl, fun _ member => .inl member⟩
    · cases ok
      refine ⟨rfl, rfl, rfl, rfl, rfl, fun key member => ?_⟩
      rcases List.mem_append.mp member with old | new
      · exact .inl old
      · exact .inr (List.mem_singleton.mp new)

/-- For every columns, names and positions: if {name}`keyPositions` gives positions, there is one
position for each name, and each is below the number of columns. Proof sketch: induction over the
names; a found column is below the length ({name}`columnPosition_lt`). -/
theorem keyPositions_cases {columns : List CatalogColumn} :
    ∀ {names : List Identifier} {positions : List Nat}, keyPositions columns names = .ok positions →
      positions.length = names.length ∧ ∀ position ∈ positions, position < columns.length
  | [], positions, ok => by
    simp only [keyPositions, Except.ok.injEq] at ok; subst ok; simp
  | name :: rest, positions, ok => by
    simp only [keyPositions] at ok
    cases found : columnPosition columns name with
    | none => simp [found] at ok
    | some position =>
      simp only [found] at ok
      cases hrest : keyPositions columns rest with
      | error _ => simp [hrest, Except.map] at ok
      | ok tail =>
        simp only [hrest, Except.map, Except.ok.injEq] at ok
        subst ok
        obtain ⟨lengths, below⟩ := keyPositions_cases hrest
        refine ⟨by simp [lengths], fun place member => ?_⟩
        rcases List.mem_cons.mp member with rfl | inner
        · exact columnPosition_lt found
        · exact below place inner

/-- For every list, position and function that keeps the value of a function, the list after
{lit}`List.modify` has the same values of the function. Proof sketch: compare the elements at each
position. -/
theorem map_modify (items : List α) (position : Nat) (change : α → α) (value : α → β)
    (keeps : ∀ item, value (change item) = value item) : (items.modify position change).map value = items.map value := by
  apply List.ext_getElem?
  intro place
  simp only [List.getElem?_map, List.getElem?_modify]
  by_cases same : position = place
  · subst same; cases items[position]? <;> simp [keeps]
  · simp [same]

/-- For every list, function of a position and an element, and function on the elements whose value the first function keeps for each position, the values on {lit}`List.mapIdx` of the list are the values on the list. Proof sketch: compare the elements at each position.  -/
theorem map_mapIdx (items : List α) (change : Nat → α → α) (value : α → β)
    (keeps : ∀ place item, value (change place item) = value item) : (items.mapIdx change).map value = items.map value := by
  apply List.ext_getElem?
  intro place
  simp only [List.getElem?_map, List.getElem?_mapIdx]
  cases items[place]? <;> simp [keeps]

/-- For every table and deferral, {name}`CatalogTable.deferLast` keeps the layouts of the columns, the
keys, the alias, the strictness and the rowid kind. Proof sketch: it changes the foreign keys of the
table or of one column. -/
theorem CatalogTable.deferLast_keeps (table : CatalogTable) (deferred : Bool) :
    (table.deferLast deferred).columns.map CatalogColumn.layout = table.columns.map CatalogColumn.layout ∧
      (table.deferLast deferred).primaryKey = table.primaryKey ∧
      (table.deferLast deferred).uniqueKeys = table.uniqueKeys ∧ (table.deferLast deferred).rowidAlias = table.rowidAlias ∧
      (table.deferLast deferred).withoutRowid = table.withoutRowid ∧ (table.deferLast deferred).strict = table.strict := by
  unfold CatalogTable.deferLast
  split
  · exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
  · split
    · exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
    · exact ⟨map_modify _ _ _ _ fun _ => rfl, rfl, rfl, rfl, rfl, rfl⟩

end Belay.Sqlite.Model
