import Belay.Sqlite.Model.QueryPlainLaws

set_option doc.verso true

/-! What the evaluation of an expression reads of its context (ADR 0017, S4): for the row it
evaluates over, only the subqueries for that row. Two contexts that give the same results for
the subqueries of the row give an expression the same value and fault. A proof about a query over every
database uses this to replace the context of a statement, which holds the running subqueries,
by a context that holds their results. -/

namespace Belay.Sqlite.Model.Resolved

/-- The context with the given results for the subqueries, by index, for every outer row; the other
fields are those of the context. An index past the list gives no row and no fault. For example,
{lit}`context.withRuns [run]` serves subquery 0 with {lit}`run`. -/
def EvalContext.withRuns (context : EvalContext) (runs : List SubqueryRun) : EvalContext :=
  { context with subqueries := fun index _ => (runs[index]?).getD { rows := [], fault := .none } }

/-- For every context, list of results, index and outer row, subquery {lit}`index` of the context with the results is
the result at that index of the list, or no row and no fault past the list. Proof sketch: the definition
computes. -/
theorem EvalContext.withRuns_subqueries (context : EvalContext) (runs : List SubqueryRun) (index : Nat) (outer : List Value) :
    (context.withRuns runs).subqueries index outer = (runs[index]?).getD { rows := [], fault := .none } := rfl

/-- For every context and list of results, the values bound to the parameters of the context with the results are
those of the context. Proof sketch: the definition computes. -/
theorem EvalContext.withRuns_parameters (context : EvalContext) (runs : List SubqueryRun) :
    (context.withRuns runs).parameters = context.parameters := rfl

/-- For every context, row, other results of the subqueries that equal the context's for the row, and
expression without a fallible call at any depth ({name}`Expr.isFallibleCall`), the value and fault of the
expression over the row are the same in the context and in the context with the other results. Proof sketch:
induction over the mutual expression and argument types; a node that reads no subquery reads only the same
fields of the contexts, a node that names a subquery reads the results for the row, which agree, and
a call that cannot fail does not read the context. -/
theorem Expr.evaluate_withSubqueries (context : EvalContext) (row : List Value)
    (other : Nat → List Value → SubqueryRun) (agree : ∀ index, context.subqueries index row = other index row)
    (expression : Expr) (plain : expression.any Expr.isFallibleCall = false) :
    expression.evaluate { context with subqueries := other } row = expression.evaluate context row := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.any Expr.isFallibleCall = false →
      arguments.evaluate { context with subqueries := other } row = arguments.evaluate context row ∧
      match arguments with
      | .nil => True
      | .cons head tail => head.evaluate { context with subqueries := other } row = head.evaluate context row ∧
          tail.evaluate { context with subqueries := other } row = tail.evaluate context row) <;>
    simp_all [Expr.any, Arguments.any, Expr.isFallibleCall, Expr.evaluate, Arguments.evaluate]
  case scalar function arguments ih =>
    cases function <;> try simp_all [Expr.evaluate]
    cases arguments with
    | nil => simp [Expr.evaluate]
    | cons head tail => simp_all [Expr.evaluate]

/-- The result of a subquery with its first row marked certain. A scalar subquery reads that mark; {lit}`EXISTS` and
{lit}`IN` do not. -/
def SubqueryRun.certainFirst (run : SubqueryRun) : SubqueryRun := { run with firstCertain := true }

/-- For every result, marking its first row certain keeps its rows. Proof sketch: the definition computes. -/
@[simp] theorem SubqueryRun.certainFirst_rows (run : SubqueryRun) : run.certainFirst.rows = run.rows := rfl

/-- For every result, marking its first row certain keeps its fault. Proof sketch: the definition computes. -/
@[simp] theorem SubqueryRun.certainFirst_fault (run : SubqueryRun) : run.certainFirst.fault = run.fault := rfl

/-- For every result, marking its first row certain keeps the certainty of its rows. Proof sketch: the definition
computes. -/
@[simp] theorem SubqueryRun.certainFirst_rowsCertain (run : SubqueryRun) : run.certainFirst.rowsCertain = run.rowsCertain := rfl

/-- For every result, marking its first row certain makes the first row certain. Proof sketch: the definition
computes. -/
@[simp] theorem SubqueryRun.certainFirst_firstCertain (run : SubqueryRun) : run.certainFirst.firstCertain = true := rfl

/-- For every context, row and expression without a scalar subquery ({lit}`(SELECT ...)`) at any depth, with no
fallible call, the value and fault of the expression over the row are the same in the context and in the
context in which every subquery has its first row marked certain ({name}`SubqueryRun.certainFirst`). Proof sketch:
induction over the mutual expression and argument types; only a scalar subquery reads the mark, and a call that
cannot fail does not read the context. -/
theorem Expr.evaluate_certainFirst (context : EvalContext) (row : List Value) (expression : Expr)
    (noScalar : expression.any (· matches .subquery _) = false)
    (plain : expression.any Expr.isFallibleCall = false) :
    expression.evaluate { context with subqueries := fun index outer => (context.subqueries index outer).certainFirst } row =
      expression.evaluate context row := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.any (· matches .subquery _) = false →
      arguments.any Expr.isFallibleCall = false →
      arguments.evaluate { context with subqueries := fun index outer => (context.subqueries index outer).certainFirst } row =
        arguments.evaluate context row ∧
      match arguments with
      | .nil => True
      | .cons head tail =>
        head.evaluate { context with subqueries := fun index outer => (context.subqueries index outer).certainFirst } row =
          head.evaluate context row ∧
        tail.evaluate { context with subqueries := fun index outer => (context.subqueries index outer).certainFirst } row =
          tail.evaluate context row) <;>
    simp_all [Expr.any, Arguments.any, Expr.isFallibleCall, Expr.evaluate, Arguments.evaluate]
  case inQuery => rfl
  case scalar =>
    rename_i function arguments ih
    cases function <;> try simp_all [Expr.evaluate]
    cases arguments with
    | nil => simp [Expr.evaluate]
    | cons head tail => simp_all [Expr.evaluate]

end Belay.Sqlite.Model.Resolved
