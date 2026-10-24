import Belay.Sqlite.Model.Summation

set_option doc.verso true

/-! The integer overflow of {lit}`SUM`: over integers and NULLs, {lit}`SUM` fails exactly when
the exact sum of some first part of the inputs leaves the 64-bit range. -/

namespace Belay.Sqlite.Model

/-- The integers among values, in order; NULL and every other value leave no integer. -/
def integerCells (values : List Value) : List Int :=
  values.filterMap fun
    | .integer value => some value
    | .null | .real _ | .text _ | .blob _ => none

/-- For every state and integer, if the state is not approximate and the sum after the addition fits in 64 bits,
adding the integer increments the input count and adds the integer to the exact sum. All other fields stay the same.
Proof sketch: unfold {name}`SumState.add`; the input of an integer is the integer. -/
theorem SumState.add_integer_exact (state : SumState) (value : Int) (exact : state.approximate = false)
    (fits : fitsInt64Range (state.integerSum + value) = true) :
    state.add (.integer value) = { state with count := state.count + 1, integerSum := state.integerSum + value } := by
  simp [SumState.add, Value.sumInput?, exact, fits]

/-- For every state and integer: adding an integer to an approximate state with the overflow flag keeps both. Proof
sketch: unfold {name}`SumState.add`; {name}`SumState.addInteger` changes only the sums. -/
theorem SumState.add_integer_overflowed (state : SumState) (value : Int) (approximate : state.approximate = true)
    (overflow : state.overflow = true) :
    (state.add (.integer value)).approximate = true ∧ (state.add (.integer value)).overflow = true ∧
      (state.add (.integer value)).count = state.count + 1 := by
  simp [SumState.add, Value.sumInput?, approximate, SumState.addInteger, SumState.addDouble, overflow]
  split <;> simp

/-- For every state and integer: adding an integer to a state that is not approximate, when the new sum leaves the
64-bit range, gives an approximate state with the overflow flag and one more input. Proof sketch: unfold
{name}`SumState.add`; the state starts the approximate sum, sets the flag, and adds the integer in doubles. -/
theorem SumState.add_integer_overflows (state : SumState) (value : Int) (exact : state.approximate = false)
    (leaves : fitsInt64Range (state.integerSum + value) = false) :
    (state.add (.integer value)).approximate = true ∧ (state.add (.integer value)).overflow = true ∧
      (state.add (.integer value)).count = state.count + 1 := by
  have key : ∀ (state : SumState) (value : Int),
      (({ state.startApproximate with overflow := true }).addInteger value).approximate = true ∧
      (({ state.startApproximate with overflow := true }).addInteger value).overflow = true ∧
      (({ state.startApproximate with overflow := true }).addInteger value).count = state.count := fun state value => by
    unfold SumState.startApproximate SumState.addInteger SumState.addDouble
    dsimp only
    split <;> split <;> simp
  have := key { state with count := state.count + 1 } value
  simpa [SumState.add, Value.sumInput?, exact, leaves] using this

/-- For every integers and state that is approximate with the overflow flag: adding the integers one by one keeps the
state approximate with the flag, and counts each integer. Proof sketch: induction on the integers with
{name}`SumState.add_integer_overflowed`. -/
theorem sumFold_overflowed (ints : List Int) : ∀ state : SumState, state.approximate = true → state.overflow = true →
    (ints.foldl (fun state value => state.add (.integer value)) state).approximate = true ∧
    (ints.foldl (fun state value => state.add (.integer value)) state).overflow = true ∧
    (ints.foldl (fun state value => state.add (.integer value)) state).count = state.count + ints.length := by
  induction ints with
  | nil => intro state approximate overflow; exact ⟨approximate, overflow, rfl⟩
  | cons head rest induction =>
    intro state approximate overflow
    obtain ⟨stepApproximate, stepOverflow, stepCount⟩ := SumState.add_integer_overflowed state head approximate overflow
    obtain ⟨rApproximate, rOverflow, rCount⟩ := induction _ stepApproximate stepOverflow
    exact ⟨rApproximate, rOverflow, by rw [List.foldl_cons, rCount, stepCount, List.length_cons]; omega⟩

