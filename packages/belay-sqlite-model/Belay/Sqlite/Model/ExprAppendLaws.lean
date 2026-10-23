import Belay.Sqlite.Model.ExprEval
import Belay.Sqlite.Model.Resolution.ExprAny

set_option doc.verso true

/-! The value of an expression that reads only columns below a width does not change when cells
are appended to a row of at least that width. ADD COLUMN appends a cell to each row, so a key
term or the filter of a partial unique index that reads only the old columns keeps its value
({lit}`KeysUniqueAddColumn`). -/

namespace Belay.Sqlite.Model.Resolved

/-- For the given context: the results of each subquery do not depend on the outer row. The
plain context of a clock value ({name}`EvalContext.plain`), in which key terms and filters are
evaluated, satisfies it. -/
def EvalContext.RowFree (context : EvalContext) : Prop :=
  ∀ index row other, context.subqueries index row = context.subqueries index other

/-- For every clock value, the plain context of the clock value satisfies
{name}`EvalContext.RowFree`: each subquery gives no rows for every outer row. Proof sketch: the
definition. -/
theorem EvalContext.plain_rowFree (clock : Int) : (EvalContext.plain clock).RowFree := fun _ _ _ => rfl

/-- For every context whose subqueries do not depend on the outer row
({name}`EvalContext.RowFree`), width, row with at least that many cells, appended cells and
expression that reads no column at or after the width ({name}`Expr.isColumnFrom`,
{name}`Expr.any`): the expression has the same value and fault ({name}`Expr.evaluate`), and the
same JSON subtype ({name}`Expr.givesJson`), over the row with the cells appended as over the
row. Proof sketch: induction over the mutual expression and argument types; a column below the
width reads a cell of the row, a subquery form reads the same results for both rows, and every
other node combines the values of its parts, which are equal by induction. The subtype of a
JSON call reads the values of its arguments, which the argument case gives. -/
theorem Expr.evaluate_append (context : EvalContext) (rowFree : context.RowFree) {width : Nat} (row extra : List Value)
    (wide : width ≤ row.length) (expression : Expr) (below : expression.any (Expr.isColumnFrom width) = false) :
    expression.evaluate context (row ++ extra) = expression.evaluate context row ∧
      expression.givesJson context (row ++ extra) = expression.givesJson context row := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.any (Expr.isColumnFrom width) = false →
      arguments.evaluate context (row ++ extra) = arguments.evaluate context row ∧
        arguments.givesJson context (row ++ extra) = arguments.givesJson context row ∧
        ∀ head tail, arguments = .cons head tail → head.evaluate context (row ++ extra) = head.evaluate context row ∧
          tail.evaluate context (row ++ extra) = tail.evaluate context row)
  case json function arguments ih =>
    have same := ih (by simpa [Expr.any, Expr.isColumnFrom] using below)
    refine ⟨by simp only [Expr.evaluate, same.1, same.2], ?_⟩
    have values := congrArg Prod.fst same.1
    cases function <;> try rfl
    rcases arguments with _ | ⟨json, _ | ⟨path, _ | ⟨_, _⟩⟩⟩ <;> try rfl
    simp only [Arguments.evaluate, List.cons.injEq] at values
    simp only [Expr.givesJson, values.1, values.2.1]
  case column position =>
    have inside : position < row.length := by
      simp only [Expr.any, Expr.isColumnFrom, ge_iff_le, decide_eq_false_iff_not, Nat.not_le] at below
      omega
    simp [Expr.evaluate, Expr.givesJson, List.getD_eq_getElem?_getD, List.getElem?_append_left inside]
  case «exists» index => simp [Expr.evaluate, Expr.givesJson, rowFree index (row ++ extra) row]
  case subquery index => simp [Expr.evaluate, Expr.givesJson, rowFree index (row ++ extra) row]
  case inQuery operand index affinity collation negated ih =>
    have same := ih (by simpa [Expr.any, Expr.isColumnFrom] using below)
    simp [Expr.evaluate, Expr.givesJson, rowFree index (row ++ extra) row, same.1]
  case scalar function arguments ih =>
    have same := ih (by simpa [Expr.any, Expr.isColumnFrom] using below)
    cases function
    case iif =>
      rcases arguments with _ | ⟨condition, rest⟩
      · simp [Expr.evaluate, Expr.givesJson]
      · have parts := same.2.2 condition rest rfl
        simp [Expr.evaluate, Expr.givesJson, parts.1, parts.2]
    all_goals simp [Expr.evaluate, Expr.givesJson, same.1]
  all_goals simp_all [Expr.any, Arguments.any, Expr.isColumnFrom, Expr.evaluate, Arguments.evaluate, Expr.givesJson,
      Arguments.givesJson]

/-- For every context whose subqueries do not depend on the outer row
({name}`EvalContext.RowFree`), width, row with at least that many cells, appended cells and
expression that reads only columns below the width ({name}`Expr.readsBelow`): the expression has
the same value ({name}`Expr.eval`) over the row with the cells appended as over the row. Proof
sketch: {name}`Expr.evaluate_append`. -/
theorem Expr.eval_append (context : EvalContext) (rowFree : context.RowFree) {width : Nat} (row extra : List Value)
    (wide : width ≤ row.length) {expression : Expr} (below : expression.readsBelow width = true) :
    expression.eval context (row ++ extra) = expression.eval context row := by
  unfold Expr.eval
  rw [(Expr.evaluate_append context rowFree row extra wide expression (by simpa [Expr.readsBelow] using below)).1]

end Belay.Sqlite.Model.Resolved
