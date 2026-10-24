import Belay.Sqlite.Model.QueryEval

set_option doc.verso true

/-! Grouping and pairs of rows (ADR 0017, S4): the rows of a query that groups its rows have only groups of one row
exactly when no row is in one group with an earlier row, which is the statement "no two rows have equal keys". -/

namespace Belay.Sqlite.Model.Resolved

/-- One step of grouping: a new row joins the first group whose first row it is the same as ({lit}`same`), and
starts a group of its own when there is none. {name}`groups` is a fold of this step. -/
def groupStep {α : Type} (same : α → α → Bool) (found : List (List α)) (row : α) : List (List α) :=
  match found.findIdx? (fun group => group.head?.any (same row)) with
  | some index => found.modify index (· ++ [row])
  | none => found ++ [[row]]

/-- A step of grouping never makes a group shorter: each group of the groups before is, in the groups after, at the
same position or one position of a group that is at least as long. Proof sketch: a row that joins a group makes
that group longer, and any other group stays as it is; a row that starts a group adds one group at the end. -/
theorem groupStep_length_le {α : Type} (same : α → α → Bool) (found : List (List α)) (row : α) (group : List α)
    (member : group ∈ found) : ∃ longer ∈ groupStep same found row, group.length ≤ longer.length := by
  unfold groupStep
  cases search : found.findIdx? (fun group => group.head?.any (same row)) with
  | none => exact ⟨group, List.mem_append_left _ member, Nat.le_refl _⟩
  | some index =>
    obtain ⟨position, bound, rfl⟩ := List.getElem_of_mem member
    have bounded : (found.modify index (· ++ [row])).length = found.length := List.length_modify _ _ _
    refine ⟨(found.modify index (· ++ [row]))[position]'(by omega), List.getElem_mem _, ?_⟩
    rw [List.getElem_modify]
    by_cases same : index = position
    · simp [same]
    · simp [same]

/-- Many steps of grouping never make a group shorter: each group before has, among the groups after the steps of
the rows, a group that is at least as long. Proof sketch: induction on the rows with
{name}`groupStep_length_le`. -/
theorem groupFold_length_le {α : Type} (same : α → α → Bool) :
    ∀ (rows : List α) (found : List (List α)) (group : List α), group ∈ found →
      ∃ longer ∈ rows.foldl (groupStep same) found, group.length ≤ longer.length
  | [], _, group, member => ⟨group, member, Nat.le_refl _⟩
  | row :: rows, found, group, member => by
    obtain ⟨grown, grownMember, grownLength⟩ := groupStep_length_le same found row group member
    obtain ⟨longer, longerMember, longerLength⟩ := groupFold_length_le same rows _ grown grownMember
    exact ⟨longer, longerMember, Nat.le_trans grownLength longerLength⟩

/-- When each group before is one row that is not the same as any of the rows still to come, and those rows are
pairwise not the same as an earlier one, every group after the steps has at most one row. Proof sketch: induction
on the rows; each row finds no group to join, so it starts a group of its own. -/
theorem groupFold_singletons_of_pairwise {α : Type} (same : α → α → Bool) :
    ∀ (rows : List α) (found : List (List α)),
      (∀ group ∈ found, ∃ first, group = [first] ∧ ∀ later ∈ rows, same later first = false) →
      rows.Pairwise (fun earlier later => same later earlier = false) →
      ∀ group ∈ rows.foldl (groupStep same) found, group.length ≤ 1
  | [], found, singles, _, group, member => by
    obtain ⟨first, rfl, _⟩ := singles group member
    exact Nat.le_refl _
  | row :: rows, found, singles, pairwise, group, member => by
    rw [List.pairwise_cons] at pairwise
    have fresh : found.findIdx? (fun group => group.head?.any (same row)) = none := by
      rw [List.findIdx?_eq_none_iff]
      intro candidate inFound
      obtain ⟨first, rfl, others⟩ := singles candidate inFound
      simp [others row List.mem_cons_self]
    refine groupFold_singletons_of_pairwise same rows (groupStep same found row) ?_ pairwise.2 group member
    simp only [groupStep, fresh]
    intro candidate inGroups
    rcases List.mem_append.1 inGroups with inFound | inNew
    · obtain ⟨first, rfl, others⟩ := singles candidate inFound
      exact ⟨first, rfl, fun later laterIn => others later (List.mem_cons_of_mem _ laterIn)⟩
    · rw [List.mem_singleton] at inNew
      exact ⟨row, inNew, pairwise.1⟩

