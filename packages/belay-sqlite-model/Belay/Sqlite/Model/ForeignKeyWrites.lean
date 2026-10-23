import Belay.Sqlite.Model.RowEngine

set_option doc.verso true

/-! The writes that run row by row with foreign keys (ADR 0018, D4) or triggers (D5): INSERT,
UPDATE, DELETE and DROP TABLE over {name}`Belay.Sqlite.Model.runRows`, with SQLite's end of statement: a counter of violations other than zero
fails the statement as ABORT ({lit}`sqlite3VdbeCheckFkImmediate`), also after a FAIL failure,
which then keeps nothing; a ROLLBACK failure stays one. Checked natively: a FAIL failure of a
later row after a row without a parent is {lit}`FOREIGN KEY constraint failed`. -/

namespace Belay.Sqlite.Model

/-- What a write that runs row by row gives: its effect, the rows that it wrote
({name}`KeyState.written`), and whether the model describes it on the database. -/
structure KeyRun where
  /-- The effect of the write. -/
  effect : Effect
  /-- The rows that the statement wrote, for its {lit}`RETURNING` rows and its change count. -/
  written : List Row
  /-- Whether the model describes the write: its rows are described ({name}`KeyStop.undescribed`
  does not occur), no subquery reads a table while an action or a trigger changes the tables,
  every table that an action or a trigger changed satisfies its constraints before the write,
  and every changed table has bounded rowids. -/
  ready : Bool

/-- Whether the model describes the state of a run over the input database whose own
subqueries are none when {lit}`plain` is set ({name}`KeyRun.ready`). -/
def keyReady (input : Database) (target : Nat) (plain : Bool) (state : KeyState) : Bool :=
  ((plain && !state.subqueried) || state.acted.isEmpty) &&
    state.acted.all (fun position => (input.table position).all fun table =>
      LiteralData.tableReady (input.catalog.uniqueKeys position table.shape) table) &&
    (target :: state.acted).all fun position =>
      ((state.database input.catalog).rowsAt position).all (LiteralData.boundedInteger ·.rowid)

/-- The end of a write that runs row by row over the input database, whose own subqueries are
none when {lit}`plain` is set: a counter other than zero fails as ABORT, also after a FAIL
failure; a FAIL failure keeps the rows that it reached, a ROLLBACK failure rolls them back with
the transaction, and every other error keeps the input database. -/
def keyRun (input : Database) (target : Nat) (plain : Bool) : Except KeyStop KeyState → KeyRun
  | .error .undescribed => { effect := .error (.unmodeled, input), written := [], ready := false }
  | .error (.error reason) => { effect := .error (reason, input), written := [], ready := true }
  | .error (.stopped .rollback state) =>
    { effect := .error (.constraintRollback, state.database input.catalog), written := [], ready := keyReady input target plain state }
  | .error (.stopped .fail state) =>
    if state.counter != 0 then { effect := .error (.constraintViolation, input), written := [], ready := keyReady input target plain state }
    else { effect := .error (.constraintFail, state.database input.catalog), written := state.written,
           ready := keyReady input target plain state }
  | .ok state =>
    if state.counter != 0 then { effect := .error (.constraintViolation, input), written := [], ready := keyReady input target plain state }
    else { effect := .ok (state.database input.catalog), written := state.written, ready := keyReady input target plain state }


/-- The foreign-key links that a write with the rules checks: those of the catalog when the rules
check keys, none otherwise. -/
def Resolved.WriteRules.links (rules : Resolved.WriteRules) (catalog : Catalog) : List ForeignKeyLink :=
  if rules.keys then catalog.foreignKeyLinks else []

/-- The frame of a write with the rules at the clock value, with the conflict algorithm of its
{lit}`OR` clause, which its programs inherit: its programs and the setting of recursive
triggers, with nothing running. -/
def Resolved.WriteRules.frame (rules : Resolved.WriteRules) (clock : Int) (algorithm : Option ConflictAlgorithm) :
    RowFrame :=
  { clock, programs := rules.programs, recursive := rules.recursive, algorithm }

/-- The run of a work with the rules at the clock value ({name}`runRows`), with fuel one more
than the trigger depth limit, from the rows of the database; its programs inherit the algorithm. -/
def rowsKeys (rules : Resolved.WriteRules) (clock : Int) (target : Nat) (work : RowWork) (database : Database)
    (plain : Bool) (algorithm : Option ConflictAlgorithm := none) : KeyRun :=
  keyRun database target plain
    (runRows database.catalog (rules.links database.catalog) (rules.depth + 1) (rules.frame clock algorithm) work
      { rows := database.rows })

