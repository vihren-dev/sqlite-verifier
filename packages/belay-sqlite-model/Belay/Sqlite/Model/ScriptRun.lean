import Belay.Sqlite.Model.Output
import Belay.Sqlite.Model.Resolution.Resolve
import Belay.Sqlite.Model.SqlExecution

set_option doc.verso true

/-! A run of statement syntax that continues after an error (ADR 0017, D3, amended
2026-10-22). It resolves each statement when it runs, against the state of the connection at
that time: the catalog of the visible database, the catalog at {lit}`BEGIN` of an open
transaction, and the settings of {lit}`PRAGMA foreign_keys` and {lit}`PRAGMA recursive_triggers`.
It runs the statement with
{name}`Belay.Sqlite.Model.runStatement` and {name}`Belay.Sqlite.Model.advanceRun`, gives its
{name}`Belay.Sqlite.Model.Output`, and goes on with the next statement after an error, as an
application that sends one statement at a time does. The run takes an optional clock: a
statement that reads the clock runs with the clock's value at its index, or ends the run when
the run has no clock. A statement that the model does not describe ends the run.
{lit}`ScriptRunLaws.lean` relates the run to {name}`Belay.Sqlite.Model.runSqlFrom`. -/

namespace Belay.Sqlite.Model

/-- The state of a connection between two statements: the visible database, the snapshot of
an open transaction, a clock assignment and the counters ({name}`SqlState`), and the settings of
{lit}`PRAGMA foreign_keys` and {lit}`PRAGMA recursive_triggers`. For example,
{lean}`({ state := { database := {} } } : Connection)` is an idle connection to the empty
database with both settings off. The run of this file takes
its clock as an argument and does not read the clock assignment of the state; the laws of
{lit}`ScriptRunLaws.lean` compare the run with {name}`runSqlFrom` on the state, which reads it. -/
structure Connection where
  /-- The database, the open transaction, the clock assignment (which the run carries without
  a change) and the counters (which each statement that writes changes). -/
  state : SqlState
  /-- Whether foreign keys are on; off by default, as in SQLite. -/
  foreignKeys : Bool := false
  /-- Whether recursive triggers are on; off by default, as in SQLite. -/
  recursiveTriggers : Bool := false

/-- The state of resolution for the next statement: the catalog of the visible database, the
catalog of the snapshot of an open transaction, and the settings. -/
def Connection.resolveState (connection : Connection) : ResolveState :=
  { catalog := connection.state.database.catalog, saved := connection.state.snapshot.map (·.catalog),
    foreignKeys := connection.foreignKeys, recursiveTriggers := connection.recursiveTriggers }

/-- The connection after a statement that stopped with the outcome: an open transaction stays
open with its snapshot, as in SQLite; a failure outside a transaction, also after the rollback
of {lit}`OR ROLLBACK` ({name}`SqlState.failed`), leaves the connection idle. The database is
the outcome's, and the settings are those of the resolution state {lit}`after` the statement, and the counters are
those after the {lit}`counts` of the statement, which a failed write also gives (ADR 0024, D2). -/
def Connection.afterError (connection : Connection) (after : ResolveState) (counts : Counts) : Outcome → Connection
  | .success database | .failure _ _ database =>
    { state := { connection.state with
                 database := database, snapshot := none, counters := connection.state.counters.apply counts },
      foreignKeys := after.foreignKeys, recursiveTriggers := after.recursiveTriggers }
  | .pending persisted visible _ =>
    { state := { connection.state with
                 database := visible, snapshot := some persisted, counters := connection.state.counters.apply counts },
      foreignKeys := after.foreignKeys, recursiveTriggers := after.recursiveTriggers }

/-- The connection after a statement's transition: the state of a transition that continues,
with the settings of the resolution state {lit}`after` the statement, or
{name}`Connection.afterError` of a halt with the counts of the statement. -/
def Connection.afterStep (connection : Connection) (after : ResolveState) (counts : Counts) : SqlTransition → Connection
  | .next state => { state, foreignKeys := after.foreignKeys, recursiveTriggers := after.recursiveTriggers }
  | .halt outcome => connection.afterError after counts outcome