/-- For every integers and state that is not approximate and whose sum fits in 64 bits, with the integers added one by
one: the state counts each integer; if some first part of the integers, added to the sum of the state, leaves the 64-bit
range, the state is approximate with the overflow flag; and if no first part does, the state is not approximate.
Proof sketch: induction on the integers; a sum that fits goes on exactly
({name}`SumState.add_integer_exact`), and the first sum that does not fit starts the approximate sum with the flag
({name}`SumState.add_integer_overflows`), which stays ({name}`sumFold_overflowed`). -/
theorem sumFold_integers (ints : List Int) : ∀ state : SumState, state.approximate = false →
    fitsInt64Range state.integerSum = true →
    (ints.foldl (fun state value => state.add (.integer value)) state).count = state.count + ints.length ∧
    ((∃ k, fitsInt64Range (state.integerSum + (ints.take k).sum) = false) →
      (ints.foldl (fun state value => state.add (.integer value)) state).approximate = true ∧
      (ints.foldl (fun state value => state.add (.integer value)) state).overflow = true) ∧
    ((∀ k, fitsInt64Range (state.integerSum + (ints.take k).sum) = true) →
      (ints.foldl (fun state value => state.add (.integer value)) state).approximate = false) := by
  induction ints with
  | nil =>
    intro state exact fits
    refine ⟨rfl, fun ⟨k, leaves⟩ => by simp_all, fun _ => exact⟩
  | cons head rest induction =>
    intro state exact fits
    by_cases step : fitsInt64Range (state.integerSum + head) = true
    · obtain ⟨count, overflows, stays⟩ := induction { state with count := state.count + 1, integerSum := state.integerSum + head }
        exact step
      rw [List.foldl_cons, SumState.add_integer_exact state head exact step]
      refine ⟨by rw [count]; simp; omega, fun ⟨k, leaves⟩ => overflows ?_, fun all => stays ?_⟩
      · cases k with
        | zero => simp_all
        | succ k => exact ⟨k, by simpa [Int.add_assoc] using leaves⟩
      · intro k
        simpa [Int.add_assoc] using all (k + 1)
    · have leaves : fitsInt64Range (state.integerSum + head) = false := by simpa using step
      obtain ⟨stepApproximate, stepOverflow, stepCount⟩ := SumState.add_integer_overflows state head exact leaves
      obtain ⟨rApproximate, rOverflow, rCount⟩ := sumFold_overflowed rest _ stepApproximate stepOverflow
      rw [List.foldl_cons]
      refine ⟨by rw [rCount, stepCount, List.length_cons]; omega, fun _ => ⟨rApproximate, rOverflow⟩, fun all => ?_⟩
      have first := all 1
      simp [leaves] at first

/-- For every values that are all NULL or integers, and every state: adding the values to the state one by one is
adding their integers, because {lit}`SUM` skips NULL. Proof sketch: induction on the values; a NULL leaves the state. -/
theorem foldl_add_integerCells (values : List Value) (cells : ∀ value ∈ values, value = .null ∨ ∃ number, value = .integer number) :
    ∀ state : SumState, values.foldl SumState.add state =
      (integerCells values).foldl (fun state number => state.add (.integer number)) state := by
  induction values with
  | nil => intro state; rfl
  | cons head rest induction =>
    intro state
    have restCells : ∀ value ∈ rest, value = .null ∨ ∃ number, value = .integer number :=
      fun value member => cells value (List.mem_cons_of_mem _ member)
    rcases cells head (List.mem_cons_self ..) with isNull | ⟨number, isInteger⟩
    · subst isNull
      simp only [List.foldl_cons, integerCells, List.filterMap_cons] at induction ⊢
      rw [show state.add .null = state by simp [SumState.add, Value.sumInput?]]
      exact induction restCells state
    · subst isInteger
      simp only [List.foldl_cons, integerCells, List.filterMap_cons] at induction ⊢
      exact induction restCells _

/-- For every state: the value of {lit}`SUM` ({name}`SumState.sumValue`) is the {lit}`integer overflow` error exactly
when the state has an input, is approximate, and has the overflow flag. Proof sketch: unfold
{name}`SumState.sumValue`; the three tests are the three conditions. -/
theorem SumState.sumValue_isNone_iff (state : SumState) :
    state.sumValue.isNone = true ↔ state.count ≠ 0 ∧ state.approximate = true ∧ state.overflow = true := by
  unfold SumState.sumValue
  by_cases noInput : state.count = 0 <;> by_cases approximate : state.approximate = true <;>
    by_cases overflow : state.overflow = true <;> simp [noInput, approximate, overflow]

/-- The overflow of {lit}`SUM` over integers, for every values that are all NULL or integers: the value of
{lit}`SUM` is the {lit}`integer overflow` error ({name}`SumState.sumValue` is {lean}`Option.none`) exactly when some
first part of the integers, in order (NULL skipped), has an exact sum outside the 64-bit range
({name}`fitsInt64Range`). A first part is the first {lit}`k` integers for a number {lit}`k`, also the whole list. The
statement holds also when the later integers bring the sum back: {lit}`SUM` of {lit}`9223372036854775807, 1, -1` fails.
Proof sketch: {name}`foldl_add_integerCells` reduces the values to their integers, and {name}`sumFold_integers`
says that the state is approximate with the flag exactly when some first part leaves the range; the flag makes
the value an error when there is an input. -/
theorem sumOf_fails_iff (values : List Value)
    (cells : ∀ value ∈ values, value = .null ∨ ∃ number, value = .integer number) :
    (sumOf values).sumValue.isNone = true ↔
      ∃ k, fitsInt64Range (((integerCells values).take k).sum) = false := by
  unfold sumOf
  rw [foldl_add_integerCells values cells, SumState.sumValue_isNone_iff]
  obtain ⟨count, leaves, stays⟩ := sumFold_integers (integerCells values) {} rfl (by decide)
  simp only [Int.zero_add] at leaves stays
  change (∃ k, fitsInt64Range (((integerCells values).take k).sum) = false) → _ at leaves
  constructor
  · rintro ⟨-, approximate, -⟩
    refine Classical.byContradiction fun noLeave => ?_
    have := stays fun k => by simpa using fun leaves => noLeave ⟨k, leaves⟩
    simp_all
  · rintro ⟨k, outside⟩
    obtain ⟨approximate, overflow⟩ := leaves ⟨k, outside⟩
    refine ⟨?_, approximate, overflow⟩
    rw [count]
    intro zero
    have empty : integerCells values = [] := List.eq_nil_of_length_eq_zero (by simpa using zero)
    simp [empty] at outside
    exact absurd outside (by decide)

end Belay.Sqlite.Model
