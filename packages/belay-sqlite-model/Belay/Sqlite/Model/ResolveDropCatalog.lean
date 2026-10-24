import Belay.Sqlite.Model.ResolveCreateTriggerCatalog
import Belay.Sqlite.Model.CatalogValidDrop
import Belay.Sqlite.Model.Resolution.Drops

set_option doc.verso true

/-! The positions of a DROP (ADR 0022, D3, slice 4): the positions that {lit}`Catalog.tableObjects` gives
for a table, and the position of an index or a trigger alone, meet {lit}`Catalog.DropClosed`. The
lemmas here tell which objects the list of {lit}`Catalog.tableObjects` holds. -/

namespace Belay.Sqlite.Model

/-- For every catalog, table position, place, object and index: if the object at the place is an
index of the table at the position, the place is in {name}`Catalog.tableObjects` of the position.
Proof sketch: the place is in the filtered list of numbered objects, and the filter keeps the index. -/
theorem Catalog.mem_tableObjects_index {catalog : Catalog} {position place : Nat} {object : CatalogObject}
    {found : CatalogIndex} (atPlace : catalog[place]? = some object) (entry : object.entry = .index found)
    (same : found.table = position) : place ∈ catalog.tableObjects position := by
  unfold Catalog.tableObjects
  refine List.mem_cons_of_mem _ (List.mem_filterMap.mpr ⟨(object, place),
    List.mem_zipIdx_iff_getElem?.mpr atPlace, ?_⟩)
  simp [entry, same]

/-- For every catalog, table position, place, object and trigger: if the object at the place is a
trigger whose table has the same name as the object at the position, the place is in
{name}`Catalog.tableObjects` of the position. Proof sketch: the place is in the filtered list of numbered
objects, and the filter keeps the trigger. -/
theorem Catalog.mem_tableObjects_trigger {catalog : Catalog} {position place : Nat} {object owner : CatalogObject}
    {found : CatalogTrigger} (atPlace : catalog[place]? = some object) (entry : object.entry = .trigger found)
    (atPosition : catalog[position]? = some owner) (same : found.table.sameName owner.name = true) :
    place ∈ catalog.tableObjects position := by
  unfold Catalog.tableObjects
  refine List.mem_cons_of_mem _ (List.mem_filterMap.mpr ⟨(object, place),
    List.mem_zipIdx_iff_getElem?.mpr atPlace, ?_⟩)
  simp [entry, atPosition, same]

/-- For every catalog, table position and place in {name}`Catalog.tableObjects` of the position:
the place is the position, or every object of the catalog at the place has an entry that is no
table. Proof sketch: a place other than the first comes from the filtered list, and the filter
keeps no table. -/
theorem Catalog.entry_of_mem_tableObjects {catalog : Catalog} {position place : Nat}
    (member : place ∈ catalog.tableObjects position) :
    place = position ∨ ∀ object table, catalog[place]? = some object → object.entry ≠ .table table := by
  unfold Catalog.tableObjects at member
  rcases List.mem_cons.mp member with same | later
  · exact Or.inl same
  · right
    intro object table atPlace entry
    obtain ⟨⟨original, index⟩, inside, kept⟩ := List.mem_filterMap.mp later
    have located := List.mem_zipIdx_iff_getElem?.mp inside
    simp only at located
    cases kept' : original.entry with
    | table _ => simp [kept'] at kept
    | index found =>
      simp only [kept'] at kept
      split at kept <;> try (cases kept; done)
      cases kept
      rw [atPlace] at located
      cases located
      simp [kept'] at entry
    | trigger found =>
      simp only [kept'] at kept
      split at kept <;> try (cases kept; done)
      cases kept
      rw [atPlace] at located
      cases located
      simp [kept'] at entry

/-- For every valid catalog, place and index at the place: the object at the position of the table of the
index is a table. Proof sketch: a valid catalog supports its index, and the support of an index
requires a table at the position ({name}`Catalog.tableAt`). -/
theorem Catalog.Valid.indexTable {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {place : Nat} {object : CatalogObject} {found : CatalogIndex} (atPlace : catalog[place]? = some object)
    (entry : object.entry = .index found) :
    ∃ owner table, catalog[found.table]? = some owner ∧ owner.entry = .table table := by
  have supported := valid.object (List.mem_of_getElem? atPlace)
  simp only [CatalogObject.supported, entry, Bool.and_eq_true] at supported
  unfold Catalog.tableAt at supported
  cases owner : catalog[found.table]? with
  | none => simp [owner] at supported
  | some owner' =>
    obtain ⟨ownerName, ownerEntry⟩ := owner'
    cases ownerEntry with
    | table table => exact ⟨_, table, rfl, rfl⟩
    | index _ => simp [owner] at supported
    | trigger _ => simp [owner] at supported

/-- For every valid catalog, name and table that {name}`Catalog.findTable` finds at a position:
the positions of {name}`Catalog.tableObjects` meet {name}`Catalog.DropClosed`. Proof sketch: the
table of a kept index and the table of a kept trigger are tables. The list holds the position
of the dropped table and positions of indexes and triggers, so these tables are not in it
({name}`Catalog.mem_tableObjects_index`, {name}`Catalog.mem_tableObjects_trigger`,
{name}`Catalog.entry_of_mem_tableObjects`). -/
theorem Catalog.DropClosed.table {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {name : Identifier} {position : Nat} {table : CatalogTable}
    (found : catalog.findTable name = some (position, table)) :
    catalog.DropClosed (catalog.tableObjects position) := by
  refine ⟨fun place object index atPlace entry notIn member => ?_,
    fun place object trigger atPlace entry notIn target owner hfind member => ?_⟩
  · obtain ⟨_, _, atTable, tableEntry⟩ := valid.indexTable atPlace entry
    rcases Catalog.entry_of_mem_tableObjects member with same | other
    · exact notIn (Catalog.mem_tableObjects_index atPlace entry same)
    · exact other _ _ atTable tableEntry
  · obtain ⟨object', atTarget, targetEntry, folded⟩ := Catalog.findTable_some catalog _ target owner hfind
    rcases Catalog.entry_of_mem_tableObjects member with same | other
    · subst same
      exact notIn (Catalog.mem_tableObjects_trigger atPlace entry atTarget
        (by simp [Identifier.sameName, folded]))
    · exact other _ _ atTarget targetEntry

/-- For every valid catalog, position and object at the position whose entry is not a table: the
list of the position alone meets {name}`Catalog.DropClosed`. Proof sketch: the table of a kept index and
the table of a kept trigger are tables, and the position holds no table. -/
theorem Catalog.DropClosed.single {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {position : Nat} {object : CatalogObject} (atPosition : catalog[position]? = some object)
    (notTable : ∀ table, object.entry ≠ .table table) : catalog.DropClosed [position] := by
  refine ⟨fun place other index atPlace entry _ member => ?_,
    fun place other trigger atPlace entry _ target owner hfind member => ?_⟩
  · obtain ⟨_, _, atTable, tableEntry⟩ := valid.indexTable atPlace entry
    rw [List.mem_singleton.mp member, atPosition] at atTable
    cases atTable
    exact notTable _ tableEntry
  · obtain ⟨found, atTarget, targetEntry, _⟩ := Catalog.findTable_some catalog _ target owner hfind
    rw [List.mem_singleton.mp member, atPosition] at atTarget
    cases atTarget
    exact notTable _ targetEntry

end Belay.Sqlite.Model