/-- The reason of a statement that reads the clock in a run without a clock. -/
def clockUnmodeled : String :=
  "the statement reads the clock, which this run does not describe; write the time as a literal value"

/-- The reason of a statement that calls a counter function that the connection does not know
(ADR 0024, D2): it names the function and says how to make the value known. -/
def counterUnknownReason (kind : CounterKind) : String :=
  let function := match kind with
    | .changes => "changes()"
    | .totalChanges => "total_changes()"
    | .lastInsertRowid => "last_insert_rowid()"
  s!"the statement calls {function}, whose value on this connection the run does not know; start the run on a new connection"

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

/-- The step of a statement that ran on the connection with the values bound to its parameters,
as resolved, with the resolution state {lit}`after` it, its clock value, its run and its
transition: {name}`Output.ofStep` with the values; an output {name}`Output.unmodeled` ends the run,
and every other output continues with {name}`Connection.afterStep` of the transition and the counts
of the run. -/
def ranScriptStep (parameters : List Value) (connection : Connection) (resolved : Resolved.Statement)
    (after : ResolveState) (value : Int) (run : StatementRun) (transition : SqlTransition) : RunStep :=
  match Output.ofStep value parameters resolved connection.state run transition with
  | .unmodeled reason => .ended reason
  | output@(.rows _) | output@(.done _) | output@(.error _) | output@(.oneOf _) =>
    .continued output (connection.afterStep after run.counts transition)

/-- The steps of one statement of a run up to its transition, with the value to give when the
run ends at the statement ({lit}`ended`, with the reason) and when the statement runs
({lit}`ran`, with the resolved statement, the resolution state after it,
its clock value, its run and its transition). {lit}`runScriptStep` is this function with
{name}`RunStep.ended` and {name}`ranScriptStep`. A caller that needs more of a step than its
output, such as its transition, gives its own values and takes the same steps:

* resolve the statement against {name}`Connection.resolveState`; a restriction ends the run with
  its reason ({name}`NodeRestriction.reason`);
* take its clock value ({name}`statementClock`); a statement that reads the clock in a run
  without a clock ends the run with {name}`clockUnmodeled`;
* take the first counter that the statement reads and the connection does not know
  ({name}`Counters.firstUnknown`); the run ends with {name}`counterUnknownReason`;
* run it with the values at the clock value ({name}`SqlState.statementRun`); a statement that fails
  the support check ends the run with {name}`unmodeledHere`;
* otherwise give {lit}`ran` of the transition of {name}`advanceRun` at the index. -/
def runScriptStepWith {α : Type} (ended : String → α) (ran : Resolved.Statement → ResolveState → Int → StatementRun → SqlTransition → α)
    (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statement : Syntax.Statement) (parameters : List Value) : α :=
  match resolveStatement context connection.resolveState statement with
  | .error restriction => ended restriction.reason
  | .ok (resolved, after) =>
    match statementClock clock index resolved with
    | none => ended clockUnmodeled
    | some value => match connection.state.counters.firstUnknown resolved.counterReads with
      | some kind => ended (counterUnknownReason kind)
      | none =>
        let run := connection.state.statementRun value parameters resolved
        if !run.ready then ended unmodeledHere
        else ran resolved after value run (advanceRun index resolved connection.state run)

/-- Run one statement with the values bound to its parameters at its zero-based index on the
connection, with an optional clock: the steps of {name}`runScriptStepWith`, then
{name}`ranScriptStep` for a statement that runs. A restriction, a statement that reads the
clock in a run without a clock, a statement that reads an unknown counter, a statement that
fails the support check, and an output {name}`Output.unmodeled` end the run. -/
def runScriptStep (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (statement : Syntax.Statement) (parameters : List Value) : RunStep :=
  runScriptStepWith .ended (ranScriptStep parameters connection) context clock index connection statement parameters

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
