import Belay.Sqlite.Model.SqlState
import Belay.Sqlite.Model.RowDelete
import Belay.Sqlite.Model.UpsertRun
import Belay.Sqlite.Model.StatementRun
import Belay.Sqlite.Model.PlainCounts
import Belay.Sqlite.Model.JsonReady
import Belay.Sqlite.Model.StatementClock
import Belay.Sqlite.Model.StatementCounterReads

set_option doc.verso true

/-! The run of one resolved statement (ADR 0013, D8): its effect, its support check and its
counts. The transitions of script-directed SQL execution, which use it, are in
{lit}`SqlAdvance.lean`. -/
namespace Belay.Sqlite.Model

/-- Run one statement at a clock value with the counters that it reads and the values bound to its
parameters, computing each
write and query once for its effect and its support check (ADR 0013, D8). The effect: INSERT and UPDATE with ABORT
constraints over the table's keys ({name}`Database.keys`), INSERT with {lit}`ON CONFLICT`
clauses or algorithms row by row ({name}`LiteralData.upsertSteps`), each over the rows at
the clock value ({name}`Resolved.rowsAt`), in the statement's context of its subqueries
({name}`Resolved.statementContext`), DELETE, which removes rows and cannot fail a
constraint, a query ({name}`queryEffect`), and {name}`step` for every other statement. A
position without a table fails as {lean}`ExecutionError.unmodeled`. An error carries the
database that the statement reached: the rows before the failing row of an INSERT with
clauses or algorithms, and the input database for every other error. The support check:
INSERT and UPDATE pass the data domain of the table, every write and query the JSON
checks of {lit}`JsonReady`, no expression cell of INSERT may fail ({name}`Resolved.cellsReady`), and a
statement's subqueries have no fallible call ({name}`Resolved.subqueriesPlain`), because SQLite may
evaluate a subquery for rows that the model does not reach, except the terms of a compound query
({name}`Resolved.Query.nestedSubqueries`), whose run describes their failures; a position without a table passes and fails during execution
instead. ADD COLUMN must have modeled default readback, a model restriction, because SQLite
accepts such statements. CREATE TABLE passes, as its table has no rows to violate a
constraint (ADR 0014, slice 4), and so do CREATE INDEX and the other statement forms. A write
that checks foreign keys (ADR 0018, D4) has the effect of its keys ({name}`insertKeys`,
{name}`updateKeys`, {name}`deleteKeys`, {name}`dropKeys`) and passes the support check when the
plain write and the keys both pass it ({name}`StatementRun.withKeys`). A write with trigger
programs (ADR 0018, D5) runs row by row in the same way, with foreign keys on or off. -/
def runStatement (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    StatementRun :=
  match statement with
  | .insert target rows returning subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock counters parameters database subqueries
      let keys := database.keys target table
      let values := Resolved.rowsAt context table.shape.columns rows
      let result := LiteralData.inserted table values
      let effect := insertOutcome database target keys table values result
      StatementRun.withKeys effect
        (LiteralData.insertReady keys table values result && Resolved.subqueriesPlain subqueries && Resolved.cellsReady context rows &&
          !(returningExpressions returning).any (·.any Resolved.Expr.isFallibleCall))
        (LiteralData.insertCounts effect keys table values)
        (rules.map fun rules => insertKeys rules clock target (database.catalog.writePolicy target table.shape none)
          [] values database subqueries.isEmpty)
  | .upsert target rows clauses returning algorithm subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock counters parameters database subqueries
      let keys := database.keys target table
      let policy := database.catalog.writePolicy target table.shape algorithm
      let values := Resolved.rowsAt context table.shape.columns rows
      let steps := LiteralData.upsertSteps context keys policy clauses table values
      let summary := LiteralData.upsertSummary table steps
      StatementRun.withKeys (match summary with
          | .ok (result, _) => .ok (database.setRows target result.rows)
          | .error (reason, reached, _) => .error (reason, database.setRows target reached.rows))
        (LiteralData.upsertReady keys table clauses values steps && Resolved.subqueriesPlain subqueries &&
          Resolved.cellsReady context rows && upsertJsonReady clauses returning)
        (LiteralData.upsertCounts keys clauses table.shape steps (match summary with
          | .ok _ => none
          | .error (reason, _, _) => some reason))
        (rules.map fun rules => insertKeys rules clock target policy clauses values database subqueries.isEmpty algorithm)
  | .update target assignments filter returning subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock counters parameters database subqueries
      let keys := database.keys target table
      let result := LiteralData.updated context table assignments filter
      let effect := if LiteralData.updateMismatch context table assignments filter then .error (.datatypeMismatch, database)
        else checkedWrite database target keys result
      StatementRun.withKeys effect
        (LiteralData.updateReady keys table assignments result && Resolved.subqueriesPlain subqueries &&
          updateJsonReady context table assignments filter returning)
        (LiteralData.changedCounts effect (table.scanRows.filter (LiteralData.selected context filter)).length)
        (rules.map fun rules => updateKeys context rules target table assignments filter database subqueries.isEmpty)
  | .delete target filter returning subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock counters parameters database subqueries
      StatementRun.withKeys (.ok (database.setRows target (LiteralData.deleted context table filter).rows))
        (Resolved.subqueriesPlain subqueries && deleteJsonReady context table filter returning)
        (LiteralData.changedCounts (.ok database) (table.scanRows.filter (LiteralData.selected context filter)).length)
        (rules.map fun rules => deleteKeys context rules target table filter database subqueries.isEmpty)
  | .query query subqueries =>
    let ran := query.runOn clock counters parameters database subqueries
    { effect := queryEffect database ran,
      ready := Resolved.subqueriesPlain (query.nestedSubqueries subqueries) && ran.all fun (source, run) => source.fault != .may && run.fault != .may }
  | .createTable .. => { effect := step clock counters parameters statement database, ready := true }
  | .addColumn _ column =>
    { effect := step clock counters parameters statement database,
      ready := column.clockDefault || (readDefaultValue column).toOption.isSome }
  | .drop positions rules =>
    StatementRun.withKeys (step clock counters parameters statement database) true {}
      (rules.map fun rules => dropKeys rules clock positions database)
  | .createIndex .. | .createTrigger .. => { effect := step clock counters parameters statement database, ready := true }
  | .begin | .commit | .rollback | .prepareError _ | .setting .. =>
    { effect := step clock counters parameters statement database, ready := true }

/-- The effect of one statement at a clock value with the counters and the values bound to its
parameters ({name}`runStatement`). This computation does not establish the separate stored-value support
obligation. -/
def literalStep (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    Effect :=
  (runStatement clock counters parameters statement database).effect

/-- Whether the model describes the statement with the counters and the values bound to its
parameters on the database ({name}`runStatement`). Use it through the reached-statement script support check. -/
def statementReady (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    Bool :=
  (runStatement clock counters parameters statement database).ready

/-- The run of a statement at a clock value on a connection state, with the values bound to its
parameters ({name}`runStatement`): over the database of the state, with the counters of the
state that the statement reads ({name}`Counters.view`) and no others, so that a counter that
the statement does not call cannot change its run. The run is ready only when {name}`runStatement`
is, and the state knows every counter that the statement reads ({name}`Counters.firstUnknown`),
because a statement with an unknown read is not described (ADR 0024, D2). Write the call as
{lit}`SqlState.statementRun state …`, not with dot notation, so that the copy of this file in the model
mutation test ({lit}`tests/conformance_mutation_test.py`) is the code that runs. -/
def SqlState.statementRun (state : SqlState) (clock : Int) (parameters : List Value) (statement : Resolved.Statement) :
    StatementRun :=
  let run := runStatement clock (state.counters.view statement.counterReads) parameters statement state.database
  { run with ready := run.ready && (state.counters.firstUnknown statement.counterReads).isNone }

end Belay.Sqlite.Model
