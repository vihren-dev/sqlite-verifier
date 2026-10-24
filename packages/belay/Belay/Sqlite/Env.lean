import Lean.Elab.Term
import Belay.Sqlite.Model

set_option doc.verso true

/-! The execution environment of a run (ADR 0017, D3, its clock amendment): the inputs of a run
other than the database. It holds the clock and the counters of the connection; the runs use the
pinned profile. A statement that reads the clock, such as {lit}`CURRENT_TIMESTAMP` or
{lit}`date('now')`, runs with the clock's time, and ends the run when the environment has no clock.
{lit}`clockAt "2026-10-20 12:00:00"` gives that time to every statement, and the text is
checked where it is written. A statement that calls {lit}`changes()`, {lit}`total_changes()` or
{lit}`last_insert_rowid()` reads the counter from the connection, and ends the run when the
environment does not know that counter; {lit}`Env.newConnection` knows all three (ADR 0024). -/

namespace Belay.Sqlite

open Lean Elab Term

export Belay.Sqlite.Model (Clock clockUnmodeled Counters Counters.newConnection CounterKind counterUnknownReason)

/-- The inputs of a run other than the database. For example, {lit}`Env.default` has no clock and
knows no counter, {lit}`clockAt "2026-10-20 12:00:00"` gives that time to every statement, and
{lit}`Env.newConnection` is the environment of a new connection. Use {lit}`Env.default` when no
statement reads the clock or a counter that the script does not set first. -/
structure Env where
  /-- The clock: for each statement of a run, by its zero-based index, the time in Julian-day
  milliseconds, as SQLite's {lit}`xCurrentTimeInt64` gives it. Without a clock, a statement that
  reads the clock gives {name}`Belay.Sqlite.Model.Output.unmodeled` with the reason {name}`clockUnmodeled`, and the
  run ends at it. -/
  clock : Option Clock := none
  /-- The counters of the connection at the start of the run (ADR 0024). Each counter that the
  environment does not know is unknown: a statement that calls the function of an unknown counter
  gives {name}`Belay.Sqlite.Model.Output.unmodeled` with the reason
  {name}`Belay.Sqlite.Model.counterUnknownReason`, and the run ends at it. A write of the run sets
  the counters that it changes, so {lit}`INSERT INTO t VALUES (1); SELECT last_insert_rowid()`
  gives the rowid of the row also from unknown counters. -/
  counters : Counters := {}

/-- The environment of a run when the run does not name one: no clock. -/
def Env.default : Env := {}

/-- The environment of a new connection: each counter is 0, as in SQLite
({name}`Belay.Sqlite.Model.Counters.newConnection`), and there is no clock. For example,
{lit}`SELECT changes()` gives 0 in it. Add a clock with {lit}`{ Env.newConnection with clock := ... }`
or {lit}`{ clockAt "2026-10-20 12:00:00" with counters := Counters.newConnection }`. -/
def Env.newConnection : Env := { counters := Counters.newConnection }

/-- The environment whose clock gives the time, in Julian-day milliseconds, to every statement.
For example, {lean}`Env.atTime 212602449600000` is 2025-01-01 00:00:00. {lit}`clockAt` gives it
from a text. -/
def Env.atTime (julianMilliseconds : Int) : Env := { clock := some fun _ => julianMilliseconds }

/-- The time of the text in Julian-day milliseconds, as SQLite's date functions read a time
value without modifiers ({name}`Belay.Sqlite.Model.DateTime.ofArguments`): a date, a date and a
time, a time on 2000-01-01, or a Julian day number, each in UTC. It is
{lean}`(none : Option Int)` for a text that the functions do not read as a time, for a time
after 9999-12-31 23:59:59.999 or before the first Julian day ({name}`Belay.Sqlite.Model.validJulianDay`),
and for {lit}`now`, which reads the clock. -/
def timeOfText? (text : String) : Option Int :=
  (Belay.Sqlite.Model.DateTime.ofArguments 0 [.text text.toUTF8.toList]).map
    (·.computeJulianDay.julianMilliseconds)

/-- {lit}`clockAt "TIME"`: the environment whose clock gives the time of the text to every
statement ({name}`Env.atTime` of {name}`timeOfText?`). For example,
{lit}`clockAt "2026-10-20 12:00:00"`. A text that SQLite's date functions do not read as a time
is an error at the text. -/
syntax:max (name := clockAtTerm) "clockAt " str : term

/-- The message of a text that is not a time. -/
def notATimeMessage (text : String) : String :=
  s!"SQLite's date functions do not read the text {repr text} as a time; write a date and a time in UTC, such as \"2026-10-20 12:00:00\""

/-- Elaborate {lit}`clockAt "TIME"` to {name}`Env.atTime` of the time of the text, which the
elaborator computes ({name}`timeOfText?`), or give {name}`notATimeMessage` at the text. -/
@[term_elab clockAtTerm]
def elabClockAt : TermElab := fun term _ => do
  let literal := term[1]
  let some text := literal.isStrLit? | throwUnsupportedSyntax
  match timeOfText? text with
  | some time => return mkApp (mkConst ``Env.atTime) (toExpr time)
  | none => throwErrorAt literal (notATimeMessage text)

end Belay.Sqlite
