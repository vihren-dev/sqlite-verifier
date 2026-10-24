import Belay.Sqlite.Model.ModelLaws
import Belay.Sqlite.Model.Resolution.CatalogSpec

set_option doc.verso true

/-! Laws of {lit}`Catalog.Valid` that the resolver facts of slice 4 use (ADR 0022, D3): the
validity of a catalog as a statement about its names and its objects, and the validity of a
catalog with one object appended. -/

namespace Belay.Sqlite.Model

/-- For every list: the list that {lit}`List.eraseDups` gives is not
longer than the list, and it has the length of the list exactly when the list has no duplicate.
Proof sketch: strong induction on the length. The head stays; the tail loses the elements equal to
the head, which leaves a list that is shorter than the tail, or equal to it exactly when the head
is not in the tail. -/
theorem length_eraseDups_iff {α : Type} [BEq α] [LawfulBEq α] :
    ∀ (size : Nat) (items : List α), items.length = size →
      items.eraseDups.length ≤ items.length ∧ (items.eraseDups.length = items.length ↔ items.Nodup) := by
  intro size
  induction size using Nat.strongRecOn with
  | _ size ih =>
    intro items hsize
    cases items with
    | nil => simp
    | cons head tail =>
      have smaller : (tail.filter fun item => !item == head).length < size := by
        have := List.length_filter_le (fun item => !item == head) tail
        simp only [List.length_cons] at hsize
        omega
      obtain ⟨le, iff⟩ := ih _ smaller _ rfl
      have bound := List.length_filter_le (fun item => !item == head) tail
      rw [List.eraseDups_cons]
      simp only [List.length_cons]
      refine ⟨by omega, ?_⟩
      constructor
      · intro equal
        have whole : (tail.filter fun item => !item == head).length = tail.length := by omega
        have all := List.length_filter_eq_length_iff.mp whole
        have same : (tail.filter fun item => !item == head) = tail := List.filter_eq_self.mpr all
        have free : tail.Nodup := by
          have := iff.mp (by omega)
          rwa [same] at this
        refine List.nodup_cons.mpr ⟨fun inside => ?_, free⟩
        have := all head inside
        simp at this
      · intro nodup
        obtain ⟨absent, free⟩ := List.nodup_cons.mp nodup
        have same : (tail.filter fun item => !item == head) = tail :=
          List.filter_eq_self.mpr fun item inside => by
            simp only [Bool.not_eq_true', beq_eq_false_iff_ne, ne_eq]
            exact fun equal => absent (equal ▸ inside)
        have equal := iff.mpr (by rwa [same])
        have lengths : (tail.filter fun item => !item == head).length = tail.length := by rw [same]
        omega

/-- For every catalog, the number of folded names is the number of tables and indexes. Proof sketch:
{lit}`List.map` keeps the length. -/
theorem Catalog.length_foldedNames (catalog : Catalog) :
    catalog.foldedNames.length = (catalog.filter (!·.isTrigger)).length := by
  simp [Catalog.foldedNames]

/-- For every limits and catalog, {name}`Catalog.supported` holds exactly when the folded names of
the catalog are unique ({name}`Catalog.NamesUnique`) and every object is supported under the
catalog ({name}`CatalogObject.supported`). Proof sketch: the number of names without duplicates
equals the number of names exactly when there is no duplicate ({name}`length_eraseDups_iff`). -/
theorem Catalog.supported_iff (limits : Limits) (catalog : Catalog) :
    catalog.supported limits = true ↔
      catalog.NamesUnique ∧ ∀ object ∈ catalog, object.supported limits catalog = true := by
  unfold Catalog.supported Catalog.NamesUnique
  simp only [Bool.and_eq_true, beq_iff_eq, List.all_eq_true]
  rw [← Catalog.length_foldedNames]
  exact and_congr_left' (length_eraseDups_iff _ _ rfl).2

/-- For every limits, catalog, object of the catalog and valid catalog: the object is supported.
Proof sketch: the second part of {name}`Catalog.supported_iff`. -/
theorem Catalog.Valid.object {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {object : CatalogObject} (member : object ∈ catalog) : object.supported limits catalog = true :=
  ((Catalog.supported_iff limits catalog).mp valid).2 object member

/-- For every valid catalog, the folded names of its tables and indexes are unique. Proof sketch: the
first part of {name}`Catalog.supported_iff`. -/
theorem Catalog.Valid.namesUnique {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits) :
    catalog.NamesUnique :=
  ((Catalog.supported_iff limits catalog).mp valid).1

/-- For every valid catalog, position and table at the position, the table is supported under the
limits. Proof sketch: the object at the position is a catalog object, and a table object is supported
only when its table is. -/
theorem Catalog.Valid.tableSupported {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {position : Nat} {table : CatalogTable} (present : catalog.tableAt position = some table) :
    table.supported limits = true := by
  unfold Catalog.tableAt at present
  split at present <;> try contradiction
  rename_i object name atPosition
  cases present
  have supported := valid.object (List.mem_of_getElem? atPosition)
  simp only [CatalogObject.supported, Bool.and_eq_true] at supported
  exact supported.1

/-- For every catalog, extension and position of a table in the catalog, the catalog with the
extension appended has the same table at the position. Proof sketch: a position below the length
reads the same object in the longer list ({lit}`List.getElem?_append_left`). -/
theorem Catalog.tableAt_append_of_some {catalog : Catalog} (extension : Catalog) {position : Nat}
    {table : CatalogTable} (present : catalog.tableAt position = some table) :
    (catalog ++ extension).tableAt position = some table := by
  unfold Catalog.tableAt at present ⊢
  cases found : catalog[position]? with
  | none => simp [found] at present
  | some object =>
    have bound := (List.getElem?_eq_some_iff.mp found).1
    rw [List.getElem?_append_left bound, found]
    simpa [found] using present

/-- For every catalog, extension, name and table found by {name}`Catalog.findTable`, the catalog
with the extension appended finds the same table. Proof sketch: {name}`findPosition_append`. -/
theorem Catalog.findTable_append_of_some {catalog : Catalog} (extension : Catalog) {name : Identifier}
    {found : Nat × CatalogTable} (present : catalog.findTable name = some found) :
    (catalog ++ extension).findTable name = some found := by
  unfold Catalog.findTable Catalog.find at present ⊢
  cases hfind : findPosition (fun object => object.name.sameName name && !object.isTrigger) catalog with
  | none => simp [hfind] at present
  | some pair =>
    rw [findPosition_append extension hfind]
    simpa [hfind] using present

/-- For every limits, catalog, extension and object that is supported under the catalog, the
object is supported under the catalog with the extension appended. Proof sketch: a table does not read
the catalog, and the table of an index and of a trigger keeps its position and its name
({lit}`Catalog.tableAt_append_of_some`, {lit}`Catalog.findTable_append_of_some`). -/
theorem CatalogObject.supported_append {limits : Limits} {catalog : Catalog} {object : CatalogObject}
    (supported : object.supported limits catalog = true) (extension : Catalog) :
    object.supported limits (catalog ++ extension) = true := by
  unfold CatalogObject.supported at supported ⊢
  cases entry : object.entry with
  | table table => simpa only [entry] using supported
  | index index =>
    simp only [entry, Bool.and_eq_true] at supported ⊢
    refine ⟨supported.1, ?_⟩
    cases found : catalog.tableAt index.table with
    | none => simp [found] at supported
    | some table =>
      rw [Catalog.tableAt_append_of_some extension found]
      simpa [found] using supported.2
  | trigger trigger =>
    simp only [entry, Bool.and_eq_true] at supported ⊢
    refine ⟨supported.1, ?_⟩
    cases found : catalog.findTable trigger.table with
    | none => simp [found] at supported
    | some pair => simp [Catalog.findTable_append_of_some extension found]

/-- For every valid catalog and object: if the object is a trigger or has a name that the catalog
does not find, and it is supported under the catalog with the object appended, then the catalog
with the object appended is valid. This is the law of CREATE TABLE, CREATE INDEX and CREATE
TRIGGER. Proof sketch: the folded names stay unique ({name}`CatalogStep.namesUnique`), and every
old object stays supported ({name}`CatalogObject.supported_append`). -/
theorem Catalog.Valid.append {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    (object : CatalogObject) (fresh : object.isTrigger = false → catalog.find object.name = none)
    (supported : object.supported limits (catalog ++ [object]) = true) :
    (catalog ++ [object]).Valid limits := by
  refine (Catalog.supported_iff limits _).mpr ⟨?_, ?_⟩
  · cases kind : object.isTrigger
    · exact (CatalogStep.append object (fresh kind)).namesUnique valid.namesUnique
    · exact (CatalogStep.appendTrigger object kind).namesUnique valid.namesUnique
  · intro object' inside
    rcases List.mem_append.mp inside with old | new
    · exact CatalogObject.supported_append (valid.object old) [object]
    · rw [List.mem_singleton.mp new]
      exact supported

end Belay.Sqlite.Model
