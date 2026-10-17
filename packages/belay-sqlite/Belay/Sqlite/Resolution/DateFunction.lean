import Belay.Sqlite.Declarations

set_option doc.verso true

/-! The date and time functions that a resolved expression calls (ADR 0012, amendment 5,
slice 6f). -/

namespace Belay.Sqlite.Resolved

/-- A date and time function of ADR 0012, amendment 5, slice 6f. Each takes one time value
or none, which is {lit}`now`; {lit}`strftime` takes its format first. -/
inductive DateFunction where
  /-- {lit}`date(time-value)`: the text {lit}`YYYY-MM-DD`. -/
  | date
  /-- {lit}`time(time-value)`: the text {lit}`HH:MM:SS`. -/
  | time
  /-- {lit}`datetime(time-value)`: the text {lit}`YYYY-MM-DD HH:MM:SS`. -/
  | datetime
  /-- {lit}`julianday(time-value)`: the Julian day number as a REAL. -/
  | julianday
  /-- {lit}`unixepoch(time-value)`: the Unix time in seconds as an INTEGER. -/
  | unixepoch
  /-- {lit}`strftime(format, time-value)`: the time value as the format gives it. -/
  | strftime
  deriving Repr, DecidableEq

end Belay.Sqlite.Resolved
