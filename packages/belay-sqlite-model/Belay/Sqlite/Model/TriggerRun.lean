import Belay.Sqlite.Model.ForeignKeyPhases
import Belay.Sqlite.Model.Upsert
import Belay.Sqlite.Model.Subqueries
import Belay.Sqlite.Model.StatementClock

set_option doc.verso true

/-! The run of the trigger programs of one row (ADR 0018, D5). With recursive triggers off, a
program runs only when no program of the same trigger runs around it; with them on
({lit}`PRAGMA recursive_triggers`, ADR 0019, D2), also when one does. SQLite then counts the
frame of the program against its trigger depth limit, and the program runs its steps when its
{lit}`WHEN` condition is true for the row's cells. Its steps run in order: a write is a nested
write of the row engine, whose own triggers fire in turn; a SELECT may fail; a raising SELECT
ends the row with {lit}`RAISE(IGNORE)`, or fails the statement with the algorithm of the other
kinds. The nested writes run through {lit}`nested`, which the row engine gives with one less
fuel, so the depth of the programs is bounded as SQLite bounds it by its trigger depth limit. -/

namespace Belay.Sqlite.Model

/-- What the rows of a write run with besides their table: the statement's clock value, the
programs of the triggers that may fire, whether recursive triggers are on, the triggers whose
programs run around the rows, and the conflict algorithm that the programs of the rows inherit,
none for the default. Start with the programs and the setting of the write's rules and nothing
running. -/
structure RowFrame where
  /-- The statement's clock value. -/
  clock : Int
  /-- The programs of the triggers that the write may fire ({name}`Resolved.WriteRules`). -/
  programs : List Resolved.Program
  /-- Whether a trigger fires again while it runs, and the rows that REPLACE deletes fire the
  DELETE triggers. -/
  recursive : Bool := false
  /-- The catalog positions of the triggers whose programs run around the rows. -/
  running : List Nat := []
  /-- The conflict algorithm that the programs inherit. -/
  algorithm : Option ConflictAlgorithm := none

/-- The rows of one write of the row engine, in order, with the rowids of the rows that it
deletes or updates: a DELETE, with {lit}`record` for a statement's own rows, {lit}`ignore` for the
DELETE of DROP TABLE ({name}`oldSteps`) and {lit}`fire` when the table's DELETE triggers fire
(not for DROP TABLE, and for the rows that REPLACE deletes only with recursive triggers on); an UPDATE, each row to its new
row, with the {lit}`SET` columns, which decide its UPDATE triggers, and the changed positions;
and an INSERT of full rows of values with its conflict policy, clauses and whether it is a
write of several rows ({lit}`isMultiWrite`). -/
inductive RowWork where
  /-- Delete the rows. -/
  | delete (table : Nat) (rowids : List Int) (record ignore fire : Bool)
  /-- Update the rows, each to its new row. -/
  | update (table : Nat) (change : Row → Row) (assigned changed : List Nat) (rowids : List Int) (record : Bool)
  /-- Insert the rows. -/
  | insert (table : Nat) (rows : List (List Value)) (policy : Resolved.ConflictPolicy)
      (clauses : List Resolved.ConflictClause) (multiWrite record : Bool)

/-- A nested write of the row engine: the work in the frame from a state. -/
abbrev NestedRun := RowFrame → RowWork → KeyState → Except KeyStop KeyState

/-- The value of an INSERT cell of a trigger's body over the trigger's cells, stored with the
affinity, as {name}`Resolved.Cell.valueAt` gives it over no cells. -/
def Resolved.Cell.valueWith (context : Resolved.EvalContext) (cells : List Value) (affinity : Affinity) :
    Resolved.Cell → Value
  | .value stored => stored
  | .expression term => Value.store affinity (term.eval context cells)

/-- The rows of an INSERT of a trigger's body over the trigger's cells ({name}`Resolved.Cell.valueWith`). -/
def rowsWith (context : Resolved.EvalContext) (cells : List Value) (columns : List CatalogColumn)
    (rows : List (List Resolved.Cell)) : List (List Value) :=
  rows.map fun row => row.zipIdx.map fun (cell, index) =>
    cell.valueWith context cells ((columns[index]?.map CatalogColumn.affinity).getD .blob)

/-- The rowids of the rows of the table that the filter selects over each row followed by the
trigger's cells, in scan order. -/
def selectedRowids (context : Resolved.EvalContext) (cells : List Value) (table : Table)
    (filter : Option Resolved.Expr) : List Int :=
  (table.scanRows.filter fun row => filter.all fun condition => Resolved.truthy (condition.eval context (row.values ++ cells))).map
    (·.rowid)

/-- The kind that a raising SELECT raises over the trigger's cells: none when its filter is not
true, else the kind of the first arm whose condition is true, or the kind of {lit}`otherwise`. -/
def raisedKind (context : Resolved.EvalContext) (cells : List Value) (filter : Option Resolved.Expr)
    (arms : List (Resolved.Expr × Option Syntax.RaiseKind)) (otherwise : Option Syntax.RaiseKind) :
    Option Syntax.RaiseKind :=
  if !(filter.all fun condition => Resolved.truthy (condition.eval context cells)) then none
  else match arms.find? fun (condition, _) => Resolved.truthy (condition.eval context cells) with
    | some (_, kind) => kind
    | none => otherwise

/-- What {lit}`RAISE` of the kind does to the state: {lit}`IGNORE` ends the row (true), ABORT fails
the statement as a constraint failure, and FAIL and ROLLBACK stop it with their algorithm. -/
def raiseEffect (state : KeyState) : Syntax.RaiseKind → Except KeyStop (KeyState × Bool)
  | .ignore => pure (state, true)
  | .abort => throw (.error .constraintViolation state)
  | .fail => throw (.stopped .fail state)
  | .rollback => throw (.stopped .rollback state)

