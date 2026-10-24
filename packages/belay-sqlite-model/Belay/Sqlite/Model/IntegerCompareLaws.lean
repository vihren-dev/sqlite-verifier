import Belay.Sqlite.Model.Comparison

set_option doc.verso true

/-! The comparison of two integers (ADR 0017, S4): under every collation it is the order of the integers, so
a comparison of two integers is the comparison of Lean's integers. -/

namespace Belay.Sqlite.Model

/-- For every positive integer, multiplying two integers by it keeps their order. Proof sketch: the three cases of
the order of the integers; a product with a positive number keeps a strict order and an equality. -/
theorem Int.compare_mul_positive (first second scale : Int) (positive : 0 < scale) :
    Ord.compare (first * scale) (second * scale) = Ord.compare first second := by
  rcases Int.lt_trichotomy first second with less | equal | greater
  · rw [Int.compare_eq_lt.2 less, Int.compare_eq_lt.2 (Int.mul_lt_mul_of_pos_right less positive)]
  · rw [equal, Int.compare_eq_eq.2 rfl, Int.compare_eq_eq.2 rfl]
  · rw [Int.compare_eq_gt.2 greater, Int.compare_eq_gt.2 (Int.mul_lt_mul_of_pos_right greater positive)]

/-- For every collation and two integers, the comparison of the integers under the collation is the order of the
integers. Proof sketch: a collation keeps an integer, and two integers of the same rank compare by their scaled
values, which are the integers times the same positive number ({name}`Int.compare_mul_positive`). -/
theorem Collation.compare_integer (collation : Collation) (first second : Int) :
    collation.compare (.integer first) (.integer second) = Ord.compare first second := by
  have key : ∀ value : Int, collation.key (.integer value) = .integer value := by
    intro value
    cases collation <;> rfl
  have positive : (0 : Int) < 2 ^ 1074 := Int.pow_pos (by decide)
  simp only [Collation.compare, key, Value.compare, compareLex, compareOn, Value.rank, Value.scaled, Value.bytes,
    Int.compare_mul_positive _ _ _ positive]
  cases Ord.compare first second <;> rfl

end Belay.Sqlite.Model
