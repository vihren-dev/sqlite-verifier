import Belay.Sqlite.Model.StatementCounterReads
import Belay.Sqlite.Model.Counters

set_option doc.verso true

/-! Calm expressions and statements (ADR 0017, S4): an expression that has no fallible call, reads
no clock and calls no counter function. A claim over every database about a statement whose
expressions are calm needs none of the three facts that the run of a statement checks first (a
plain query, no clock read, no unknown counter read), so the query laws of the surface only
state calm. -/

namespace Belay.Sqlite.Model.Resolved

/-- A calm expression: none of its parts is a fallible call ({name}`Expr.isFallibleCall`), a read
of the clock ({name}`Expr.readsClockHere`) or a call of a counter function
({name}`Expr.readsCounterHere`). For example, a comparison of a column with a literal is calm, and
{lit}`abs(x)` is not, because {lit}`abs` can fail. -/
def Expr.Calm (expression : Expr) : Prop :=
  expression.any Expr.isFallibleCall = false ∧ expression.any Expr.readsClockHere = false ∧
    ∀ kind, expression.any (Expr.readsCounterHere kind) = false

/-- A calm statement: every expression that its evaluation reads is calm
({name}`Expr.Calm`, {name}`Statement.clockExpressions`). A statement without expressions is calm. -/
def Statement.Calm (statement : Statement) : Prop :=
  ∀ expression ∈ statement.clockExpressions, expression.Calm

/-- For every calm statement, the statement reads no clock ({name}`Statement.readsClock`). Proof
sketch: a clock read is a part of an expression that reads the clock, which the calm expression
lacks. -/
theorem Statement.Calm.readsClock {statement : Statement} (calm : statement.Calm) : statement.readsClock = false := by
  unfold Statement.readsClock Expr.readsClock
  simp only [List.any_eq_false]
  exact fun expression member => by simp [(calm expression member).2.1]

/-- For every calm statement, the statement reads no counter ({name}`Statement.counterReads` is
empty). Proof sketch: a counter that the statement reads is a part of one of its expressions that
calls the counter function, which a calm expression lacks. -/
theorem Statement.Calm.counterReads {statement : Statement} (calm : statement.Calm) : statement.counterReads = [] := by
  unfold Statement.counterReads
  simp only [List.filter_eq_nil_iff, List.any_eq_true, not_exists, not_and, Bool.not_eq_true]
  intro kind _ expression member
  simp [(calm expression member).2.2 kind]

/-- For every calm statement and every counters, no counter that the statement reads is unknown
({name}`Counters.firstUnknown`), because it reads none ({name}`Statement.Calm.counterReads`). -/
theorem Statement.Calm.firstUnknown {statement : Statement} (calm : statement.Calm) (counters : Counters) :
    counters.firstUnknown statement.counterReads = none := by
  rw [calm.counterReads]
  rfl

/-- For every calm statement of a query with subqueries, the expressions of the query have no
fallible call. Proof sketch: the expressions of the query are among those of the statement. -/
theorem Statement.Calm.query_plain {query : Query} {subqueries : List Query} (calm : (Statement.query query subqueries).Calm) :
    query.expressions.all (!·.any Expr.isFallibleCall) = true := by
  simp only [List.all_eq_true, Bool.not_eq_true']
  exact fun expression member => (calm expression (by simp [Statement.clockExpressions, member])).1

/-- For every calm statement of a query with subqueries, the expressions of each subquery have no
fallible call. Proof sketch: the expressions of a subquery are among those of the statement
({name}`Statement.clockExpressions`). -/
theorem Statement.Calm.subquery_plain {query : Query} {subqueries : List Query}
    (calm : (Statement.query query subqueries).Calm) {inner : Query} (member : inner ∈ subqueries) :
    inner.expressions.all (!·.any Expr.isFallibleCall) = true := by
  simp only [List.all_eq_true, Bool.not_eq_true']
  intro expression inside
  have present : expression ∈ (Statement.query query subqueries).clockExpressions := by
    simp only [Statement.clockExpressions, List.mem_append, List.mem_flatMap]
    exact .inr ⟨inner, member, inside⟩
  exact (calm expression present).1

/-- For every calm statement of a query with subqueries, the model's check of the subqueries
({name}`subqueriesPlain`) passes for the subqueries that are no term of a compound. Proof sketch:
the nested subqueries are among the subqueries of the statement, whose expressions are calm
({name}`Statement.Calm.subquery_plain`). -/
theorem Statement.Calm.subqueries_plain {query : Query} {subqueries : List Query}
    (calm : (Statement.query query subqueries).Calm) : subqueriesPlain (query.nestedSubqueries subqueries) = true := by
  have each : ∀ inner ∈ subqueries, inner.expressions.all (!·.any Expr.isFallibleCall) = true :=
    fun inner member => calm.subquery_plain member
  unfold Query.nestedSubqueries
  split
  · exact List.all_eq_true.mpr each
  · exact List.all_eq_true.mpr fun inner member => each inner (by
      obtain ⟨⟨_, index⟩, kept, rfl⟩ := List.mem_map.mp member
      exact List.fst_mem_of_mem_zipIdx (List.mem_filter.mp kept).1)

end Belay.Sqlite.Model.Resolved
