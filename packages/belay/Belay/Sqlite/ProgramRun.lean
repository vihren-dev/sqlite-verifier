import Belay.Sqlite.Program
import Belay.Sqlite.Env
import Belay.Sqlite.Run

set_option doc.verso true

/-! The runs of programs and scripts on a database (ADR 0017, D1 and D3; ADR 0022, D5, amended):
{lit}`Sql.run p db` sends each statement of program {lit}`p` as one statement of the model's
run, at the next index, on the connection that the earlier statements left, and gives the
statement's output to the rest of the program. A statement whose output is
{lit}`Output.unmodeled` ends the program. The run decides {lit}`Database.Valid` for the database
at its end, and the decision is the proof of the {lit}`Database` that it gives. {lit}`db.run`
takes a program or a script; a script is the program {lit}`send s`. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- What the model's run of a program reached, without the check of the database at its end:
the outputs and the connection, as for a script, and the program's value, which is none when the
run ended with {name}`Output.unmodeled`. -/
structure SqlRun (α : Type) extends ScriptRun where
  /-- The program's value, or none when a statement ended the run. -/
  value : Option α

/-- Run the program from a zero-based index on the connection, with an optional clock: each
statement runs as one step of the model's run ({name}`Belay.Sqlite.Model.runScriptStep`); its
output goes to the rest of the program, which runs from the next index on the connection after
the statement. A statement that ends the run gives {name}`Output.unmodeled` with the reason, and
the rest of the program does not run. -/
def Sql.runFrom {α : Type} (clock : Option Clock) (index : Nat) (connection : Connection) : Sql α → SqlRun α
  | .pure value => { outputs := [], connection, value := some value }
  | .exec statement values rest =>
    match runScriptStep runContext clock index connection statement values with
    | .ended reason => { outputs := [.unmodeled reason], connection, value := none }
    | .continued output next =>
      let later := (rest output).runFrom clock (index + 1) next
      { later with outputs := output :: later.outputs }

/-- The result of a run of a program. -/
structure Run (α : Type) where
  /-- The program's value: none when a statement ended the run with {name}`Output.unmodeled`,
  or when the database at the end is not valid. -/
  value : Option α
  /-- One output for each statement that ran, in order; the last is {name}`Output.unmodeled`
  when the run ended early, or when the database at its end is not valid. -/
  outputs : List Output
  /-- The database that the connection sees at the end, or {name}`Run.start` when the
  database at the end is not valid. -/
  db : Database
  /-- The database at the start of the run. -/
  start : Database
  /-- The database at {lit}`BEGIN` of a transaction that is open at the end, or
  {lean}`(none : Option Database.Raw)` when no transaction is open. -/
  transaction : Option Database.Raw
  /-- Whether {lit}`PRAGMA foreign_keys` is on at the end. -/
  foreignKeys : Bool
  /-- Whether {lit}`PRAGMA recursive_triggers` is on at the end. -/
  recursiveTriggers : Bool

/-- The reason of the output that ends a run whose database at its end is not valid. -/
def invalidReason : String :=
  "the database at the end of the run is not valid: a NOT NULL, CHECK, type, key or rowid " ++
    "constraint fails; the run keeps the database at its start. To see the database that the " ++
    "run reached, run the script with Database.Raw.run on db.raw"

/-- The run that the model's result gives from the start database, with the check: when the
database at the end is valid ({name}`Database.Valid`), the decision is the proof of the
{name}`Database` that the run gives, with the result's value; otherwise the value is none, the
outputs end with {name}`Output.unmodeled`, with {name}`invalidReason` unless the model's run
ended already, and the run keeps the start database, idle with both settings off. -/
def Run.checked {α : Type} (start : Database) (result : SqlRun α) : Run α :=
  if valid : result.connection.state.database.Valid Profile.pinned then
    { value := result.value, outputs := result.outputs, db := ⟨_, valid⟩, start,
      transaction := result.connection.state.snapshot, foreignKeys := result.connection.foreignKeys,
      recursiveTriggers := result.connection.recursiveTriggers }
  else
    { value := none, outputs := if result.ended then result.outputs else result.outputs ++ [.unmodeled invalidReason],
      db := start, start, transaction := none, foreignKeys := false, recursiveTriggers := false }

/-- Run the program on the database in the environment, from the idle connection to the
database, with the check of the database at the end ({name}`Run.checked` of
{name}`Sql.runFrom`). Use {name}`Env.default`, the value when {lit}`env` is not given, when no
statement reads the clock. -/
def Sql.run {α : Type} (program : Sql α) (db : Database) (env : Env := Env.default) : Run α :=
  Run.checked db (program.runFrom env.clock 0 db.raw.connection)

/-- The things that {lit}`db.run` runs: a program of type {lit}`Sql α` itself (the default
instance, so that a {lit}`do` block is a program), and a script, which is the program
{name}`send` of it. -/
class Runnable (σ : Type) (α : outParam Type) where
  /-- The program of the thing. -/
  toSql : σ → Sql α

/-- A program is the program that {lit}`db.run` runs. -/
@[default_instance] instance {α : Type} : Runnable (Sql α) α := ⟨id⟩

/-- A script is the program that sends its statements ({name}`send`). -/
instance : Runnable Script (List Output) := ⟨send⟩

/-- Run the program or the script on the database in the environment ({name}`Sql.run`), with
the database first, so that a {lit}`do` block needs no parentheses: {lit}`db.run do ...`.
For example, an UPDATE that changes one row, then a query, give the outputs
{lit}`[done 1, rows [[1, 10]]]`. -/
def Database.run {σ α : Type} [Runnable σ α] (db : Database) (program : σ) (env : Env := Env.default) : Run α :=
  (Runnable.toSql program).run db env

/-- Run the script on the database up to and including its first statement that fails
({name}`Output.isError`), as {lit}`sqlite3_exec` does: the run of the statements before the
first error and of the failed statement, or of the whole script without an error. -/
def Script.runUntilError (script : Script) (db : Database) : Run (List Output) :=
  match (db.run script).outputs.findIdx? Output.isError with
  | some position => db.run (⟨script.statements.take (position + 1)⟩ : Script)
  | none => db.run script

end Belay.Sqlite