/-- When each group before is one row and every group after the steps has at most one row, no row still to come is the
same as a row before, and the rows still to come are pairwise not the same as an earlier one. Proof sketch: induction
on the rows; a row that joins a group makes a group of two rows, and no later step makes that group shorter
({name}`groupFold_length_le`), so each row starts a group of its own, and no group before has a first row that
it is the same as. -/
theorem groupFold_pairwise_of_singletons {α : Type} (same : α → α → Bool) :
    ∀ (rows : List α) (found : List (List α)), (∀ group ∈ found, ∃ first, group = [first]) →
      (∀ group ∈ rows.foldl (groupStep same) found, group.length ≤ 1) →
      (∀ later ∈ rows, ∀ group ∈ found, ∀ first ∈ group, same later first = false) ∧
        rows.Pairwise (fun earlier later => same later earlier = false)
  | [], _, _, _ => ⟨fun _ member => by simp at member, .nil⟩
  | row :: rows, found, singles, short => by
    have fresh : found.findIdx? (fun group => group.head?.any (same row)) = none := by
      cases search : found.findIdx? (fun group => group.head?.any (same row)) with
      | none => rfl
      | some index =>
        exfalso
        have bound : index < found.length := (List.findIdx?_eq_some_iff_getElem.1 search).choose
        obtain ⟨first, single⟩ := singles found[index] (List.getElem_mem bound)
        have grown : (groupStep same found row)[index]'(by simp [groupStep, search, List.length_modify, bound]) =
            found[index] ++ [row] := by
          simp [groupStep, search]
        obtain ⟨longer, longerMember, longerLength⟩ := groupFold_length_le same rows _ _ (grown ▸ List.getElem_mem _)
        have := short longer (by simpa using longerMember)
        simp [single] at longerLength
        omega
    have next : ∀ group ∈ rows.foldl (groupStep same) (groupStep same found row), group.length ≤ 1 := by
      simpa [List.foldl_cons] using short
    have singlesNext : ∀ group ∈ groupStep same found row, ∃ first, group = [first] := by
      simp only [groupStep, fresh]
      intro candidate inGroups
      rcases List.mem_append.1 inGroups with inFound | inNew
      · exact singles candidate inFound
      · exact ⟨row, List.mem_singleton.1 inNew⟩
    obtain ⟨laterSame, pairwise⟩ := groupFold_pairwise_of_singletons same rows _ singlesNext next
    have rowFresh : ∀ group ∈ found, ∀ first ∈ group, same row first = false := by
      intro group inFound first firstIn
      have := List.findIdx?_eq_none_iff.1 fresh group inFound
      obtain ⟨single, rfl⟩ := singles group inFound
      simp at firstIn
      subst firstIn
      simpa using this
    refine ⟨?_, ?_⟩
    · intro later laterIn group inFound first firstIn
      rcases List.mem_cons.1 laterIn with rfl | laterRows
      · exact rowFresh group inFound first firstIn
      · exact laterSame later laterRows group (by simp [groupStep, fresh, inFound]) first firstIn
    · rw [List.pairwise_cons]
      exact ⟨fun later laterRows => laterSame later laterRows [row] (by simp [groupStep, fresh]) row (by simp), pairwise⟩

/-- Two rows are the same for the grouping terms {lit}`terms` when, for each term, the values of the term in the two
rows compare as equal under the collation of the term. This is the test that {name}`groups` makes. -/
def sameGroup (context : EvalContext) (terms : List (Expr × Collation)) (first second : List Value) : Bool :=
  ((terms.map (·.2)).zip ((terms.map fun (term, _) => term.eval context first).zip
    (terms.map fun (term, _) => term.eval context second))).all fun (collation, a, b) => collation.compare a b == .eq

/-- The groups of {name}`groups` are the fold of {name}`groupStep` with the test {name}`sameGroup`. Proof sketch: the
definitions agree after unfolding. -/
theorem groups_eq_fold (context : EvalContext) (terms : List (Expr × Collation)) (rows : List (List Value)) :
    groups context terms rows = rows.foldl (groupStep (sameGroup context terms)) [] := rfl

/-- For every context, grouping terms and rows, every group of the rows has at most one row exactly when no row is the
same ({name}`sameGroup`) as a row before it. An empty list of rows has no group, and one row has a group of one row.
Proof sketch: {name}`groupFold_singletons_of_pairwise` and {name}`groupFold_pairwise_of_singletons` from no groups. -/
theorem groups_short_iff_pairwise (context : EvalContext) (terms : List (Expr × Collation))
    (rows : List (List Value)) :
    (∀ group ∈ groups context terms rows, group.length ≤ 1) ↔
      rows.Pairwise (fun earlier later => sameGroup context terms later earlier = false) := by
  rw [groups_eq_fold]
  exact ⟨fun short => (groupFold_pairwise_of_singletons _ rows [] (by simp) short).2,
    fun pairwise => groupFold_singletons_of_pairwise _ rows [] (by simp) pairwise⟩

/-- For every context, grouping terms and rows, some group of the rows has more than one row exactly when some row is
the same ({name}`sameGroup`) as a row before it. Proof sketch: {name}`groups_short_iff_pairwise`, negated. -/
theorem groups_long_iff_repeated (context : EvalContext) (terms : List (Expr × Collation)) (rows : List (List Value)) :
    (∃ group ∈ groups context terms rows, 1 < group.length) ↔
      ¬ rows.Pairwise (fun earlier later => sameGroup context terms later earlier = false) := by
  rw [← groups_short_iff_pairwise]
  constructor
  · rintro ⟨group, member, long⟩ short
    have := short group member
    omega
  · intro notShort
    exact Classical.byContradiction fun none => notShort fun group member =>
      Nat.le_of_not_lt fun long => none ⟨group, member, long⟩

/-- For one grouping term, two rows are the same exactly when the values of the term in the two rows compare as equal
under the collation. Proof sketch: the definitions agree after unfolding. -/
theorem sameGroup_single (context : EvalContext) (term : Expr) (collation : Collation) (first second : List Value) :
    sameGroup context [(term, collation)] first second =
      (collation.compare (term.eval context first) (term.eval context second) == .eq) := by
  simp [sameGroup]

end Belay.Sqlite.Model.Resolved
