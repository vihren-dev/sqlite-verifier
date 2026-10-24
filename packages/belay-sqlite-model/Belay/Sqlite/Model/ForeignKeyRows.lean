import Belay.Sqlite.Model.TriggerRun

set_option doc.verso true

/-! The rows that a DELETE or an UPDATE writes row by row, with their foreign keys (ADR 0018, D4)
and triggers (D5), and the writes of the actions of its keys. SQLite first finds the rows of the statement, then
writes them in rowid order, or primary-key order for a {lit}`WITHOUT ROWID` table, and skips a
row that an earlier action deleted. After a row is deleted, and after the new row of an update
is written when its parent key changes, each key that references the table runs its action
over the child rows of the old row: {lit}`CASCADE` deletes them, or for an update writes the
new parent key into them; {lit}`SET NULL` and {lit}`SET DEFAULT` write NULL or the column's
default; {lit}`RESTRICT` fails when there is a child row. The action of an update runs only
when the parent key changes ({name}`Belay.Sqlite.Model.keyUnchanged`). Each action is a write of its own, with
the same counter, and every constraint of its rows is ABORT. -/

namespace Belay.Sqlite.Model

/-- The row with each position set to its value, stored with the column's affinity, its
generated columns computed and its rowid moved with its alias, as an UPDATE writes it. -/
def setCells (shape : CatalogTable) (cells : List (Nat × Value)) (row : Row) : Row :=
  let assigned := cells.foldl (fun values (position, value) =>
    values.set position (Value.store (LiteralData.positionAffinity shape.columns position) value)) row.values
  LiteralData.movedRowid shape.rowidAlias { row with values := LiteralData.generatedCells shape.columns assigned }

/-- The value that {lit}`SET DEFAULT` writes into a child column: NULL for a generated column or
a column without a default, or the default's value; none for a default that the model does not
describe there, such as a time keyword, which would make the statement read the clock. -/
def actionDefault (column : CatalogColumn) : Option Value :=
  if column.generated.isSome then some .null else match column.defaultValue with
  | none => some .null
  | some { form := .literal (.value value) _, .. } => some value
  | some { form := .literal (.hexLiteralTooBig _) _, .. } | some { form := .clock _, .. } => none

/-- The place in the parent key's pairs of the key column of the link at the written index: 0
for a rowid key. -/
def pairIndex (link : ForeignKeyLink) (key : ParentKey) (index : Nat) : Nat :=
  match key with
  | .rowid => 0
  | .columns pairs => (pairs.findIdx? (·.1 == link.key.columns.getD index 0)).getD index

/-- The cells that an action writes into a child row: the new parent key for {lit}`CASCADE`,
NULL for {lit}`SET NULL`, the defaults for {lit}`SET DEFAULT` ({name}`actionDefault`). -/
def actionCells (child parent : CatalogTable) (link : ForeignKeyLink) (key : ParentKey) (new : Row) :
    Syntax.ForeignKeyAction → Option (List (Nat × Value))
  | .cascade => some (link.key.columns.zipIdx.map fun (position, index) =>
      (position, (parentCell parent key new (pairIndex link key index)).1))
  | .setNull => some (link.key.columns.map (·, .null))
  | .setDefault => link.key.columns.mapM fun position => (child.columns[position]?.bind actionDefault).map (position, ·)
  | .noAction | .restrict => some []

/-- The state after the new row of an UPDATE of a row is checked ({name}`LiteralData.checkedRow`
over the table with the old row replaced): a rowid alias that is no integer is
{lit}`datatype mismatch`, and a failed constraint fails as ABORT. -/
def checkedUpdate (catalog : Catalog) (state : KeyState) (position : Nat) (old new : Row) : Except KeyStop Unit :=
  match (state.database catalog).table position with
  | none => throw .undescribed
  | some table =>
    if LiteralData.aliasCellMismatch table.shape.rowidAlias new then throw (.error .datatypeMismatch state)
    else match LiteralData.checkedRow (catalog.uniqueKeys position table.shape)
        (LiteralData.replaceRow table old new) new with
      | .ok _ => pure ()
      | .error reason => throw (.error reason state)

/-- The action of a link for the old row of the parent table at the position, with the new row
of an update, where {lit}`run` runs the write of the action: nothing for {lit}`NO ACTION` or an
update that keeps the parent key; otherwise the child rows of the old row, which
{lit}`RESTRICT` refuses with a constraint failure and every other action writes. -/
def runAction (catalog : Catalog) (run : RowWork → KeyState → Except KeyStop KeyState) (link : ForeignKeyLink)
    (action : Syntax.ForeignKeyAction) (position : Nat) (old : Row) (new : Option Row) (state : KeyState) :
    Except KeyStop KeyState :=
  match link.parent, catalog.tableAt position, catalog.tableAt link.child with
  | .located _ key, some parent, some child =>
    let targets := (childRows (state.database catalog) link key position old [] false).map (·.rowid)
    let acted (state : KeyState) := { state with acted := if targets.isEmpty then state.acted else state.acted ++ [link.child] }
    if new.any (keyUnchanged parent key old ·) then pure state else
    match action, new with
    | .noAction, _ => pure state
    | .restrict, _ => if targets.isEmpty then pure state else throw (.error .constraintViolation state)
    | .cascade, none => acted <$> run (.delete link.child targets false false true) state
    | .cascade, some _ | .setNull, _ | .setDefault, _ =>
      match actionCells child parent link key (new.getD old) action with
      | none => throw .undescribed
      | some cells => acted <$> run (.update link.child (setCells child cells) link.key.columns
          (child.changedColumns link.key.columns) targets false) state
  | .located .., none, _ | .located .., some _, none | .mismatch _, _, _ | .missing, _, _ => pure state

