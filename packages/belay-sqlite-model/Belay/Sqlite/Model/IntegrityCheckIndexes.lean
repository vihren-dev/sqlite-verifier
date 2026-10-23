import Belay.Sqlite.Model.CheckFailures
import Belay.Sqlite.Model.Resolution.Catalog

set_option doc.verso true

/-! The laws that connect the indexes that {lit}`integrity_check` checks
({lit}`Catalog.checkedIndexes`) with the unique keys of a table ({lit}`Catalog.uniqueKeys`):
each checked index has a unique key, and each unique key is the key of a checked index or the
primary key, which has no index when it is the rowid alias or the key of a {lit}`WITHOUT ROWID`
table. -/

namespace Belay.Sqlite.Model

/-- For every table and entry of {name}`CatalogTable.constraintKeys`: the entry is a UNIQUE key
of the table that is not marked as the primary key, or the primary key, marked as such, when it
has an index ({name}`CatalogTable.primaryIndexed`).
Proof sketch: the entry is in the UNIQUE keys before or after the primary key, which {lit}`take` and
{lit}`drop` keep, or it is the primary key. -/
theorem CatalogTable.of_mem_constraintKeys {table : CatalogTable} {entry : List Nat × Bool × Bool}
    (member : entry ∈ table.constraintKeys) :
    (entry.2.2 = false ∧ entry.1 ∈ table.uniqueKeys) ∨
      (entry.2.2 = true ∧ entry.1 = table.primaryKey ∧ table.primaryIndexed = true) := by
  have ofUnique : ∀ entry ∈ table.uniqueKeys.zipIdx.map (fun (positions, index) =>
      (positions, table.uniqueAlgorithm index == some ConflictAlgorithm.replace, false)), entry.2.2 = false ∧ entry.1 ∈ table.uniqueKeys := by
    intro entry found
    obtain ⟨⟨positions, index⟩, inZip, rfl⟩ := List.mem_map.mp found
    exact ⟨rfl, List.fst_mem_of_mem_zipIdx inZip⟩
  unfold CatalogTable.constraintKeys at member
  split at member
  · rcases List.mem_append.mp member with front | back
    · rcases List.mem_append.mp front with taken | primary
      · exact .inl (ofUnique entry (List.mem_of_mem_take taken))
      · simp only [List.mem_singleton] at primary
        subst primary
        exact .inr ⟨rfl, rfl, by assumption⟩
    · exact .inl (ofUnique entry (List.mem_of_mem_drop back))
  · exact .inl (ofUnique entry member)

/-- For every table and UNIQUE key of it: {name}`CatalogTable.constraintKeys` has the key, not
marked as the primary key.
Proof sketch: the key has an index in the list, so its entry is in the mapped {lit}`zipIdx`, which
the split by {lit}`take` and {lit}`drop` keeps. -/
theorem CatalogTable.mem_constraintKeys_of_unique {table : CatalogTable} {positions : List Nat}
    (member : positions ∈ table.uniqueKeys) : ∃ replace, (positions, replace, false) ∈ table.constraintKeys := by
  obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
  have inZip : (positions, index) ∈ table.uniqueKeys.zipIdx := List.mem_zipIdx_iff_getElem?.mpr found
  have inUniques := List.mem_map_of_mem (f := fun ((positions, index) : List Nat × Nat) =>
    (positions, table.uniqueAlgorithm index == some ConflictAlgorithm.replace, false)) inZip
  refine ⟨table.uniqueAlgorithm index == some ConflictAlgorithm.replace, ?_⟩
  unfold CatalogTable.constraintKeys
  split
  · rw [← List.take_append_drop table.uniqueBeforePrimary (List.map _ _)] at inUniques
    simp only [List.mem_append] at inUniques ⊢
    rcases inUniques with taken | dropped
    · exact .inl (.inl taken)
    · exact .inr dropped
  · exact inUniques

/-- For every table with an index of its primary key ({name}`CatalogTable.primaryIndexed`):
{name}`CatalogTable.constraintKeys` has the primary key, marked as such.
Proof sketch: the definition inserts the primary key when it has an index. -/
theorem CatalogTable.mem_constraintKeys_of_primary {table : CatalogTable} (indexed : table.primaryIndexed = true) :
    ∃ replace, (table.primaryKey, replace, true) ∈ table.constraintKeys := by
  refine ⟨table.primaryKeyAlgorithm == some ConflictAlgorithm.replace, ?_⟩
  unfold CatalogTable.constraintKeys
  simp [indexed]

