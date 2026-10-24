import Belay.Sqlite.Model.CatalogValidAddColumn

set_option doc.verso true

/-! The validity of a catalog after ALTER TABLE ADD COLUMN (ADR 0022, D3, slice 4), second part:
the catalog with one object replaced by an object of the same name and kind keeps its lookups. -/

namespace Belay.Sqlite.Model

/-- For every catalog, position, object at the position and replacement with the same name and the
same kind (table or index, or trigger), and every name that {name}`Catalog.find` finds in the
catalog: the catalog with the replacement finds the same position, with the same object or the
replacement. Proof sketch: the first-match rule ({name}`FirstMatch`) tests only the name and the kind,
which the replacement keeps. -/
theorem Catalog.find_set {catalog : Catalog} {position : Nat} {object replacement : CatalogObject}
    (atPosition : catalog[position]? = some object) (name : replacement.name = object.name)
    (kind : replacement.isTrigger = object.isTrigger) {target : Identifier} {found : Nat × CatalogObject}
    (hfind : catalog.find target = some found) :
    ∃ other, Catalog.find (catalog.set position replacement) target = some (found.1, other) ∧
      (other = found.2 ∨ other = replacement) := by
  obtain ⟨place, thing⟩ := found
  unfold Catalog.find at hfind ⊢
  obtain ⟨atPlace, passes, before⟩ := (findPosition_eq_some_iff _ _ _ _).mp hfind
  have bound : position < catalog.length := (List.getElem?_eq_some_iff.mp atPosition).1
  have same : ((fun other : CatalogObject => other.name.sameName target && !other.isTrigger) replacement) =
      ((fun other : CatalogObject => other.name.sameName target && !other.isTrigger) object) := by
    simp [name, kind]
  by_cases here : place = position
  · subst here
    rw [atPosition] at atPlace
    cases atPlace
    refine ⟨replacement, (findPosition_eq_some_iff _ _ _ _).mpr ⟨List.getElem?_set_self bound, by simp_all, ?_⟩, .inr rfl⟩
    intro earlier less item found
    rw [List.getElem?_set_ne (by omega)] at found
    exact before earlier less item found
  · refine ⟨thing, (findPosition_eq_some_iff _ _ _ _).mpr ⟨by rwa [List.getElem?_set_ne (Ne.symm here)], passes, ?_⟩, .inl rfl⟩
    intro earlier less item found
    by_cases hit : earlier = position
    · subst hit
      rw [List.getElem?_set_self bound] at found
      cases found
      rw [same]
      exact before _ less object atPosition
    · rw [List.getElem?_set_ne (Ne.symm hit)] at found
      exact before earlier less item found

/-- For every catalog, position, object at the position and replacement that has the same name and
the same kind as the object and is a table: if the catalog finds a table with a name
({name}`Catalog.findTable`), the catalog with the replacement does too. Proof sketch: the same
position is found ({name}`Catalog.find_set`), and its object is the old table or the replacement. -/
theorem Catalog.findTable_isSome_set {catalog : Catalog} {position : Nat} {object replacement : CatalogObject}
    (atPosition : catalog[position]? = some object) (name : replacement.name = object.name)
    (kind : replacement.isTrigger = object.isTrigger) {table : CatalogTable}
    (isTable : replacement.entry = .table table) {target : Identifier}
    (found : (catalog.findTable target).isSome = true) :
    (Catalog.findTable (catalog.set position replacement) target).isSome = true := by
  unfold Catalog.findTable at found ⊢
  cases hfind : catalog.find target with
  | none => simp [hfind] at found
  | some pair =>
    obtain ⟨place, thing⟩ := pair
    obtain ⟨other, hother, choice⟩ := Catalog.find_set atPosition name kind hfind
    rw [hother]
    rcases choice with rfl | rfl
    · obtain ⟨_, entry⟩ := other
      cases entry <;> simp_all
    · obtain ⟨_, entry⟩ := other
      cases isTable
      simp

/-- For every valid catalog, position of a table, column and extended table: if the extended table is
supported, then the catalog after {name}`Catalog.addColumn` is valid. The object at the position
needs an ordinary name (not one of SQLite's own tables). Proof sketch: the names stay the same
({name}`CatalogStep.namesUnique`); an index on the table is supported for the larger width
({name}`CatalogIndex.supported_mono`), and a trigger still finds its table
({name}`Catalog.findTable_isSome_set`). -/
theorem Catalog.Valid.addColumn {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {position : Nat} {table : CatalogTable} (present : catalog.tableAt position = some table)
    (column : CatalogColumn) (ordinary : ∀ object, catalog[position]? = some object → reservedName object.name = false)
    (supported : ({ table with columns := table.columns ++ [column] } : CatalogTable).supported limits = true) :
    (catalog.addColumn position column).Valid limits := by
  have atPosition : ∃ name, catalog[position]? = some { name, entry := .table table } := by
    unfold Catalog.tableAt at present
    split at present <;> try contradiction
    rename_i _ name _ found
    cases present
    exact ⟨name, found⟩
  obtain ⟨name, atPosition⟩ := atPosition
  have bound : position < catalog.length := (List.getElem?_eq_some_iff.mp atPosition).1
  have result : catalog.addColumn position column =
      catalog.set position { name, entry := .table { table with columns := table.columns ++ [column] } } := by
    simp [Catalog.addColumn, atPosition]
  refine (Catalog.supported_iff limits _).mpr ⟨?_, ?_⟩
  · rw [result]
    exact (CatalogStep.replace position { name, entry := .table table }
      (.table { table with columns := table.columns ++ [column] }) atPosition rfl).namesUnique valid.namesUnique
  · intro object inside
    rw [result] at inside
    obtain ⟨index, atIndex⟩ := List.mem_iff_getElem?.mp inside
    by_cases here : index = position
    · subst here
      rw [List.getElem?_set_self bound] at atIndex
      cases atIndex
      have plain := ordinary _ atPosition
      simp [CatalogObject.supported, supported, plain]
    · rw [List.getElem?_set_ne (Ne.symm here)] at atIndex
      have old := valid.object (List.mem_of_getElem? atIndex)
      unfold CatalogObject.supported at old ⊢
      cases entry : object.entry with
      | table _ => simpa only [entry] using old
      | index found =>
        simp only [entry, Bool.and_eq_true] at old ⊢
        refine ⟨old.1, ?_⟩
        by_cases onTable : found.table = position
        · rw [onTable] at old ⊢
          rw [Catalog.tableAt_addColumn_same column present]
          rw [present] at old
          simp only [Option.any_some] at old ⊢
          exact CatalogIndex.supported_mono old.2 (by simp)
        · rw [Catalog.tableAt_addColumn_other catalog column onTable]
          exact old.2
      | trigger found =>
        simp only [entry, Bool.and_eq_true] at old ⊢
        refine ⟨old.1, ?_⟩
        rw [result]
        exact Catalog.findTable_isSome_set
          (replacement := { name, entry := .table { table with columns := table.columns ++ [column] } })
          atPosition rfl rfl rfl old.2

end Belay.Sqlite.Model
