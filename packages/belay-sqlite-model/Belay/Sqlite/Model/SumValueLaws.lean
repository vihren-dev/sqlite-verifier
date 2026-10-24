import Belay.Sqlite.Model.SumIntegerLaws
import Belay.Sqlite.Model.QueryEval

set_option doc.verso true

/-! The values and faults of {lit}`SUM` over integer and NULL inputs. These laws connect the
aggregate expression to exact integer addition and the first partial sum outside the 64-bit range. -/

namespace Belay.Sqlite.Model

/-- For every integer list and exact state, if adding each prefix of the list to the state's sum
fits in 64 bits, the fold increments the count by the list's length and adds its sum. All other
state fields stay the same. Proof sketch: induction on the list, using
{name}`SumState.add_integer_exact` for each addition. -/
theorem sumFold_exact (ints : List Int) (state : SumState) (exact : state.approximate = false)
    (fits : ∀ k, fitsInt64Range (state.integerSum + (ints.take k).sum) = true) :
    ints.foldl (fun state value => state.add (.integer value)) state =
      { state with count := state.count + ints.length, integerSum := state.integerSum + ints.sum } := by
  induction ints generalizing state with
  | nil => simp
  | cons head rest ih =>
    have first : fitsInt64Range (state.integerSum + head) = true := by simpa using fits 1
    rw [List.foldl_cons, SumState.add_integer_exact state head exact first]
    rw [ih { state with count := state.count + 1, integerSum := state.integerSum + head }
      exact (fun k => by simpa [Int.add_assoc] using fits (k + 1))]
    simp [Int.add_assoc]
    omega

/-- For every list of integer or NULL values whose integer prefixes all fit in 64 bits,
{name}`sumOf` produces NULL when there is no integer, and otherwise the exact integer sum.
Proof sketch: discard NULL with {name}`foldl_add_integerCells`, then use {name}`sumFold_exact`
from the empty state and the definition of {name}`SumState.sumValue`. -/
theorem sumOf_value_of_fits (values : List Value)
    (cells : ∀ value ∈ values, value = .null ∨ ∃ number, value = .integer number)
    (fits : ∀ k, fitsInt64Range (((integerCells values).take k).sum) = true) :
    (sumOf values).sumValue = some (if integerCells values = [] then .null else .integer (integerCells values).sum) := by
  unfold sumOf
  rw [foldl_add_integerCells values cells, sumFold_exact _ {} rfl (by simpa using fits)]
  simp [SumState.sumValue, List.length_eq_zero_iff, apply_ite]

namespace Resolved

/-- For every context, rows and operand, {lit}`SUM` evaluates the operand on each row and reads
{name}`SumState.sumValue` from those inputs. Its value is NULL when the sum reports an error;
{name}`Aggregate.fails` reports that error separately. Proof sketch: the definition computes. -/
theorem Aggregate.eval_sum (context : EvalContext) (rows : List (List Value)) (operand : Expr) :
    (Aggregate.sum operand).eval context rows =
      (sumOf (rows.map (operand.eval context))).sumValue.getD .null := rfl

/-- For every context, rows and operand, {lit}`SUM` fails exactly when its sum has no value.
Proof sketch: the definition computes. -/
theorem Aggregate.fails_sum (context : EvalContext) (rows : List (List Value)) (operand : Expr) :
    (Aggregate.sum operand).fails context rows =
      (sumOf (rows.map (operand.eval context))).sumValue.isNone := rfl

/-- For every context and rows, {lit}`count(*)` does not fail.
Proof sketch: the definition computes. -/
theorem Aggregate.fails_countRows (context : EvalContext) (rows : List (List Value)) :
    Aggregate.countRows.fails context rows = false := rfl

end Resolved
end Belay.Sqlite.Model
