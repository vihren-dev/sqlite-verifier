import Belay.Sqlite.Model.Resolution.CatalogDrop
import Belay.Sqlite.Model.Database

set_option doc.verso true

/-! The positions of the objects that a drop keeps (ADR 0014, D7): a drop keeps the elements of a
list at the positions that it does not drop, in order, and the kept element at an old position is
at its new position {lit}`keptBelow` after the drop. {lit}`KeysUniqueDrop` uses these laws for the
catalog and the row lists of a database. -/

namespace Belay.Sqlite.Model

/-- The elements of the list at the positions that are not in the given positions, in order: the
list that {lit}`Database.drop` and {lit}`Catalog.drop` keep. For example,
{lean}`keptAfterDrop [1] ["a", "b", "c"] = ["a", "c"]`. -/
def keptAfterDrop {α} (positions : List Nat) (list : List α) : List α :=
  (list.zipIdx.filter fun (_, position) => !positions.contains position).map Prod.fst

/-- Induction on a list from its end: a property of the empty list that holds for a list with an
element appended whenever it holds for the list holds for every list. Proof sketch: induction on
the reversed list. -/
theorem appendInduction {α} {motive : List α → Prop} (nil : motive [])
    (append : ∀ list element, motive list → motive (list ++ [element])) : ∀ list, motive list := by
  intro list
  rw [← List.reverse_reverse list]
  induction list.reverse with
  | nil => exact nil
  | cons element rest ih => simpa using append rest.reverse element ih

/-- For every list of positions, list and element: the kept elements of the list with the element
appended are the kept elements of the list, followed by the element when the drop keeps its
position, the length of the list. Proof sketch: {lit}`List.zipIdx` of the appended list ends
with the element at the length of the list. -/
theorem keptAfterDrop_append {α} (positions : List Nat) (list : List α) (element : α) :
    keptAfterDrop positions (list ++ [element]) =
      keptAfterDrop positions list ++ if positions.contains list.length then [] else [element] := by
  unfold keptAfterDrop
  rw [List.zipIdx_append, List.filter_append, List.map_append]
  by_cases dropped : list.length ∈ positions <;> simp [dropped]

/-- For every list of positions and position, {name}`keptBelow` of the next position adds one
when the drop keeps the position. Proof sketch: {lit}`List.range` of the next position ends with
the position. -/
theorem keptBelow_succ (positions : List Nat) (position : Nat) :
    keptBelow positions (position + 1) = keptBelow positions position + if positions.contains position then 0 else 1 := by
  unfold keptBelow
  rw [List.range_succ, List.filter_append, List.length_append]
  by_cases dropped : position ∈ positions <;> simp [dropped]

/-- For every list of positions and two positions: {name}`keptBelow` does not decrease, and it
increases from a position that the drop keeps to every later position. Proof sketch: induction on
the distance with {name}`keptBelow_succ`. -/
theorem keptBelow_le (positions : List Nat) {first second : Nat} (le : first ≤ second) :
    keptBelow positions first ≤ keptBelow positions second ∧
      (first < second → !positions.contains first → keptBelow positions first < keptBelow positions second) := by
  obtain ⟨distance, rfl⟩ := Nat.exists_eq_add_of_le le
  induction distance with
  | zero => exact ⟨Nat.le_refl _, fun less => absurd less (Nat.lt_irrefl _)⟩
  | succ distance ih =>
    have earlier := ih (Nat.le_add_right _ _)
    rw [← Nat.add_assoc, keptBelow_succ]
    refine ⟨Nat.le_trans earlier.1 (Nat.le_add_right _ _), fun _ kept => ?_⟩
    cases distance with
    | zero =>
      have out : first ∉ positions := by simpa using kept
      simp [out]
    | succ distance => exact Nat.lt_of_lt_of_le (earlier.2 (by omega) kept) (Nat.le_add_right _ _)

/-- For every list of positions and two positions that the drop keeps: if {name}`keptBelow` gives
them the same new position, they are equal. Proof sketch: the earlier of two different kept
positions has a smaller new position ({name}`keptBelow_le`). -/
theorem keptBelow_injective (positions : List Nat) {first second : Nat} (firstKept : !positions.contains first)
    (secondKept : !positions.contains second) (same : keptBelow positions first = keptBelow positions second) :
    first = second := by
  rcases Nat.lt_trichotomy first second with less | equal | greater
  · exact absurd same (Nat.ne_of_lt ((keptBelow_le positions (Nat.le_of_lt less)).2 less firstKept))
  · exact equal
  · exact absurd same.symm (Nat.ne_of_lt ((keptBelow_le positions (Nat.le_of_lt greater)).2 greater secondKept))

