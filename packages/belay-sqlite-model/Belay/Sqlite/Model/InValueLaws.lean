import Belay.Sqlite.Model.Truth
import Belay.Sqlite.Model.ExprEval

set_option doc.verso true

/-! When {lit}`x IN (q)` is true (ADR 0017, S4): {name}`Belay.Sqlite.Model.Resolved.inValue` in logic. The test
is true exactly when {lit}`x` is not NULL and some value of the subquery is not NULL and compares equal to
{lit}`x` under the affinity and the collation. {lit}`x NOT IN (q)` is true for an empty subquery, and else
exactly when {lit}`x` is not NULL, no value compares equal, and no value is NULL. -/

namespace Belay.Sqlite.Model.Resolved

/-- For every affinity, collation, value and candidates, {lit}`x IN (q)` is true exactly when {lit}`x` is not NULL and some
candidate is not NULL and compares equal to {lit}`x` after the affinity is applied
({name}`comparisonOperands`) under the collation. An empty list of candidates gives no candidate, so the test is
not true; a NULL value gives NULL, which is not true. Proof sketch: unfold {name}`inValue`; the four cases of its
definition give an empty list (zero), a NULL value (NULL), a match (one), and the others (NULL or zero), of which only
the match is true. -/
theorem truthy_inValue_eq_true (affinity : Option Affinity) (collation : Collation) (value : Value)
    (candidates : List Value) :
    truthy (inValue affinity collation false value candidates) = true ↔
      value.isNull = false ∧ ∃ candidate ∈ candidates,
        (!(comparisonOperands affinity value candidate).2.isNull &&
          collation.compare (comparisonOperands affinity value candidate).1
            (comparisonOperands affinity value candidate).2 == .eq) = true := by
  have null : truthy .null = false := rfl
  unfold inValue
  split
  · next empty =>
    have none : candidates = [] := List.isEmpty_iff.mp empty
    simp [none, truthy_truth]
  · next empty =>
    split
    · next isNull => simp [null, isNull]
    · next isNull =>
      split
      · next found => simp_all [List.any_eq_true]
      · next found =>
        split
        · next nulls => simp_all [List.any_eq_true]
        · next nulls => simp_all [truthy_truth, List.any_eq_true]

/-- For every affinity, collation, value and candidates, {lit}`x NOT IN (q)` is true exactly when there is no candidate (for
every {lit}`x`, also NULL), or when {lit}`x` is not NULL, no candidate compares equal to {lit}`x` after the affinity is applied
({name}`comparisonOperands`) under the collation, and no candidate is NULL. Proof sketch: as for
{name}`truthy_inValue_eq_true`, with the negated results. -/
theorem truthy_inValue_negated_eq_true (affinity : Option Affinity) (collation : Collation) (value : Value)
    (candidates : List Value) :
    truthy (inValue affinity collation true value candidates) = true ↔
      candidates = [] ∨ (value.isNull = false ∧
        (∀ candidate ∈ candidates,
          (!(comparisonOperands affinity value candidate).2.isNull &&
            collation.compare (comparisonOperands affinity value candidate).1
              (comparisonOperands affinity value candidate).2 == .eq) = false) ∧
        ∀ candidate ∈ candidates, candidate.isNull = false) := by
  have null : truthy .null = false := rfl
  unfold inValue
  split
  · next empty =>
    have none : candidates = [] := List.isEmpty_iff.mp empty
    simp [none, truthy_truth]
  · next empty =>
    have some : candidates ≠ [] := fun h => empty (by simp [h])
    split
    · next isNull => simp [null, isNull, some]
    · next isNull =>
      split
      · next found =>
        obtain ⟨x, member, agrees⟩ := List.any_eq_true.mp found
        simp only [truthy_truth, Bool.not_true, Bool.false_eq_true, false_iff]
        intro h
        rcases h with h | ⟨_, all, _⟩
        · exact some h
        · have := all x member
          exact absurd (agrees.symm.trans this) (by simp)
      · next found =>
        split
        · next nulls => simp_all [List.any_eq_true]
        · next nulls => simp_all [truthy_truth, List.any_eq_true]

end Belay.Sqlite.Model.Resolved
