import Belay.Sqlite.Model.CatalogValidLaws
import Belay.Sqlite.Model.KeysUniqueDrop

set_option doc.verso true

/-! The validity of a catalog after DROP (ADR 0022, D3, slice 4). A drop keeps a valid catalog
valid when it keeps the table of every index and of every trigger that it keeps. -/

namespace Belay.Sqlite.Model

/-- The condition of DROP for the given catalog and positions, for the validity of the catalog after
the drop:
* for every index at a position that the drop keeps, the position of its table
  ({name}`CatalogIndex.table`) is not in the list of positions;
* for every trigger at a position that the drop keeps, if {name}`Catalog.findTable` finds the table of
  the trigger by its name, the position that it finds is not in the list of positions.

The condition does not require that the position of an index names a table, or that a table is
found: a valid catalog gives both. Objects that the drop removes require nothing. {name}`Catalog.DropCondition` is the first
condition for unique indexes only. -/
def Catalog.DropClosed (catalog : Catalog) (positions : List Nat) : Prop :=
  (∀ place object index, catalog[place]? = some object → object.entry = .index index → place ∉ positions →
    index.table ∉ positions) ∧
  (∀ place object trigger, catalog[place]? = some object → object.entry = .trigger trigger → place ∉ positions →
    ∀ found table, catalog.findTable trigger.table = some (found, table) → found ∉ positions)

/-- For every catalog and positions, {name}`Catalog.DropClosed` gives {name}`Catalog.DropCondition`:
the first condition is the second for the indexes that are unique. Proof sketch: the definitions. -/
theorem Catalog.DropClosed.dropCondition {catalog : Catalog} {positions : List Nat}
    (closed : catalog.DropClosed positions) : catalog.DropCondition positions :=
  fun place object index atPlace entry _ kept => closed.1 place object index atPlace entry kept

/-- For every catalog, positions and kind of entry, {name}`CatalogEntry.afterDrop` keeps the kind of
the entry. Proof sketch: case analysis of the entry. -/
theorem CatalogEntry.afterDrop_isTrigger (positions : List Nat) (entry : CatalogEntry) :
    (entry.afterDrop positions).isTrigger = entry.isTrigger := by
  cases entry <;> rfl

/-- For every catalog, positions and position that the drop keeps, the table at the new position
({name}`keptBelow`) of the catalog after {name}`Catalog.drop` is the table at the position of the
catalog. Proof sketch: the kept objects have the object of the position at the new position
({name}`getElem?_keptAfterDrop`), and a table does not change. -/
theorem Catalog.tableAt_drop {catalog : Catalog} {positions : List Nat} {position : Nat}
    (kept : !positions.contains position) :
    (catalog.drop positions).tableAt (keptBelow positions position) = catalog.tableAt position := by
  unfold Catalog.tableAt
  rw [Catalog.drop_eq_keptAfterDrop, List.getElem?_map, getElem?_keptAfterDrop positions catalog kept]
  cases catalog[position]? with
  | none => rfl
  | some object =>
    obtain ⟨name, entry⟩ := object
    cases entry <;> rfl

