import Belay

/-! The aggregate expression laws of `SqlSimpLaws`, `SumIntegerLaws` and `SumValueLaws`.
The free-input proofs check that users can reason about COUNT and SUM with the shared laws.
Kernel examples distinguish a prefix overflow from a final sum outside the range. -/

open Belay.Sqlite.Model

/-- For every group and context, `sql_simp` turns COUNT into the number of rows and proves that
COUNT does not fail. -/
example (context : Resolved.EvalContext) (rows : List (List Value)) :
    Resolved.Aggregate.countRows.eval context rows = .integer rows.length ∧
      Resolved.Aggregate.countRows.fails context rows = false := by
  simp [sql_simp]

/-- The same aggregate laws are available to `grind`, without unfolding the aggregate evaluator. -/
example (context : Resolved.EvalContext) (rows : List (List Value)) :
    Resolved.Aggregate.countRows.eval context rows = .integer rows.length ∧
      Resolved.Aggregate.countRows.fails context rows = false := by
  grind

/-- If each operand is an integer or NULL, SUM fails exactly when an integer prefix sum leaves
64 bits. Proof sketch: `sql_simp` applies the sum-failure equation and the integer-prefix law. -/
theorem integer_sum_failure (context : Resolved.EvalContext) (rows : List (List Value))
    (operand : Resolved.Expr)
    (cells : ∀ value ∈ rows.map (operand.eval context), value = .null ∨ ∃ number, value = .integer number) :
    (Resolved.Aggregate.sum operand).fails context rows = true ↔
      ∃ k, fitsInt64Range ((integerCells (rows.map (operand.eval context))).take k).sum = false := by
  simp (disch := assumption) only [sql_simp]

/-- If every integer prefix fits, SUM gives NULL for no integer and otherwise its exact sum.
Proof sketch: `sql_simp` applies the aggregate-value equation and the exact-fold law. -/
theorem integer_sum_value (context : Resolved.EvalContext) (rows : List (List Value))
    (operand : Resolved.Expr)
    (cells : ∀ value ∈ rows.map (operand.eval context), value = .null ∨ ∃ number, value = .integer number)
    (fits : ∀ k, fitsInt64Range ((integerCells (rows.map (operand.eval context))).take k).sum = true) :
    (Resolved.Aggregate.sum operand).eval context rows =
      if integerCells (rows.map (operand.eval context)) = [] then .null
      else .integer (integerCells (rows.map (operand.eval context))).sum := by
  simp (disch := assumption) only [sql_simp, Option.getD_some]

/-- SUM skips NULL and keeps a fitting integer sum exact. -/
example : (sumOf [.null, .integer 10, .integer (-3)]).sumValue = some (.integer 7) := by decide +kernel

/-- With no integer input SUM returns NULL. -/
example : (sumOf [.null, .null]).sumValue = some .null := by decide +kernel

/-- Later integer cancellation does not clear a prefix overflow. -/
example : (sumOf [.integer 9223372036854775807, .integer 1, .integer (-1)]).sumValue.isNone = true := by
  decide +kernel

/-- A fitting sum has no overflowing prefix, so the failure equivalence has a negative instance. -/
example : ¬ ∃ k, fitsInt64Range ((integerCells [.null, .integer 10, .integer (-3)]).take k).sum = false := by
  intro outside
  have failed := (sumOf_fails_iff [.null, .integer 10, .integer (-3)] (by simp)).2 outside
  have safe : (sumOf [.null, .integer 10, .integer (-3)]).sumValue.isNone = false := by decide +kernel
  simp [safe] at failed
