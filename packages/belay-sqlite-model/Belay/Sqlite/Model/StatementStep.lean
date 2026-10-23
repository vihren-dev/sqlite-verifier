import Belay.Sqlite.Model.SqlState
import Belay.Sqlite.Model.RowDelete
import Belay.Sqlite.Model.UpsertRun
import Belay.Sqlite.Model.StatementRun
import Belay.Sqlite.Model.JsonReady
import Belay.Sqlite.Model.StatementClock

set_option doc.verso true

/-! The steps of script-directed SQL execution of resolved statements. Each statement runs
at the clock value that the state's clock assignment gives for its position;
{lit}`SqlExecution.lean` chooses the assignment. BEGIN records the
committed snapshot; an explicit COMMIT/ROLLBACK, or an INSERT that fails with the
ROLLBACK algorithm, changes transaction state. Other statement errors stop execution
without inferring connection closure, framework cleanup, or transaction rollback. -/
namespace Belay.Sqlite.Model

/-- Run one statement at a clock value with the values bound to its parameters, computing each
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
def runStatement (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    StatementRun :=
  match statement with
  | .insert target rows returning subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock parameters database subqueries
      let keys := database.keys target table
      let values := Resolved.rowsAt context table.shape.columns rows
      let result := LiteralData.inserted table values
      StatementRun.withKeys (insertOutcome database target keys table values result)
        (LiteralData.insertReady keys table values result && Resolved.subqueriesPlain subqueries && Resolved.cellsReady context rows &&
          !(returningExpressions returning).any (·.any Resolved.Expr.isFallibleCall))
        (rules.map fun rules => insertKeys rules clock target (database.catalog.writePolicy target table.shape none)
          [] values database subqueries.isEmpty)
  | .upsert target rows clauses returning algorithm subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock parameters database subqueries
      let keys := database.keys target table
      let policy := database.catalog.writePolicy target table.shape algorithm
      let values := Resolved.rowsAt context table.shape.columns rows
      let steps := LiteralData.upsertSteps context keys policy clauses table values
      StatementRun.withKeys (match LiteralData.upsertSummary table steps with
          | .ok (result, _) => .ok (database.setRows target result.rows)
          | .error (reason, reached, _) => .error (reason, database.setRows target reached.rows))
        (LiteralData.upsertReady keys table clauses values steps && Resolved.subqueriesPlain subqueries &&
          Resolved.cellsReady context rows && upsertJsonReady clauses returning)
        (rules.map fun rules => insertKeys rules clock target policy clauses values database subqueries.isEmpty algorithm)
  | .update target assignments filter returning subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock parameters database subqueries
      let keys := database.keys target table
      let result := LiteralData.updated context table assignments filter
      StatementRun.withKeys (if LiteralData.updateMismatch context table assignments filter then .error (.datatypeMismatch, database)
          else checkedWrite database target keys result)
        (LiteralData.updateReady keys table assignments result && Resolved.subqueriesPlain subqueries &&
          updateJsonReady context table assignments filter returning)
        (rules.map fun rules => updateKeys context rules target table assignments filter database subqueries.isEmpty)
  | .delete target filter returning subqueries rules => match database.table target with
    | none => { effect := .error (.unmodeled, database), ready := true }
    | some table =>
      let context := Resolved.statementContext clock parameters database subqueries
      StatementRun.withKeys (.ok (database.setRows target (LiteralData.deleted context table filter).rows))
        (Resolved.subqueriesPlain subqueries && deleteJsonReady context table filter returning)
        (rules.map fun rules => deleteKeys context rules target table filter database subqueries.isEmpty)
  | .query query subqueries =>
    let ran := query.runOn clock parameters database subqueries
    { effect := queryEffect database ran,
      ready := Resolved.subqueriesPlain (query.nestedSubqueries subqueries) && ran.all fun (source, run) => source.fault != .may && run.fault != .may }
  | .createTable .. => { effect := step clock parameters statement database, ready := true }
  | .addColumn _ column =>
    { effect := step clock parameters statement database,
      ready := column.clockDefault || (readDefaultValue column).toOption.isSome }
  | .drop positions rules =>
    StatementRun.withKeys (step clock parameters statement database) true
      (rules.map fun rules => dropKeys rules clock positions database)
  | .createIndex .. | .createTrigger .. => { effect := step clock parameters statement database, ready := true }
  | .begin | .commit | .rollback | .prepareError _ | .setting .. =>
    { effect := step clock parameters statement database, ready := true }

/-- The effect of one statement at a clock value with the values bound to its parameters
({name}`runStatement`). This computation does not establish the separate stored-value support
obligation. -/
def literalStep (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    Effect :=
  (runStatement clock parameters statement database).effect

/-- Whether the model describes the statement with the values bound to its parameters on the
database ({name}`runStatement`). Use it through the reached-statement script support check. -/
def statementReady (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (database : Database) :
    Bool :=
  (runStatement clock parameters statement database).ready

/-- One statement at its supplied zero-based position with its effect. BEGIN records a
snapshot; COMMIT clears it; ROLLBACK restores it. Repeated BEGIN or transaction
closure without a snapshot halts with an error. Other statements use
the effect, which {lit}`advance` computes at the clock value of the position
({name}`SqlState.clock`); an error retains any open transaction, except a ROLLBACK failure,
which rolls it back ({name}`SqlState.failed`). -/
def advanceWith (position : Nat) (statement : Resolved.Statement) (state : SqlState) (effect : Effect) :
    SqlTransition :=
  match statement with
  | .begin => match state.snapshot with
    | some _ => .halt (state.finish (.failure position .transactionAlreadyActive state.database))
    | none => .next { state with snapshot := some state.database }
  | .commit => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some _ => .next { state with snapshot := none }
  | .rollback => match state.snapshot with
    | none => .halt (.failure position .noActiveTransaction state.database)
    | some original => .next { state with database := original, snapshot := none }
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .insert .. | .upsert .. | .update ..
  | .delete ..
  | .prepareError _ | .query .. | .setting .. =>
    state.publish position effect

/-- Evaluate one statement with the values bound to its parameters at its supplied zero-based
position ({name}`advanceWith` of its effect at the clock value of the position,
{name}`literalStep`). -/
def advance (position : Nat) (statement : Resolved.Statement) (parameters : List Value) (state : SqlState) :
    SqlTransition :=
  advanceWith position statement state (literalStep (state.clock position) parameters statement state.database)

/-- The statements of a script with the values bound to each: statement {lit}`i` (from 0) gets
item {lit}`i` of {lit}`values`, or the empty list when {lit}`values` has no such item. For
example, {lean}`bindValues [1, 2] [[.integer 5]] = [(1, [.integer 5]), (2, [])]`. Use
{lean}`([] : List (List Value))` as {lit}`values` for a script that binds no values. -/
def bindValues {α : Type} : List α → List (List Value) → List (α × List Value)
  | [], _ => []
  | statement :: rest, values => (statement, values.headD []) :: bindValues rest values.tail

/-- For every statement, rest of the script, list of values and rest of the lists,
{name}`bindValues` of the script and the lists is the pair of the first statement and the first
list, followed by {name}`bindValues` of the rest of the script and the rest of the lists. Proof
sketch: the definition. -/
@[simp] theorem bindValues_cons_cons {α : Type} (statement : α) (rest : List α) (values : List Value)
    (later : List (List Value)) :
    bindValues (statement :: rest) (values :: later) = (statement, values) :: bindValues rest later := rfl

/-- For every script and list of lists of values, the statements of {name}`bindValues` are the
script. Proof sketch: induction on the script. -/
@[simp] theorem map_fst_bindValues {α : Type} (script : List α) (values : List (List Value)) :
    (bindValues script values).map (·.1) = script := by
  induction script generalizing values with
  | nil => rfl
  | cons statement rest ih => simp [bindValues, ih]

/-- Execute the script from a supplied position and connection state, each statement with the
values bound to its parameters ({name}`bindValues` binds a list of lists). A halt stops
the script; a continuing transition advances the position. EOF finishes the
current state and preserves an open transaction. The idle wrapper starts at position zero. -/
def runSqlFrom (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Outcome :=
  match script with
  | [] => state.finish (.success state.database)
  | (statement, parameters) :: rest => match advance position statement parameters state with
    | .halt outcome => outcome
    | .next next => runSqlFrom (position + 1) rest next

/-- Execute a resolved script from position zero outside a transaction. Use
{name}`runSqlFrom` for an explicit position/state. A file is not implicitly atomic;
transaction control must be supplied in its statements. -/
def runSql (script : List (Resolved.Statement × List Value)) (database : Database) : Outcome :=
  runSqlFrom 0 script { database := database }

/-- Check {name}`statementReady` at every reached statement and follow the actual
transition, both from one run of the statement ({name}`runStatement`). After a halt,
unreachable statements impose no obligation. An empty script passes. -/
def supportedSqlFrom (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Bool :=
  match script with
  | [] => true
  | (statement, parameters) :: rest =>
    let run := runStatement (state.clock position) parameters statement state.database
    run.ready &&
    match advanceWith position statement state run.effect with
    | .halt _ => true
    | .next next => supportedSqlFrom (position + 1) rest next

end Belay.Sqlite.Model
