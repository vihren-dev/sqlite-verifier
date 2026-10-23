import Belay.Sqlite.Script

set_option doc.verso true

/-! The surface's programs (ADR 0017, D1, the row of S3): a program sends statements one at a
time and can use the output of each statement to choose what it sends next. A program is data:
{lit}`Sql.exec` holds one statement with its values and the function that gives the rest of the
program from the statement's output. The {lit}`Monad` instance gives {lit}`do` notation, and
{lit}`send` sends the statements of a script. {lit}`ProgramRun.lean` runs programs. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- A program that sends statements to a database and gives a value of type {lit}`α`. For
example, {lean}`(Sql.pure 1 : Sql Nat)` sends no statement and gives 1. Lean cannot decide
whether two programs are equal, because the rest of a program is a function; the result of a
run is data, and {lit}`decide` can compare it. -/
inductive Sql (α : Type) where
  /-- The program that sends no statement and gives the value. -/
  | pure (value : α)
  /-- The program that sends the statement with the values bound to its parameters, then runs
  the program that {lit}`rest` gives for the statement's output. A run gives {lit}`rest` only
  the outputs that do not end a run: {name}`Output.unmodeled` ends the program. -/
  | exec (statement : Syntax.Statement) (values : List Value) (rest : Output → Sql α)

namespace Sql

/-- The program, then the program that the function gives for its value: each statement of
the first program, in order, and then the statements of the second. -/
def bind {α β : Type} : Sql α → (α → Sql β) → Sql β
  | .pure value, next => next value
  | .exec statement values rest, next => .exec statement values fun output => (rest output).bind next

/-- The program with the function applied to its value: the same statements in the same
order. -/
def map {α β : Type} (function : α → β) : Sql α → Sql β
  | .pure value => .pure (function value)
  | .exec statement values rest => .exec statement values fun output => (rest output).map function

/-- The programs form a monad, so a program is written in {lit}`do` notation: {lit}`pure` is
{name}`Sql.pure`, {lit}`>>=` is {name}`Sql.bind`, and {lit}`<$>` is {name}`Sql.map`. -/
instance : Monad Sql where
  pure := Sql.pure
  bind := Sql.bind
  map := Sql.map

end Sql

/-- The program that sends the statements in order, each with its values; its value is their
outputs, one for each statement. -/
def sendStatements : List (Syntax.Statement × List Value) → Sql (List Output)
  | [] => .pure []
  | (statement, values) :: rest => .exec statement values fun output => (sendStatements rest).map (output :: ·)

/-- {lit}`send s`: the program that sends each statement of script {lit}`s` in order, with its
values; its value is the outputs of the statements. Its run is the run of the script
({lit}`Sql.runFrom_send`). For example, {lit}`send (sql r"SELECT 1")` gives
{lean}`[Output.rows [[.integer 1]]]`. -/
def send (script : Script) : Sql (List Output) := sendStatements script.statements

/-- A script on its own line in a {lit}`do` block is sent ({name}`send`), and its value is
dropped. -/
instance : Coe Script (Sql PUnit) := ⟨fun script => (send script).map fun _ => ⟨⟩⟩

end Belay.Sqlite
