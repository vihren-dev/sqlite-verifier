import Belay.Sqlite.Model.LiteralData
import Belay.Sqlite.Model.IntegerCompareLaws

set_option doc.verso true

/-! The comparison of a stored cell with a value (ADR 0017, S4, outcome 6): when two stored cells of one
column are each equal to the same value in a comparison {lit}`c = v`, the two cells conflict as key cells
({name}`Belay.Sqlite.Model.LiteralData.keyCellsEqual`) under the collation of the comparison. This is the
step of a unique lookup that needs the affinity of the column. -/

namespace Belay.Sqlite.Model

/-- For every collation and value, the collation key of the value has the same storage class
({name}`Value.rank`) as the value. Proof sketch: case analysis on the collation and the value. -/
theorem Collation.key_rank (collation : Collation) (value : Value) : (collation.key value).rank = value.rank := by
  cases collation <;> cases value <;> simp [Collation.key, Value.rank]

/-- For every collation and two values of different storage classes ({name}`Value.rank`), the comparison of the
values under the collation is not {lean}`Ordering.eq`. Proof sketch: the comparison starts with the ranks of the
keys ({name}`Collation.key_rank`), which differ. -/
theorem Collation.compare_ne_of_rank_ne (collation : Collation) {first second : Value}
    (different : first.rank ≠ second.rank) : collation.compare first second ≠ .eq := by
  have ranks : Ord.compare (collation.key first).rank (collation.key second).rank ≠ .eq := by
    rw [Collation.key_rank, Collation.key_rank]
    exact fun equal => different (Nat.compare_eq_eq.1 equal)
  unfold Collation.compare Value.compare compareLex compareOn
  generalize Ord.compare (collation.key first).rank (collation.key second).rank = order at ranks ⊢
  cases order <;> simp_all [Ordering.then]

namespace Resolved

/-- The value that a stored cell is compared with in {lit}`c = v`, for a comparison with the affinity of the column
({name}`comparisonOperands`): with INTEGER, REAL or NUMERIC affinity the value after
{name}`numericOperand`; with TEXT affinity the value after {name}`Value.store` of TEXT; with BLOB affinity or none the
value itself. -/
def comparisonProbe : Option Affinity → Value → Value
  | some .integer, value | some .real, value | some .numeric, value => numericOperand value
  | some .text, value => Value.store .text value
  | some .blob, value | none, value => value

/-- For every cell and affinity of INTEGER, REAL or NUMERIC: if the cell is in the form that a column of the affinity
stores ({name}`LiteralData.storedForm`), {name}`numericOperand` leaves it as it is. Proof sketch: only TEXT can change;
the store of a TEXT is its {name}`numericText`, or for REAL the read of that, which leaves a TEXT only when the
{name}`numericText` is the same TEXT. -/
theorem numericOperand_of_stored {affinity : Affinity} {cell : Value} (numeric : affinity ≠ .text ∧ affinity ≠ .blob)
    (stored : LiteralData.storedForm affinity cell = true) : numericOperand cell = cell := by
  simp only [LiteralData.storedForm, beq_iff_eq] at stored
  cases cell with
  | text bytes =>
    cases affinity with
    | text => exact absurd rfl numeric.1
    | blob => exact absurd rfl numeric.2
    | integer | numeric => exact stored
    | real =>
      simp only [Value.store, numericStore] at stored
      simp only [numericOperand]
      generalize numericText bytes = number at stored ⊢
      cases number <;> simp_all [realRead]
  | null | integer _ | real _ | blob _ => rfl

end Resolved
end Belay.Sqlite.Model