/-- The frame of the write of a foreign-key action: SQLite runs it as a program whose writes
inherit ABORT. -/
def RowFrame.action (frame : RowFrame) : RowFrame := { frame with algorithm := some .abort }

/-- Delete the row with the rowid from the table at the position, if it is still there, as
SQLite's {lit}`sqlite3GenerateRowDelete` does: with {lit}`fire`, the {lit}`BEFORE DELETE`
programs over the row's {lit}`OLD` cells, which may end the row; then {name}`oldSteps`, the
delete, the actions of the keys that reference the table ({name}`runAction`, through
{lit}`nested`), and with {lit}`fire` the {lit}`AFTER DELETE` programs. -/
def deleteRow (catalog : Catalog) (links : List ForeignKeyLink) (nested : NestedRun) (frame : RowFrame) (position : Nat)
    (record ignore fire : Bool) (state : KeyState) (rowid : Int) : Except KeyStop KeyState := do
  let some found := ((state.database catalog).rowsAt position).find? (·.rowid == rowid) | pure state
  let (state, ended) ← if fire then runPrograms catalog nested frame position .before .delete found.values state
    else pure (state, false)
  if ended then return state
  let some row := ((state.database catalog).rowsAt position).find? (·.rowid == rowid) | pure state
  let state ← oldSteps catalog state position row (childLinks links position) (parentLinks links position) ignore
  let written := if record then state.written ++ [row] else state.written
  let state := { state.changeRows position fun rows => rows.filter (·.rowid != rowid) with written, own := state.own + 1 }
  let state ← (parentLinks links position).foldlM (fun state link =>
    runAction catalog (nested frame.action) link link.key.onDelete position row none state) state
  if fire then return (← runPrograms catalog nested frame position .after .delete row.values state).1
  return state

/-- Update the row with the rowid of the table at the position to its new row, if it is still
there: a rowid alias that is no integer is {lit}`datatype mismatch`; with {lit}`BEFORE UPDATE`
programs for the {lit}`SET` columns, the types of a {lit}`STRICT` table are checked and the
programs run over the {lit}`NEW` then {lit}`OLD` cells, and may end the row; then the checks of
the new row ({name}`checkedUpdate`), which fail as ABORT and are not described under another
inherited algorithm; with a changed key ({name}`updateLevel`), {name}`oldSteps` and
{name}`newSteps` for the changed keys, where SQLite keeps the old row's record while it checks
the new row when the level is 1 and the rowid or primary key stays; the write; the actions of
the changed parent keys; and the {lit}`AFTER UPDATE` programs. -/
def updateRow (catalog : Catalog) (links : List ForeignKeyLink) (nested : NestedRun) (frame : RowFrame) (position : Nat)
    (change : Row → Row) (assigned changed : List Nat) (record : Bool) (state : KeyState) (rowid : Int) :
    Except KeyStop KeyState :=
  match ((state.database catalog).rowsAt position).find? (·.rowid == rowid), catalog[position]? with
  | some old, some { name, entry := .table shape } => do
    let new := change old
    let event := Resolved.TriggerEvent.update (some assigned)
    if LiteralData.aliasCellMismatch shape.rowidAlias new then throw (.error .datatypeMismatch state)
    if !(frame.fired position .before event).isEmpty && !LiteralData.typesFit shape new then
      throw (.error .constraintViolation state)
    let (state, ended) ← runPrograms catalog nested frame position .before event (new.values ++ old.values) state
    if ended then return state
    match checkedUpdate catalog state position old new with
    | .error stop => if frame.algorithm.all (· == .abort) then throw stop else throw .undescribed
    | .ok () => pure ()
    let level := updateLevel links position name shape changed
    let children := (childLinks links position).filter fun link =>
      link.key.childChanged changed || link.key.selfReferences name
    let parents := (parentLinks links position).filter (·.key.parentChanged shape changed)
    let before ← if level != 0 then oldSteps catalog state position old children parents false else pure state
    let moved := shape.rowidAlias.any changed.contains || (shape.withoutRowid && shape.primaryKey.any changed.contains)
    let stale := if level ≤ 1 && !moved then some old else none
    let removed := before.changeRows position fun rows => rows.filter (·.rowid != rowid)
    let checked ← if level != 0 then newSteps catalog removed position new children parents true stale changed
      else pure removed
    let written := if record then checked.written ++ [new] else checked.written
    let state := { checked with rows := before.rows, written, own := checked.own + 1 }.changeRows position fun rows =>
      rows.map fun (row : Row) => if row.rowid == rowid then new else row
    let state ← parents.foldlM (fun state link =>
      runAction catalog (nested frame.action) link link.key.onUpdate position old (some new) state) state
    return (← runPrograms catalog nested frame position .after event (new.values ++ old.values) state).1
  | none, _ | some _, some { entry := .index _, .. } | some _, some { entry := .trigger _, .. } | some _, none =>
    pure state

end Belay.Sqlite.Model