/-- For every catalog, position, table name and table, an index is in
{name}`Catalog.checkedIndexes` exactly when it is an index of a constraint
({name}`CatalogTable.constraintIndexes`) or of {lit}`CREATE UNIQUE INDEX`
({name}`Catalog.declaredIndexes`): the order moves indexes but adds or drops none.
Proof sketch: the two filters split the reversed list by the flag {lit}`replace`, and a reverse
keeps the members. -/
theorem Catalog.mem_checkedIndexes {catalog : Catalog} {position : Nat} {name : Identifier} {table : CatalogTable}
    {checked : CheckedIndex} :
    checked ∈ catalog.checkedIndexes position name table ↔
      checked ∈ table.constraintIndexes name ∨ checked ∈ catalog.declaredIndexes position := by
  unfold Catalog.checkedIndexes
  simp only [List.mem_append, List.mem_filter, List.mem_reverse]
  cases checked.replace <;> simp

/-- For every catalog, position and index of {name}`Catalog.declaredIndexes`: its key is the key
of a unique index on the table at the position, as {name}`Catalog.uniqueKeys` lists them.
Proof sketch: the catalog object that gives the index also gives its key. -/
theorem Catalog.key_of_declared {catalog : Catalog} {position : Nat} {checked : CheckedIndex}
    (member : checked ∈ catalog.declaredIndexes position) :
    checked.key ∈ catalog.filterMap fun object => match object.entry with
      | .index index => if index.table == position && index.unique then some index.uniqueKey else none
      | .table _ | .trigger _ => none := by
  obtain ⟨object, inCatalog, made⟩ := List.mem_filterMap.mp member
  refine List.mem_filterMap.mpr ⟨object, inCatalog, ?_⟩
  revert made
  cases object.entry with
  | index index =>
    cases chosen : (index.table == position && index.unique) <;> simp [chosen] <;> intro made <;> subst made <;> rfl
  | table _ | trigger _ => simp

/-- For every catalog, position and key of a unique index on the table at the position, as
{name}`Catalog.uniqueKeys` lists them: an index of {name}`Catalog.declaredIndexes` has the key.
Proof sketch: the catalog object that gives the key also gives an index with it. -/
theorem Catalog.declared_of_key {catalog : Catalog} {position : Nat} {key : UniqueKey}
    (member : key ∈ catalog.filterMap fun object => match object.entry with
      | .index index => if index.table == position && index.unique then some index.uniqueKey else none
      | .table _ | .trigger _ => none) :
    ∃ checked ∈ catalog.declaredIndexes position, checked.key = key := by
  obtain ⟨object, inCatalog, made⟩ := List.mem_filterMap.mp member
  revert made
  cases entry : object.entry with
  | index index =>
    cases chosen : (index.table == position && index.unique) <;> simp [chosen] <;> intro made <;> subst made
    exact ⟨{ name := object.name, key := index.uniqueKey, replace := false, ascendingTies := false },
      List.mem_filterMap.mpr ⟨object, inCatalog, by simp [entry, chosen]⟩, rfl⟩
  | table _ | trigger _ => simp

/-- For every catalog, position, table name, table and index of {name}`Catalog.checkedIndexes`:
the key of the index is in {name}`Catalog.uniqueKeys` of the table.
Proof sketch: an index of a constraint has a UNIQUE key or the primary key, which is not empty when
it has an index; a declared index has the key of its catalog object. -/
theorem Catalog.key_mem_uniqueKeys {catalog : Catalog} {position : Nat} {name : Identifier} {table : CatalogTable}
    {checked : CheckedIndex} (member : checked ∈ catalog.checkedIndexes position name table) :
    checked.key ∈ catalog.uniqueKeys position table := by
  unfold Catalog.uniqueKeys
  rcases Catalog.mem_checkedIndexes.mp member with constraint | declared
  · unfold CatalogTable.constraintIndexes at constraint
    obtain ⟨⟨⟨positions, replace, primary⟩, number⟩, inZip, made⟩ := List.mem_filterMap.mp constraint
    cases flag : (primary && table.withoutRowid)
    case true => simp [flag] at made
    case false =>
      simp only [flag] at made
      cases made
      refine List.mem_append_left _ (List.mem_map_of_mem ?_)
      rcases CatalogTable.of_mem_constraintKeys (List.fst_mem_of_mem_zipIdx inZip) with unique | ⟨_, isPrimary, indexed⟩
      · exact List.mem_append_right _ unique.2
      · simp only at isPrimary
        subst isPrimary
        unfold CatalogTable.primaryIndexed at indexed
        have nonempty : table.primaryKey.isEmpty = false := by
          cases empty : table.primaryKey.isEmpty <;> simp_all
        simp [nonempty]
  · exact List.mem_append_right _ (Catalog.key_of_declared declared)