/-- For every catalog, positions, name, table and position: if {name}`Catalog.findTable` finds the
table at a position that the drop keeps, the catalog after {name}`Catalog.drop` finds a table with the
name ({name}`Catalog.findTable` gives a result). The formula does not say where. Proof sketch: the first-match rule ({name}`FirstMatch`) holds for the
kept object at the new position: the kept objects before it come from earlier positions of the
catalog, and none of them has the name. -/
theorem Catalog.findTable_isSome_drop {catalog : Catalog} {positions : List Nat} {target : Identifier}
    {found : Nat} {table : CatalogTable} (hfind : catalog.findTable target = some (found, table))
    (kept : !positions.contains found) : ((catalog.drop positions).findTable target).isSome = true := by
  unfold Catalog.findTable at hfind ⊢
  cases hf : catalog.find target with
  | none => simp [hf] at hfind
  | some pair =>
    obtain ⟨place, thing⟩ := pair
    obtain ⟨name, entry⟩ := thing
    cases entry with
    | index _ | trigger _ => simp [hf] at hfind
    | table shape =>
      simp only [hf, Option.some.injEq, Prod.mk.injEq] at hfind
      obtain ⟨rfl, -⟩ := hfind
      unfold Catalog.find at hf
      obtain ⟨atPlace, passes, before⟩ := (findPosition_eq_some_iff _ _ _ _).mp hf
      have location : (catalog.drop positions).find target =
          some (keptBelow positions place, { name, entry := .table shape }) := by
        unfold Catalog.find
        refine (findPosition_eq_some_iff _ _ _ _).mpr ⟨?_, passes, ?_⟩
        · rw [Catalog.drop_eq_keptAfterDrop, List.getElem?_map, getElem?_keptAfterDrop positions catalog kept, atPlace]
          rfl
        · intro earlier less item atEarlier
          rw [Catalog.drop_eq_keptAfterDrop, List.getElem?_map] at atEarlier
          cases keptAt : (keptAfterDrop positions catalog)[earlier]? with
          | none => simp [keptAt] at atEarlier
          | some original =>
            simp only [keptAt, Option.map_some, Option.some.injEq] at atEarlier
            subst atEarlier
            have inside : earlier < (keptAfterDrop positions catalog).length := (List.getElem?_eq_some_iff.mp keptAt).1
            obtain ⟨old, oldKept, rfl⟩ := exists_keptBelow positions catalog inside
            rw [getElem?_keptAfterDrop positions catalog oldKept] at keptAt
            have earlierOld : old < place := by
              refine Nat.lt_of_not_le fun later => ?_
              have := (keptBelow_le positions later).1
              omega
            have old := before old earlierOld original keptAt
            simpa only [CatalogObject.isTrigger, CatalogEntry.afterDrop_isTrigger] using old
      simp [location]

/-- For every valid catalog and positions that meet {name}`Catalog.DropClosed`, the catalog after
{name}`Catalog.drop` is valid. Proof sketch: the folded names stay unique
({name}`Catalog.NamesUnique.drop`); a kept table does not change; a kept index is supported for the
same table, which has a new position ({name}`Catalog.tableAt_drop`); and a kept trigger still finds
its table ({name}`Catalog.findTable_isSome_drop`). -/
theorem Catalog.Valid.drop {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {positions : List Nat} (closed : catalog.DropClosed positions) : (catalog.drop positions).Valid limits := by
  refine (Catalog.supported_iff limits _).mpr ⟨valid.namesUnique.drop positions, ?_⟩
  intro object inside
  rw [Catalog.drop_eq_keptAfterDrop] at inside
  obtain ⟨original, kept, rfl⟩ := List.mem_map.mp inside
  obtain ⟨place, placeKept, atPlace⟩ := mem_keptAfterDrop kept
  have old := valid.object (List.mem_of_getElem? atPlace)
  unfold CatalogObject.supported at old ⊢
  obtain ⟨name, entry⟩ := original
  cases entry with
  | table _ => simpa [CatalogEntry.afterDrop] using old
  | index found =>
    simp only [CatalogEntry.afterDrop, Bool.and_eq_true] at old ⊢
    refine ⟨old.1, ?_⟩
    have tableKept : !positions.contains found.table := by
      simpa using closed.1 place _ found atPlace rfl (by simpa using placeKept)
    rw [Catalog.tableAt_drop tableKept]
    exact old.2
  | trigger found =>
    simp only [CatalogEntry.afterDrop, Bool.and_eq_true] at old ⊢
    refine ⟨old.1, ?_⟩
    cases hfind : catalog.findTable found.table with
    | none => simp [hfind] at old
    | some pair =>
      obtain ⟨location, table⟩ := pair
      exact Catalog.findTable_isSome_drop hfind (by
        simpa using closed.2 place _ found atPlace rfl (by simpa using placeKept) location table hfind)

/-- For every catalog, {name}`Catalog.DropClosed` holds for the empty list of positions: the drop of
nothing keeps every table of every index and trigger. Proof sketch: no position is in the empty
list. -/
theorem Catalog.DropClosed.nil (catalog : Catalog) : catalog.DropClosed [] :=
  ⟨fun _ _ _ _ _ _ => List.not_mem_nil, fun _ _ _ _ _ _ _ _ _ => List.not_mem_nil⟩

end Belay.Sqlite.Model
