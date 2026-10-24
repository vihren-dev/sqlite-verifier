import Belay.Sqlite.Model.ForeignKeyRows
import Belay.Sqlite.Model.UpsertRun
import Belay.Sqlite.Model.RowCredit

set_option doc.verso true

/-! One row of an INSERT that runs row by row (ADR 0018, D4 and D5), in the order of SQLite's
{lit}`sqlite3Insert`: the rowid alias, the {lit}`BEFORE INSERT` programs, the constraints of
the row with their algorithms ({lit}`UpsertRun`), the rows that REPLACE deletes with their
foreign keys and, with recursive triggers on, their DELETE programs, the foreign keys of the row, the write, and the {lit}`AFTER INSERT` programs. -/

namespace Belay.Sqlite.Model

/-- The most rows that REPLACE may delete for one INSERT row of a write that runs row by row, in
a write that the model describes: SQLite deletes them in an order of its indexes that the model
does not follow, and the order changes the counts, the actions and the programs. -/
def replacedRowsDescribed : Nat := 1

/-- The algorithm of a failed constraint of an INSERT row: IGNORE skips the row, FAIL and
ROLLBACK stop the statement with the state, and every other algorithm fails as ABORT. -/
def failedRow (state : KeyState) : ConflictAlgorithm → Except KeyStop KeyState
  | .ignore => pure state
  | .fail => throw (.stopped .fail state)
  | .rollback => throw (.stopped .rollback state)
  | .abort | .replace => throw (.error .constraintViolation state)

/-- The {lit}`NEW` cells of a {lit}`BEFORE INSERT` program: the proposed row's cells with the
rowid alias as written, and -1 for a NULL alias, as SQLite has assigned no rowid yet. -/
def beforeInsertCells (table : Table) (values : List Value) : List Value :=
  let cells := (LiteralData.proposedRow table values).values
  match table.shape.rowidAlias with
  | some position => cells.set position (match values[position]? with
    | some .null | none => .integer (-1)
    | some value => value)
  | none => cells

/-- Delete the row that REPLACE replaces, with its foreign keys, actions and programs
({name}`deleteRow`, with the algorithm REPLACE for the programs). SQLite does not count a row that
REPLACE deletes, so the count of rows of the write stays (ADR 0024, D2), also when a program of the
delete stops the statement. -/
def replaceDelete (catalog : Catalog) (links : List ForeignKeyLink) (nested : NestedRun) (frame : RowFrame)
    (target : Nat) (state : KeyState) (row : Row) : Except KeyStop KeyState :=
  KeyResult.mapState (fun deleted => { deleted with own := state.own })
    (deleteRow catalog links nested { frame with algorithm := some .replace } target false false frame.recursive state row.rowid)

/-- One row of an INSERT into the table at the position in the frame: a rowid alias that is no
integer is {lit}`datatype mismatch`; with {lit}`BEFORE INSERT` programs, the types of a
{lit}`STRICT` table are checked and the programs run ({name}`beforeInsertCells`), and may end
the row; then the row as {lit}`UpsertRun` describes its constraints over the table as the
programs left it: a {lit}`DO NOTHING` clause skips the row, a {lit}`DO UPDATE` clause is not
described, a row that conflicts on REPLACE keys deletes the conflicting row with its foreign
keys and actions, and with recursive triggers on with its DELETE programs, which inherit
REPLACE, as SQLite's {lit}`sqlite3GenerateConstraintChecks` gives them; more than
{name}`replacedRowsDescribed` such rows are not described; then {name}`newSteps` checks the row, scanning the child rows only for a write of
several rows; then the row is inserted if it is admitted ({name}`LiteralData.rowAdmitted`, otherwise it is not described),
and the {lit}`AFTER INSERT` programs run over its cells. -/
def insertRow (catalog : Catalog) (links : List ForeignKeyLink) (nested : NestedRun) (frame : RowFrame) (target : Nat)
    (policy : Resolved.ConflictPolicy) (clauses : List Resolved.ConflictClause) (multiWrite record : Bool)
    (state : KeyState) (values : List Value) : Except KeyStop KeyState := do
  let some table := (state.database catalog).table target | throw .undescribed
  if LiteralData.aliasMismatch table.shape values then throw (.error .datatypeMismatch state)
  if !(frame.fired target .before .insert).isEmpty &&
      !LiteralData.typesFit table.shape (LiteralData.proposedRow table values) then throw (.error .constraintViolation state)
  let (state, ended) ← runPrograms catalog nested frame target .before .insert (beforeInsertCells table values) state
  if ended then return state
  let some table := (state.database catalog).table target | throw .undescribed
  let keys := catalog.uniqueKeys target table.shape
  let proposed := LiteralData.proposedRow table values
  if !LiteralData.boundedInteger proposed.rowid then throw .undescribed
  if let some column := LiteralData.nullColumn table.shape.columns proposed.values then
    return ← failedRow state (LiteralData.algorithmAt policy.notNull column)
  if !LiteralData.typesFit table.shape proposed then throw (.error .constraintViolation state)
  if !LiteralData.checksHold table.shape proposed then return ← failedRow state policy.check
  if let some (clause, _) := LiteralData.handlingClause keys clauses table proposed then
    match clause.action with
    | .nothing => return state
    | .update .. => throw .undescribed
  if let some index := LiteralData.blockingKey keys policy.keys table proposed then
    return ← failedRow state (LiteralData.algorithmAt policy.keys index)
  let replaced := table.rows.filter fun row => (List.range keys.length).any fun index =>
    LiteralData.algorithmAt policy.keys index == .replace && (keys[index]?).any (LiteralData.keyEqual · row proposed)
  if replaced.length > replacedRowsDescribed then throw .undescribed
  let state ← replaced.foldlM (replaceDelete catalog links nested frame target) state
  let state ← newSteps catalog state target proposed (childLinks links target) (parentLinks links target) multiWrite none []
  if !multiWrite && state.counter != 0 then throw (.error .constraintViolation state)
  let some current := (state.database catalog).table target | throw .undescribed
  match LiteralData.checkedRow keys { current with rows := current.rows ++ [proposed] } proposed with
  | .error reason => throw (.error reason state)
  | .ok (next, _) =>
    if !LiteralData.rowAdmitted current.shape proposed then throw .undescribed
    let written := if record then state.written ++ [proposed] else state.written
    let inserted := if current.shape.withoutRowid then state.inserted else some proposed.rowid
    let state := { state.changeRows target fun _ => next.rows with written, own := state.own + 1, inserted }
    return (← runPrograms catalog nested frame target .after .insert proposed.values state).1

end Belay.Sqlite.Model