/-- For every table, name and entry of {name}`CatalogTable.constraintKeys` that is not the
primary key of a {lit}`WITHOUT ROWID` table: an index of
{name}`CatalogTable.constraintIndexes` has the key of the entry.
Proof sketch: the entry has a number in the {lit}`zipIdx`, and the filter keeps it. -/
theorem CatalogTable.constraintIndex_of_entry {table : CatalogTable} {name : Identifier}
    {entry : List Nat × Bool × Bool} (member : entry ∈ table.constraintKeys) (kept : (entry.2.2 && table.withoutRowid) = false) :
    ∃ checked ∈ table.constraintIndexes name, checked.key = UniqueKey.ofColumns table.columns entry.1 := by
  obtain ⟨number, found⟩ := List.mem_iff_getElem?.mp member
  have inZip : (entry, number) ∈ table.constraintKeys.zipIdx := List.mem_zipIdx_iff_getElem?.mpr found
  let made : CheckedIndex :=
    { name := autoindexName name (number + 1), key := UniqueKey.ofColumns table.columns entry.1,
      replace := entry.2.1, ascendingTies := table.withoutRowid && table.primaryKeyDescending }
  refine ⟨made, List.mem_filterMap.mpr ⟨(entry, number), inZip, ?_⟩, rfl⟩
  obtain ⟨positions, replace, primary⟩ := entry
  simp only at kept ⊢
  simp [kept, made]

/-- For every catalog, position, table name and table whose primary key has an index
({name}`CatalogTable.primaryIndexed`) and that is not a {lit}`WITHOUT ROWID` table: an index of
{name}`Catalog.checkedIndexes` has the primary key.
Proof sketch: the primary key is an entry of {name}`CatalogTable.constraintKeys`, which a table with
a rowid keeps. -/
theorem Catalog.checked_of_primary {catalog : Catalog} {position : Nat} {name : Identifier} {table : CatalogTable}
    (indexed : table.primaryIndexed = true) (rowid : table.withoutRowid = false) :
    ∃ checked ∈ catalog.checkedIndexes position name table,
      checked.key = UniqueKey.ofColumns table.columns table.primaryKey := by
  obtain ⟨_, member⟩ := CatalogTable.mem_constraintKeys_of_primary indexed
  obtain ⟨checked, found, key⟩ := CatalogTable.constraintIndex_of_entry (name := name) member (by simp [rowid])
  exact ⟨checked, Catalog.mem_checkedIndexes.mpr (.inl found), key⟩

/-- For every catalog, position, table name, table and key of {name}`Catalog.uniqueKeys`: an
index of {name}`Catalog.checkedIndexes` has the key, or the key is the primary key, which is not
empty.
Proof sketch: a key of {name}`Catalog.uniqueKeys` is the primary key, a UNIQUE key, whose entry is
not marked as the primary key, or a declared index. -/
theorem Catalog.of_mem_uniqueKeys {catalog : Catalog} {position : Nat} {name : Identifier} {table : CatalogTable}
    {key : UniqueKey} (member : key ∈ catalog.uniqueKeys position table) :
    (∃ checked ∈ catalog.checkedIndexes position name table, checked.key = key) ∨
      (table.primaryKey ≠ [] ∧ key = UniqueKey.ofColumns table.columns table.primaryKey) := by
  unfold Catalog.uniqueKeys at member
  rcases List.mem_append.mp member with ofColumns | declared
  · obtain ⟨positions, found, rfl⟩ := List.mem_map.mp ofColumns
    rcases List.mem_append.mp found with primary | unique
    · split at primary
      · simp at primary
      · simp only [List.mem_singleton] at primary
        subst primary
        exact .inr ⟨by simp_all, rfl⟩
    · obtain ⟨_, entry⟩ := CatalogTable.mem_constraintKeys_of_unique unique
      obtain ⟨checked, inConstraints, key⟩ := CatalogTable.constraintIndex_of_entry (name := name) entry (by simp)
      exact .inl ⟨checked, Catalog.mem_checkedIndexes.mpr (.inl inConstraints), key⟩
  · obtain ⟨checked, inDeclared, key⟩ := Catalog.declared_of_key declared
    exact .inl ⟨checked, Catalog.mem_checkedIndexes.mpr (.inr inDeclared), key⟩

end Belay.Sqlite.Model
