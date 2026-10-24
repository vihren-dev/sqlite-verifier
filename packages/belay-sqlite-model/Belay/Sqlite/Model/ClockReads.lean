import Belay.Sqlite.Model.Resolution.ExprAny
import Belay.Sqlite.Model.Date.Functions
import Belay.Sqlite.Model.Date.Parse

set_option doc.verso true

/-! Which resolved expressions read the statement's clock (ADR 0012, amendment 5, slice
6e2; ADR 0013, D6). Evaluation takes the clock value as a parameter; this classifier
tells which expressions can depend on it, so that a script without them has one outcome
for every clock assignment ({lit}`SqlExecution.lean`). -/

namespace Belay.Sqlite.Model.Resolved

/-- Whether a time value reads the clock in {lit}`parseDateOrTime`: text or a BLOB whose
bytes before the first NUL ({name}`bytesBeforeNul`) are {lit}`now`, {lit}`subsec` or
{lit}`subsecond` without ASCII case ({name}`equalsKeyword`). A BLOB counts because SQLite
reads it as its bytes ({lit}`sqlite3_value_text`). Every other value gives the same date
and time at every clock value. -/
def namesClock : Value → Bool
  | .text bytes | .blob bytes =>
    let text := bytesBeforeNul bytes
    equalsKeyword text nowKeyword || equalsKeyword text subsecKeyword || equalsKeyword text subsecondKeyword
  | .null | .integer _ | .real _ => false

/-- The time value argument of a call, if any: the second argument of {lit}`strftime`, whose
first argument is the format, and the first argument of each other function. -/
def DateFunction.timeValue : DateFunction → Arguments → Option Expr
  | .strftime, .cons _ (.cons value _) => some value
  | .strftime, .cons _ .nil | .strftime, .nil => none
  | .date, arguments | .time, arguments | .datetime, arguments | .julianday, arguments
  | .unixepoch, arguments => match arguments with
    | .cons value _ => some value
    | .nil => none

/-- Whether a call may read {lit}`now` from the statement's clock: it has no time value,
or its time value is not a literal that the model sees is no clock form
({name}`namesClock`). A time value from a column or another expression may be
{lit}`now`, so it reads the clock, and so may a parameter's value. -/
def DateFunction.readsNow (function : DateFunction) (arguments : Arguments) : Bool :=
  match function.timeValue arguments with
  | some (.literal value) => namesClock value
  | none | some (.column _) | some (.compare ..) | some (.and ..) | some (.or ..) | some (.not _)
  | some (.isNull ..) | some (.arithmetic ..) | some (.cast ..) | some (.coalesce ..) | some (.json ..)
  | some (.now _) | some (.date ..) | some (.scalar ..) | some (.exists ..) | some (.inQuery ..) | some (.inList ..) | some (.aggregateValue _)
  | some (.subquery _) | some (.parameter _) | some (.counter _) => true

/-- Whether the expression itself reads the clock; its parts are not inspected: a time
keyword, or a date and time function that may read {lit}`now`
({name}`DateFunction.readsNow`). Use it with {name}`Expr.any`. A subquery's own expressions
are in the statement's list of subqueries, which {lit}`Statement.clockExpressions` reads. -/
def Expr.readsClockHere : Expr → Bool
  | .now _ => true
  | .date function arguments => function.readsNow arguments
  | .column _ | .literal _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic ..
  | .cast .. | .coalesce .. | .json .. | .scalar .. | .exists .. | .inQuery .. | .subquery _ | .inList .. | .aggregateValue _
  | .parameter _ | .counter _ => false

/-- Whether the expression or one of its parts reads the clock
({name}`Expr.readsClockHere`). -/
def Expr.readsClock (expression : Expr) : Bool := expression.any Expr.readsClockHere

end Belay.Sqlite.Model.Resolved
