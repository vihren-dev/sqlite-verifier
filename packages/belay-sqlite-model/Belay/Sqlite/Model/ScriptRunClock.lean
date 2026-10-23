import Belay.Sqlite.Model.ScriptRunIndex

set_option doc.verso true

/-! The clock assignment with which {name}`Belay.Sqlite.Model.runSqlFrom` takes the same steps as
the run of {lit}`ScriptRun.lean` with an optional clock. The run gives each statement the clock
value of {name}`Belay.Sqlite.Model.statementClock`, and {name}`Belay.Sqlite.Model.runSqlFrom`
gives it the value of the state's clock assignment at its position; the two agree when the
assignment fits the run ({lit}`ClockFits`). The assignment of
{name}`Belay.Sqlite.Model.scriptClock` fits a run from index 0. -/

namespace Belay.Sqlite.Model

/-- The clock assignment fits the run with the optional clock from the zero-based index over
the resolved statements: for every offset, statement and value, if the statement is at the
offset and its clock value in the run at the index plus the offset ({name}`statementClock`) is
the value, then the assignment gives the value at the index plus the offset. A statement that
reads the clock in a run without a clock has no clock value, so the formula requires nothing of
the assignment at its position. -/
def ClockFits (clock : Option Clock) (index : Nat) (statements : List Resolved.Statement) (assignment : Clock) :
    Prop :=
  ∀ offset statement value, statements[offset]? = some statement →
    statementClock clock (index + offset) statement = some value → assignment (index + offset) = value

/-- For every optional clock, index, statement, rest of the statements, assignment and value:
if the assignment fits the run over the statement and the rest, and the statement's clock value
at the index is the value, the assignment gives the value at the index. Proof sketch: the
definition at offset 0. -/
theorem ClockFits.head {clock : Option Clock} {index : Nat} {statement : Resolved.Statement}
    {rest : List Resolved.Statement} {assignment : Clock}
    (fits : ClockFits clock index (statement :: rest) assignment) {value : Int}
    (valued : statementClock clock index statement = some value) : assignment index = value :=
  fits 0 statement value rfl valued

/-- For every optional clock, index, statement, rest of the statements and assignment: if the
assignment fits the run from the index over the statement and the rest, it fits the run from
the next index over the rest. Proof sketch: offset {lit}`k` of the rest is offset {lit}`k + 1`
of the whole list, and the two positions are equal. -/
theorem ClockFits.tail {clock : Option Clock} {index : Nat} {statement : Resolved.Statement}
    {rest : List Resolved.Statement} {assignment : Clock}
    (fits : ClockFits clock index (statement :: rest) assignment) :
    ClockFits clock (index + 1) rest assignment := by
  intro offset later value found valued
  have shifted : index + 1 + offset = index + (offset + 1) := by omega
  rw [shifted] at valued ⊢
  exact fits (offset + 1) later value found valued

/-- For every optional clock, clock assignment and list of resolved statements: if the clock,
when the run has one, is the assignment, then {name}`scriptClock` of the assignment and the
statements fits the run with the clock from index 0 over the statements. So
{name}`runSqlAt` of the assignment and the run with the assignment, or without a clock, give
each statement that runs the same clock value. Proof sketch: at each offset, both {name}`scriptClock` and
{name}`statementClock` give the assignment's value to a statement that reads the clock and 0
to every other statement. -/
theorem ClockFits.scriptClock {clock : Option Clock} {assignment : Clock} (statements : List Resolved.Statement)
    (same : ∀ given ∈ clock, given = assignment) :
    ClockFits clock 0 statements (Model.scriptClock assignment statements) := by
  intro offset statement value found valued
  simp only [Nat.zero_add] at valued ⊢
  cases clock with
  | none => cases reads : statement.readsClock <;> simp_all [Model.scriptClock, statementClock]
  | some given =>
    cases same given rfl
    cases reads : statement.readsClock <;> simp_all [Model.scriptClock, statementClock]

/-- For every context, optional clock, index, connection, statement and list of values: if the
step without a clock does not end the run with the reason {name}`clockUnmodeled`, the step with
the clock is the step without a clock. So a clock changes only the steps of statements that read
it. Proof sketch: a statement that reads the clock ends the step without a clock with
{name}`clockUnmodeled`; every other statement runs with the value 0 in both steps
({name}`statementClock`). -/
theorem runScriptStep_of_ne_clockUnmodeled {context : ResolveContext} {clock : Option Clock} {index : Nat}
    {connection : Connection} {statement : Syntax.Statement} {parameters : List Value}
    (clockFree : runScriptStep context none index connection statement parameters ≠ .ended clockUnmodeled) :
    runScriptStep context clock index connection statement parameters =
      runScriptStep context none index connection statement parameters := by
  unfold runScriptStep runScriptStepWith at clockFree ⊢
  cases resolution : resolveStatement context connection.resolveState statement with
  | error restriction => rfl
  | ok pair =>
    obtain ⟨resolved, after⟩ := pair
    simp only [resolution] at clockFree ⊢
    cases reads : resolved.readsClock
    · simp only [statementClock, reads, Bool.false_eq_true, ite_false]
    · simp [statementClock, reads] at clockFree

end Belay.Sqlite.Model