/-- For every list of positions and list, the number of kept elements is {name}`keptBelow` of the
length of the list. Proof sketch: induction from the end of the list with
{name}`keptAfterDrop_append` and {name}`keptBelow_succ`. -/
theorem length_keptAfterDrop {α} (positions : List Nat) (list : List α) :
    (keptAfterDrop positions list).length = keptBelow positions list.length := by
  induction list using appendInduction with
  | nil => rfl
  | append list element ih =>
    rw [keptAfterDrop_append, List.length_append, ih, List.length_append, List.length_singleton, keptBelow_succ]
    by_cases dropped : list.length ∈ positions <;> simp [dropped]

/-- For every list of positions, list and position that the drop keeps: the kept elements have,
at the new position of the position ({name}`keptBelow`), the element of the list at the
position, or none for both when the position is past the end. Proof sketch: induction from the
end of the list; a position below the old length is in the old kept elements, the last
position is the appended element, and a later position is past the end on both sides. -/
theorem getElem?_keptAfterDrop {α} (positions : List Nat) (list : List α) {position : Nat}
    (kept : !positions.contains position) :
    (keptAfterDrop positions list)[keptBelow positions position]? = list[position]? := by
  induction list using appendInduction with
  | nil => simp [keptAfterDrop]
  | append list element ih =>
    have lengths := length_keptAfterDrop positions list
    rw [keptAfterDrop_append]
    rcases Nat.lt_trichotomy position list.length with below | same | beyond
    · have inside : keptBelow positions position < (keptAfterDrop positions list).length :=
        lengths ▸ (keptBelow_le positions (Nat.le_of_lt below)).2 below kept
      rw [List.getElem?_append_left inside, ih, List.getElem?_append_left below]
    · subst same
      have out : list.length ∉ positions := by simpa using kept
      simp [out, ← lengths]
    · have outside : (keptAfterDrop positions list ++ if positions.contains list.length then [] else [element]).length ≤
          keptBelow positions position := by
        have step := keptBelow_succ positions list.length
        have mono := (keptBelow_le positions (show list.length + 1 ≤ position by omega)).1
        rw [List.length_append, lengths]
        by_cases dropped : list.length ∈ positions <;> simp [dropped] at step ⊢ <;> omega
      rw [List.getElem?_eq_none outside, List.getElem?_eq_none (by simp; omega)]

/-- For every list of positions, list and position below the number of kept elements: some
old position that the drop keeps has that new position ({name}`keptBelow`). Proof sketch:
induction from the end of the list; the new last position is the old last position. -/
theorem exists_keptBelow {α} (positions : List Nat) (list : List α) {position : Nat}
    (below : position < (keptAfterDrop positions list).length) :
    ∃ old, !positions.contains old ∧ keptBelow positions old = position := by
  induction list using appendInduction with
  | nil => simp [keptAfterDrop] at below
  | append list element ih =>
    rw [keptAfterDrop_append, List.length_append] at below
    by_cases earlier : position < (keptAfterDrop positions list).length
    · exact ih earlier
    · by_cases dropped : list.length ∈ positions
      · simp [dropped] at below
        omega
      · refine ⟨list.length, by simpa using dropped, ?_⟩
        simp [dropped] at below
        rw [← length_keptAfterDrop]
        omega

/-- For every list of positions, list and element of the kept elements: the element is in the
list at a position that the drop keeps. Proof sketch: the kept elements come from the pairs of
{lit}`List.zipIdx` that the filter keeps. -/
theorem mem_keptAfterDrop {α} {positions : List Nat} {list : List α} {element : α}
    (member : element ∈ keptAfterDrop positions list) :
    ∃ place, !positions.contains place ∧ list[place]? = some element := by
  unfold keptAfterDrop at member
  obtain ⟨⟨same, place⟩, inFilter, rfl⟩ := List.mem_map.mp member
  obtain ⟨inZip, kept⟩ := List.mem_filter.mp inFilter
  exact ⟨place, kept, List.mem_zipIdx_iff_getElem?.mp inZip⟩

/-- For every catalog and positions, {name}`Catalog.drop` is the kept objects
({name}`keptAfterDrop`), each with its entry after the drop ({name}`CatalogEntry.afterDrop`). Proof sketch: both are the
same map of the same filter. -/
theorem Catalog.drop_eq_keptAfterDrop (catalog : Catalog) (positions : List Nat) :
    catalog.drop positions =
      (keptAfterDrop positions catalog).map fun object => { object with entry := object.entry.afterDrop positions } := by
  simp only [Catalog.drop, keptAfterDrop, List.map_map]
  rfl

/-- For every database and positions, the row lists after {name}`Database.drop` are the kept row
lists ({name}`keptAfterDrop`). Proof sketch: the definition. -/
theorem Database.drop_rows (database : Database) (positions : List Nat) :
    (database.drop positions).rows = keptAfterDrop positions database.rows := rfl

end Belay.Sqlite.Model
