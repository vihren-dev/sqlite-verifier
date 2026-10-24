import Belay.Sqlite.Model.StatementCalm

set_option doc.verso true

/-! Quiet expressions and statements (ADR 0017, S4): an expression that reads no clock and calls no
counter function, though it may call a function that can fail. A statement whose expressions are quiet
passes the first two checks of the run of a statement (no clock read, no unknown counter read), so the
output of a quiet query statement is the output of its query or {lit}`Output.unmodeled`,
by the third check, which is about faults. -/

namespace Belay.Sqlite.Model.Resolved

/-- A quiet expression: none of its parts is a read of the clock ({name}`Expr.readsClockHere`) or a
call of a counter function ({name}`Expr.readsCounterHere`). A call of {lit}`abs` is quiet and not calm
({name}`Expr.Calm`), because {lit}`abs` can fail. -/
def Expr.Quiet (expression : Expr) : Prop :=
  expression.any Expr.readsClockHere = false ∧ ∀ kind, expression.any (Expr.readsCounterHere kind) = false

/-- A quiet statement: every expression that its evaluation reads is quiet ({name}`Expr.Quiet`,
{name}`Statement.clockExpressions`). A statement without expressions is quiet. -/
def Statement.Quiet (statement : Statement) : Prop :=
  ∀ expression ∈ statement.clockExpressions, expression.Quiet

/-- Every calm expression is quiet. Proof sketch: calm is the three conditions, and quiet is the last two. -/
theorem Expr.Calm.quiet {expression : Expr} (calm : expression.Calm) : expression.Quiet := ⟨calm.2.1, calm.2.2⟩

/-- Every calm statement is quiet. Proof sketch: {name}`Expr.Calm.quiet` for each expression. -/
theorem Statement.Calm.quiet {statement : Statement} (calm : statement.Calm) : statement.Quiet :=
  fun expression member => (calm expression member).quiet

/-- For every quiet statement, the statement reads no clock ({name}`Statement.readsClock`). Proof
sketch: as for {name}`Statement.Calm.readsClock`. -/
theorem Statement.Quiet.readsClock {statement : Statement} (quiet : statement.Quiet) :
    statement.readsClock = false := by
  unfold Statement.readsClock Expr.readsClock
  simp only [List.any_eq_false]
  exact fun expression member => by simp [(quiet expression member).1]

/-- For every quiet statement, the statement reads no counter ({name}`Statement.counterReads` is
empty). Proof sketch: as for {name}`Statement.Calm.counterReads`. -/
theorem Statement.Quiet.counterReads {statement : Statement} (quiet : statement.Quiet) :
    statement.counterReads = [] := by
  unfold Statement.counterReads
  simp only [List.filter_eq_nil_iff, List.any_eq_true, not_exists, not_and, Bool.not_eq_true]
  intro kind _ expression member
  simp [(quiet expression member).2 kind]

/-- For every quiet statement and every counters, no counter that the statement reads is unknown
({name}`Counters.firstUnknown`), because it reads none. -/
theorem Statement.Quiet.firstUnknown {statement : Statement} (quiet : statement.Quiet) (counters : Counters) :
    counters.firstUnknown statement.counterReads = none := by
  rw [quiet.counterReads]
  rfl

end Belay.Sqlite.Model.Resolved
