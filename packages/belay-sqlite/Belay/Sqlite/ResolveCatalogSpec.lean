import Belay.Sqlite.ResolveSpec

set_option doc.verso true

/-! The unique-names rule of the catalog, and the theorems that resolution keeps it. -/

namespace Belay.Sqlite

/-- For every test and list, {name}`findPosition` finds nothing exactly when every
element fails the test. Proof sketch: induction on the list; a passing head is found
at position zero, and a failing head leaves the search to the tail. -/
theorem findPosition_eq_none_iff (test : α → Bool) (items : List α) :
    findPosition test items = none ↔ ∀ item ∈ items, test item = false := by
  induction items with
  | nil => simp [findPosition]
  | cons head rest ih =>
    by_cases passes : test head = true
    · simp [findPosition, passes]
    · simp [findPosition, passes, ih]

/-- For every catalog and name, {name}`Catalog.find` finds nothing exactly when the
folded name is not among the catalog's folded names. Proof sketch: rewrite with
{name}`findPosition_eq_none_iff`; the folded-name test fails for every object exactly
when the folded name is not in the mapped list. -/
theorem Catalog.find_eq_none_iff (catalog : Catalog) (name : String) :
    catalog.find name = none ↔ normalizeIdentifier name ∉ catalog.foldedNames := by
  rw [Catalog.find, findPosition_eq_none_iff]
  simp only [Catalog.foldedNames, List.mem_map, not_exists, not_and, beq_eq_false_iff_ne, ne_eq]

/-- For every catalog, name, position and table entry that {name}`Catalog.findTable`
returns, the catalog has an object at that position with the table entry, whose
folded name is the folded given name. Proof sketch: the result comes from
{name}`Catalog.find`, and {name}`findPosition_eq_some_iff` gives the object at the
position and its passing name test. -/
theorem Catalog.findTable_some (catalog : Catalog) (name : String) (position : Nat) (table : CatalogTable)
    (found : catalog.findTable name = some (position, table)) :
    ∃ object, catalog[position]? = some object ∧ object.entry = .table table ∧
      normalizeIdentifier object.name = normalizeIdentifier name := by
  unfold Catalog.findTable at found
  split at found <;> try contradiction
  rename_i object_position object_name hfind
  cases found
  have ⟨at_, test, _⟩ := (findPosition_eq_some_iff _ _ _ _).mp hfind
  exact ⟨_, at_, rfl, by simpa using test⟩

/-- How one statement may change the catalog. The catalog is the same; or one object
is appended whose name {name}`Catalog.find` does not find; or the object at a
position is replaced by one with the same name. -/
inductive CatalogStep (catalog : Catalog) : Catalog → Prop where
  /-- The catalog does not change. -/
  | same : CatalogStep catalog catalog
  /-- One object with an unused name is appended. -/
  | append (object : CatalogObject) (unused : catalog.find object.name = none) :
      CatalogStep catalog (catalog ++ [object])
  /-- The object at a position gets another entry and keeps its name. -/
  | replace (position : Nat) (object : CatalogObject) (entry : CatalogEntry)
      (at_ : catalog[position]? = some object) :
      CatalogStep catalog (catalog.set position { name := object.name, entry := entry })

/-- For all catalogs related by {name}`CatalogStep`, unique folded names before give
unique folded names after. Proof sketch: an unchanged catalog keeps its names; an
appended object has a folded name outside the list, by
{name}`Catalog.find_eq_none_iff`; a replaced object keeps its name, so the list of
folded names is the same. -/
theorem CatalogStep.namesUnique (step : CatalogStep catalog after) (unique : catalog.NamesUnique) :
    after.NamesUnique := by
  cases step with
  | same => exact unique
  | append object unused =>
    have absent := (Catalog.find_eq_none_iff _ _).mp unused
    simp only [Catalog.NamesUnique, Catalog.foldedNames, List.map_append, List.map_cons, List.map_nil] at *
    exact List.nodup_append.mpr ⟨unique, by simp, by simpa [Catalog.foldedNames] using absent⟩
  | replace position object entry at_ =>
    have names : Catalog.foldedNames (catalog.set position { name := object.name, entry := entry }) =
        catalog.foldedNames := by
      unfold Catalog.foldedNames
      apply List.ext_getElem?
      intro index
      simp only [List.getElem?_map, List.getElem?_set]
      by_cases same : position = index
      · subst same
        obtain ⟨bound, value⟩ := List.getElem?_eq_some_iff.mp at_
        simp [bound, value]
      · simp [same]
    simpa [Catalog.NamesUnique, names] using unique

end Belay.Sqlite
