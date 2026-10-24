import Belay.Sqlite.Model.UniqueLookupCells

set_option doc.verso true

/-! The cells that a comparison {lit}`c = v` accepted (ADR 0017, S4, outcome 6): a stored cell that the comparison
accepts is not NULL and is equal, under the collation of the comparison, to the value after the affinity of the
column ({name}`Belay.Sqlite.Model.Resolved.comparisonProbe`). Two such cells then conflict as key cells. -/

namespace Belay.Sqlite.Model.Resolved

/-- For every two values and collation: the comparison {lit}`=` of the two values ({name}`Comparison.apply`) is true
({name}`truthy`) exactly when neither value is NULL and the two values compare as equal under the collation. Proof
sketch: unfold {name}`Comparison.apply` and split on NULL. -/
theorem truthy_eq_apply (left right : Value) (collation : Collation) :
    truthy (Comparison.eq.apply left right collation) = true ↔
      left ≠ .null ∧ right ≠ .null ∧ collation.compare left right = .eq := by
  cases left <;> cases right <;> simp [Comparison.apply, Value.isNull, truth, truthy, Comparison.holds]

/-- For every affinity of the comparison, collation, stored cell and value: if the comparison {lit}`cell = value` is
true after the affinity is applied ({name}`comparisonOperands`), the cell is not NULL and compares as equal, under the
collation, to the probe ({name}`comparisonProbe`) of the value. The cell must be in the stored form of the column's
affinity ({name}`LiteralData.storedForm`) when the comparison has an affinity. Proof sketch: for BLOB affinity
and none, the operands are the cell and the value; for INTEGER, REAL and NUMERIC the cell stays
({name}`numericOperand_of_stored`); for TEXT, a TEXT cell meets the TEXT of the value, a BLOB cell meets a BLOB or a TEXT
unchanged, and a BLOB cell never equals a number (different storage classes,
{name}`Collation.compare_ne_of_rank_ne`). -/
theorem cell_eq_probe {affinity : Option Affinity} {collation : Collation} {cell value : Value}
    (stored : ∀ column, affinity = some column → LiteralData.storedForm column cell = true)
    (accepted : truthy (Comparison.eq.apply (comparisonOperands affinity cell value).1
      (comparisonOperands affinity cell value).2 collation) = true) :
    cell ≠ .null ∧ collation.compare cell (comparisonProbe affinity value) = .eq := by
  rw [truthy_eq_apply] at accepted
  match affinity with
  | none | some .blob => exact ⟨accepted.1, accepted.2.2⟩
  | some .integer =>
    simp only [comparisonOperands, numericOperand_of_stored (affinity := .integer) (by decide) (stored _ rfl)] at accepted
    exact ⟨accepted.1, accepted.2.2⟩
  | some .real =>
    simp only [comparisonOperands, numericOperand_of_stored (affinity := .real) (by decide) (stored _ rfl)] at accepted
    exact ⟨accepted.1, accepted.2.2⟩
  | some .numeric =>
    simp only [comparisonOperands, numericOperand_of_stored (affinity := .numeric) (by decide) (stored _ rfl)] at accepted
    exact ⟨accepted.1, accepted.2.2⟩
  | some .text =>
    have cellStored := stored .text rfl
    simp only [LiteralData.storedForm, beq_iff_eq] at cellStored
    cases cell with
    | null =>
      refine absurd ?_ accepted.1
      simp only [comparisonOperands]
      split <;> simp [cellStored]
    | integer number => simp [Value.store] at cellStored
    | real bits => simp [Value.store] at cellStored
    | text bytes =>
      simp only [comparisonOperands, Value.isText, Bool.true_or, ite_true, cellStored] at accepted
      exact ⟨accepted.1, accepted.2.2⟩
    | blob bytes =>
      cases value with
      | null =>
        refine absurd ?_ accepted.2.1
        simp only [comparisonOperands]
        split <;> simp [Value.store]
      | integer number =>
        simp only [comparisonOperands, Value.isText, Bool.or_false, Bool.false_eq_true, ite_false] at accepted
        exact absurd accepted.2.2 (Collation.compare_ne_of_rank_ne collation (by simp [Value.rank]))
      | real bits =>
        simp only [comparisonOperands, Value.isText, Bool.or_false, Bool.false_eq_true, ite_false] at accepted
        refine absurd accepted.2.2 (Collation.compare_ne_of_rank_ne collation ?_)
        simp only [Value.rank]
        split <;> omega
      | text other =>
        simp only [comparisonOperands, Value.isText, Bool.or_true, ite_true, cellStored] at accepted
        exact ⟨accepted.1, accepted.2.2⟩
      | blob other =>
        simp only [comparisonOperands, Value.isText, Bool.or_false, Bool.false_eq_true, ite_false] at accepted
        exact ⟨accepted.1, accepted.2.2⟩

end Belay.Sqlite.Model.Resolved
