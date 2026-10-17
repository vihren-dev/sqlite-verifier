import Belay.Sqlite.Resolution.QueryForm

set_option doc.verso true

/-! The clock forms of a resolved expression (ADR 0012, amendment 5, slice 6e2): which
expressions read the statement's clock, and the expression at a clock value, in which each
time keyword is the literal text that SQLite gives for it ({lit}`TimeKeyword.value`). The
execution applies the clock value of each statement before it evaluates the statement, so
evaluation never reads the clock. -/

namespace Belay.Sqlite.Resolved

/-- The time keyword of a keyword as written, which SQLite compares without ASCII case:
{lit}`CURRENT_TIME`, {lit}`CURRENT_DATE`, or else {lit}`CURRENT_TIMESTAMP`, the only other
keyword that the frontend maps to {lit}`Syntax.Expr.currentTime`. -/
def timeKeywordNamed (keyword : String) : TimeKeyword :=
  match keyword.toLower with
  | "current_time" => .time
  | "current_date" => .date
  | _ => .timestamp

mutual
/-- Whether the expression reads the statement's clock: it has a time keyword. -/
def Expr.readsClock : Expr → Bool
  | .column _ | .literal _ => false
  | .now _ => true
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .coalesce left right =>
    left.readsClock || right.readsClock
  | .not operand | .isNull operand _ | .cast _ operand => operand.readsClock
  | .json _ arguments | .arguments arguments => arguments.readsClock

/-- Whether an argument reads the statement's clock. -/
def Arguments.readsClock : Arguments → Bool
  | .nil => false
  | .cons head tail => head.readsClock || tail.readsClock
end

mutual
/-- The expression at a clock value: each time keyword becomes the literal of its value at
the clock ({name}`TimeKeyword.value`); everything else is unchanged. -/
def Expr.atClock (clock : Int) : Expr → Expr
  | .now keyword => .literal (keyword.value clock)
  | .column position => .column position
  | .literal value => .literal value
  | .compare operator left right => .compare operator (left.atClock clock) (right.atClock clock)
  | .and left right => .and (left.atClock clock) (right.atClock clock)
  | .or left right => .or (left.atClock clock) (right.atClock clock)
  | .not operand => .not (operand.atClock clock)
  | .isNull operand negated => .isNull (operand.atClock clock) negated
  | .arithmetic operator left right => .arithmetic operator (left.atClock clock) (right.atClock clock)
  | .cast affinity operand => .cast affinity (operand.atClock clock)
  | .coalesce first rest => .coalesce (first.atClock clock) (rest.atClock clock)
  | .json function arguments => .json function (arguments.atClock clock)
  | .arguments arguments => .arguments (arguments.atClock clock)

/-- The arguments at a clock value ({name}`Expr.atClock`). -/
def Arguments.atClock (clock : Int) : Arguments → Arguments
  | .nil => .nil
  | .cons head tail => .cons (head.atClock clock) (tail.atClock clock)
end

/-- For every clock value and expression that does not read the clock, the expression at
the clock value is the expression. Proof sketch: induction over the mutual expression and
argument types. -/
theorem Expr.atClock_of_readsClock (clock : Int) (expression : Expr) (free : expression.readsClock = false) :
    expression.atClock clock = expression := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.readsClock = false → arguments.atClock clock = arguments) <;>
    simp_all [Expr.readsClock, Expr.atClock, Arguments.readsClock, Arguments.atClock]

end Belay.Sqlite.Resolved
