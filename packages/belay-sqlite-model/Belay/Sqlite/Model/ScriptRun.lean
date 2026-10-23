import Belay.Sqlite.Model.Output
import Belay.Sqlite.Model.Resolution.Resolve
import Belay.Sqlite.Model.SqlExecution

set_option doc.verso true

/-! A run of statement syntax that continues after an error (ADR 0017, D3, amended
2026-10-22). It resolves each statement when it runs, against the state of the connection at
that time: the catalog of the visible database, the catalog at {lit}`BEGIN` of an open
transaction, and the setting of {lit}`PRAGMA foreign_keys`. It runs the statement with
{name}`Belay.Sqlite.Model.runStatement` and {name}`Belay.Sqlite.Model.advanceWith`, gives its
{name}`Belay.Sqlite.Model.Output`, and goes on with the next statement after an error, as an
application that sends one statement at a time does. The run takes an optional clock: a
statement that reads the clock runs with the clock's value at its index, or ends the run when
the run has no clock. A statement that the model does not describe ends the run.
{lit}`ScriptRunLaws.lean` relates the run to {name}`Belay.Sqlite.Model.runSqlFrom`. -/

namespace Belay.Sqlite.Model

/-- The state of a connection between two statements: the visible database, the snapshot of
an open transaction and a clock assignment ({name}`SqlState`), and the setting of
{lit}`PRAGMA foreign_keys`. For example, {lean}`({ state := { database := {} } } : Connection)`
is an idle connection to the empty database with foreign keys off. The run of this file takes
its clock as an argument and does not read the clock assignment of the state; the laws of
{lit}`ScriptRunLaws.lean` compare the run with {name}`runSqlFrom` on the state, which reads it. -/
structure Connection where
  /-- The database, the open transaction and the clock assignment, which the run carries
  without a change. -/
  state : SqlState
  /-- Whether foreign keys are on; off by default, as in SQLite. -/
  foreignKeys : Bool := false

/-- The state of resolution for the next statement: the catalog of the visible database, the
catalog of the snapshot of an open transaction, and the setting. -/
def Connection.resolveState (connection : Connection) : ResolveState :=
  { catalog := connection.state.database.catalog, saved := connection.state.snapshot.map (·.catalog),
    foreignKeys := connection.foreignKeys }

/-- The connection after a statement that stopped with the outcome: an open transaction stays
open with its snapshot, as in SQLite; a failure outside a transaction, also after the rollback
of {lit}`OR ROLLBACK` ({name}`SqlState.failed`), leaves the connection idle. The database is
the outcome's. -/
def Connection.afterError (connection : Connection) (foreignKeys : Bool) : Outcome → Connection
  | .success database | .failure _ _ database =>
    { state := { connection.state with database, snapshot := none }, foreignKeys }
  | .pending persisted visible _ =>
    { state := { connection.state with database := visible, snapshot := some persisted }, foreignKeys }

/-- The connection after a statement's transition: the state of a transition that continues,
with the setting that the statement leaves, or {name}`Connection.afterError` of a halt. -/
def Connection.afterStep (connection : Connection) (foreignKeys : Bool) : SqlTransition → Connection
  | .next state => { state, foreignKeys }
  | .halt outcome => connection.afterError foreignKeys outcome

/-- The reason of a statement that reads the clock in a run without a clock. -/
def clockUnmodeled : String :=
  "the statement reads the clock, which this run does not describe; write the time as a literal value"

/-- The clock value with which a resolved statement at a zero-based index runs: the value of
the clock at the index for a statement that reads the clock
({name}`Resolved.Statement.readsClock`), and 0 for every other statement, as
{name}`scriptClock` gives it. It is {lean}`(none : Option Int)` for a statement that reads the
clock in a run without a clock. Use {lean}`(none : Option Clock)` as the clock when the run
must not read one. -/
def statementClock (clock : Option Clock) (index : Nat) (statement : Resolved.Statement) : Option Int :=
  if statement.readsClock then clock.map (· index) else some 0

/-- What one statement of a run gives: its output and the connection after it, or the reason
why the run ends at it. -/
inductive RunStep where
  /-- The statement ran, with its output, which is not {name}`Output.unmodeled`. -/
  | continued (output : Output) (next : Connection)
  /-- The model does not describe the statement; the run ends. -/
  | ended (reason : String)

/-- Run one statement with the values bound to its parameters at its zero-based index on the
connection, with an optional clock:

* resolve it against {name}`Connection.resolveState`; a restriction ends the run with its reason
  ({name}`NodeRestriction.reason`);
* take its clock value ({name}`statementClock`); a statement that reads the clock in a run
  without a clock ends the run with {name}`clockUnmodeled`;
* run it with the values at the clock value ({name}`runStatement`); a statement that fails the
  support check ends the run;
* advance the connection with {name}`advanceWith`, and give {name}`Output.ofStep` with the
  values; an output
  {name}`Output.unmodeled` ends the run;
* the connection after it is {name}`Connection.afterStep` of the transition. -/
def runScriptStep (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statement : Syntax.Statement) (parameters : List Value) : RunStep :=
  match resolveStatement context connection.resolveState statement with
  | .error restriction => .ended restriction.reason
  | .ok (resolved, after) =>
    match statementClock clock index resolved with
    | none => .ended clockUnmodeled
    | some value =>
      let run := runStatement value parameters resolved connection.state.database
      if !run.ready then .ended unmodeledHere
      else
        let transition := advanceWith index resolved connection.state run.effect
        match Output.ofStep value parameters resolved connection.state transition with
        | .unmodeled reason => .ended reason
        | output@(.rows _) | output@(.done _) | output@(.error _) | output@(.oneOf _) =>
          .continued output (connection.afterStep after.foreignKeys transition)

/-- The result of a run: the output of each statement that ran, in order, and the connection
at the end. -/
structure ScriptRun where
  /-- One output for each statement that ran; the last is {name}`Output.unmodeled` when the
  run ended early. -/
  outputs : List Output
  /-- The connection after the last statement that ran, or at the start of the statement
  that ended the run. -/
  connection : Connection

/-- Run statements in order, each with the values bound to its parameters, from a zero-based
index on the connection, with an optional clock for each index ({name}`runScriptStep`): the
run goes on after an error and ends at a statement that the model does not describe, whose
output is {name}`Output.unmodeled`. With {lean}`(none : Option Clock)`, a statement that reads
the clock ends the run. -/
def runScriptFrom (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection) :
    List (Syntax.Statement × List Value) → ScriptRun
  | [] => { outputs := [], connection }
  | (statement, parameters) :: rest => match runScriptStep context clock index connection statement parameters with
    | .ended reason => { outputs := [.unmodeled reason], connection }
    | .continued output next =>
      let later := runScriptFrom context clock (index + 1) next rest
      { later with outputs := output :: later.outputs }

end Belay.Sqlite.Model