/-- An INSERT of the rows into the table at the position with the rules: a write of several rows
when it has more than one row, a key whose algorithm is REPLACE or a trigger of INSERT on the
table, as SQLite's {lit}`isMultiWrite` is. Its programs inherit the algorithm of its {lit}`OR`
clause, none without one. -/
def insertKeys (rules : Resolved.WriteRules) (clock : Int) (target : Nat) (policy : Resolved.ConflictPolicy)
    (clauses : List Resolved.ConflictClause) (rows : List (List Value)) (database : Database) (plain : Bool)
    (algorithm : Option ConflictAlgorithm := none) : KeyRun :=
  let multiWrite := rows.length > 1 || policy.keys.contains .replace ||
    rules.programs.any fun program => program.table == target && program.event == .insert
  rowsKeys rules clock target (.insert target rows policy clauses multiWrite true) database plain algorithm

/-- An UPDATE with the rules: the rows that the filter selects, in scan order, each with its new
row as {name}`LiteralData.assign` and {name}`LiteralData.movedRowid` give it from the row at the
time SQLite writes it. -/
def updateKeys (context : Resolved.EvalContext) (rules : Resolved.WriteRules) (target : Nat) (table : Table)
    (assignments : List (Nat × Resolved.Expr)) (filter : Option Resolved.Expr) (database : Database) (plain : Bool) :
    KeyRun :=
  let rowids := (table.scanRows.filter (LiteralData.selected context filter)).map (·.rowid)
  let change (row : Row) := LiteralData.movedRowid table.shape.rowidAlias
    (LiteralData.assign context table.shape.columns assignments row)
  let assigned := assignments.map (·.1)
  rowsKeys rules context.clock target (.update target change assigned (table.shape.changedColumns assigned) rowids true)
    database plain

/-- A DELETE with the rules: the rows that the filter selects, in scan order. -/
def deleteKeys (context : Resolved.EvalContext) (rules : Resolved.WriteRules) (target : Nat) (table : Table)
    (filter : Option Resolved.Expr) (database : Database) (plain : Bool) : KeyRun :=
  let rowids := (table.scanRows.filter (LiteralData.selected context filter)).map (·.rowid)
  rowsKeys rules context.clock target (.delete target rowids true false true) database plain

/-- DROP TABLE of a table that foreign keys reference: SQLite first deletes every row of the
table with {lit}`disableTriggers` ({name}`oldSteps` with {lit}`ignore`), then fails when the counter
is not zero and otherwise removes the objects at the positions from the database after the
DELETE. -/
def dropKeys (rules : Resolved.WriteRules) (clock : Int) (positions : List Nat) (database : Database) : KeyRun :=
  match positions, positions.head?.bind database.table with
  | target :: _, some table =>
    let run := rowsKeys rules clock target (.delete target (table.scanRows.map (·.rowid)) false true false) database true
    match run.effect with
    | .ok after => { run with effect := .ok (after.drop positions) }
    | .error _ => run
  | _, _ => { effect := .ok (database.drop positions), written := [], ready := true }

/-- For every input database, table, flag, result and database: if the run ({name}`keyRun`)
succeeds with the database, the database has the input's catalog. Proof sketch: the success is
the state's rows over the input catalog ({name}`KeyState.database`). -/
theorem keyRun_ok_catalog {input result : Database} {target : Nat} {plain : Bool}
    {outcome : Except KeyStop KeyState}
    (ok : (keyRun input target plain outcome).effect = .ok result) : result.catalog = input.catalog := by
  unfold keyRun at ok
  repeat' split at ok
  all_goals first | (cases ok; rfl) | cases ok

/-- For every database, positions, rules and result: if DROP TABLE with foreign keys
({name}`dropKeys`) succeeds, the result's catalog is the input catalog without the objects at the
positions, as for the plain DROP. Proof sketch: the DELETE keeps the catalog
({name}`keyRun_ok_catalog`) and {name}`Database.drop` removes the objects. -/
theorem dropKeys_ok_catalog {database result : Database} {rules : Resolved.WriteRules} {clock : Int}
    {positions : List Nat} (ok : (dropKeys rules clock positions database).effect = .ok result) :
    result.catalog = database.catalog.drop positions := by
  unfold dropKeys at ok
  split at ok
  · simp only [] at ok
    split at ok
    · rename_i after deleted
      cases ok
      simp only [Database.drop, keyRun_ok_catalog deleted]
    · rename_i failed
      rw [failed] at ok
      cases ok
  · cases ok; rfl

end Belay.Sqlite.Model