/-- The state after a write of a step: the written table among the changed tables, and a body
statement with subqueries noted. -/
def KeyState.afterStep (state : KeyState) (table : Nat) (subqueries : List Resolved.Query) : KeyState :=
  { state with acted := state.acted ++ [table], subqueried := state.subqueried || !subqueries.isEmpty }

/-- Run one step of a program over the trigger's cells in the frame of the program: a write
through {lit}`nested` with the algorithm that it inherits, the SELECT of a query with its errors,
or a raising SELECT. A trigger body binds no values, so each parameter of a step is NULL; SQLite
refuses a trigger with a parameter at prepare. The second result is true when the step ends the
row. -/
def runStep (catalog : Catalog) (nested : NestedRun) (frame : RowFrame) (cells : List Value) (state : KeyState) :
    Resolved.Step → Except KeyStop (KeyState × Bool)
  | .insert table rows clauses own subqueries => do
    let database := state.database catalog
    let some target := database.table table | throw .undescribed
    let context := Resolved.statementContext frame.clock {} [] database subqueries
    let algorithm := frame.algorithm <|> own
    let values := rowsWith context cells target.shape.columns rows
    let work := RowWork.insert table values (catalog.writePolicy table target.shape algorithm) clauses true false
    return ((← nested { frame with algorithm } work state).afterStep table subqueries, false)
  | .update table assignments filter subqueries => do
    let database := state.database catalog
    let some target := database.table table | throw .undescribed
    let context := Resolved.statementContext frame.clock {} [] database subqueries
    let change (row : Row) := LiteralData.movedRowid target.shape.rowidAlias
      (LiteralData.assignFrom context target.shape.columns assignments (row.values ++ cells) row)
    let assigned := assignments.map (·.1)
    let work := RowWork.update table change assigned (target.shape.changedColumns assigned)
      (selectedRowids context cells target filter) false
    return ((← nested frame work state).afterStep table subqueries, false)
  | .delete table filter subqueries => do
    let database := state.database catalog
    let some target := database.table table | throw .undescribed
    let context := Resolved.statementContext frame.clock {} [] database subqueries
    let work := RowWork.delete table (selectedRowids context cells target filter) false false true
    return ((← nested frame work state).afterStep table subqueries, false)
  | .query query subqueries => do
    let database := state.database catalog
    let context := Resolved.statementContext frame.clock {} [] database subqueries
    let some source := query.sourceAfter context cells database | throw .undescribed
    let run := query.run context source.rows
    if source.fault == .may || run.fault == .may || !Resolved.subqueriesPlain subqueries then throw .undescribed
    if run.mismatch then throw (.error .datatypeMismatch state)
    if run.overflow then throw (.error .integerOverflow state)
    if run.fault == .must then throw (.error .functionError state)
    return ({ state with subqueried := state.subqueried || !subqueries.isEmpty }, false)
  | .raise filter arms otherwise =>
    match raisedKind (.plain frame.clock) cells filter arms otherwise with
    | some kind => raiseEffect state kind
    | none => pure (state, false)

/-- Enter the frame of a program of a trigger on the table at the position: SQLite counts the
frame when it enters the program, before it tests the {lit}`WHEN` condition, and fails beyond its
trigger depth limit, which the model does not describe. The nested run has one less fuel than
the write of the row, so it can run a write exactly when the depth limit allows one more frame;
the check runs a nested DELETE of no rows, which changes nothing. -/
def enterProgram (nested : NestedRun) (frame : RowFrame) (table : Nat) (state : KeyState) : Except KeyStop Unit :=
  (fun _ => ()) <$> nested frame (.delete table [] false false false) state

/-- Run the program over the trigger's cells: nothing when the frame runs it already and recursive
triggers are off; else the program enters its frame ({name}`enterProgram`), and nothing more
when its condition is not true; else its steps in order, in the frame with the program's trigger
running, up to the first that ends the row. The second result is true when a step ended the
row. -/
def runProgram (catalog : Catalog) (nested : NestedRun) (frame : RowFrame) (cells : List Value) (state : KeyState)
    (program : Resolved.Program) : Except KeyStop (KeyState × Bool) := do
  if !frame.recursive && frame.running.contains program.trigger then return (state, false)
  enterProgram nested frame program.table state
  if !(program.condition.all fun condition => Resolved.truthy (condition.eval (.plain frame.clock) cells)) then
    pure (state, false)
  else
    let inner := { frame with running := program.trigger :: frame.running }
    program.body.foldlM (fun (state, ended) step => if ended then pure (state, true)
      else runStep catalog nested inner cells state step) (state, false)

/-- The programs of the frame for the rows of the table at the position, at the time and for the
write's event, in the frame's order, newest first. -/
def RowFrame.fired (frame : RowFrame) (table : Nat) (time : Syntax.TriggerTime) (event : Resolved.TriggerEvent) :
    List Resolved.Program :=
  frame.programs.filter fun program => program.table == table && program.time == time && program.event.fires event

/-- Run the programs of the frame for a row at the time ({name}`RowFrame.fired`) over its cells,
up to the first that ends the row. The second result is true when one ended it. -/
def runPrograms (catalog : Catalog) (nested : NestedRun) (frame : RowFrame) (table : Nat) (time : Syntax.TriggerTime)
    (event : Resolved.TriggerEvent) (cells : List Value) (state : KeyState) : Except KeyStop (KeyState × Bool) :=
  (frame.fired table time event).foldlM (fun (state, ended) program => if ended then pure (state, true)
    else runProgram catalog nested frame cells state program) (state, false)

end Belay.Sqlite.Model
