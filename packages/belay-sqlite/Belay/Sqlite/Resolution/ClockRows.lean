import Belay.Sqlite.Resolution.Defaults
import Belay.Sqlite.Resolution.QueryExprs
import Belay.Sqlite.Resolution.Assignments
import Belay.Sqlite.Resolution.Resolved

set_option doc.verso true

/-! The rows of an INSERT whose cells may read the statement's clock (ADR 0012, amendment 5,
slice 6e2). A {lit}`VALUES` item with a time keyword and an omitted column whose default is
a time keyword cannot get a value at resolution: the cell holds NULL, and its expression
becomes a {lit}`Resolved.ClockCell`, which the execution fills at the statement's clock
value ({lit}`Statement.atClock`). Every other cell gets its value as before. -/

namespace Belay.Sqlite

/-- A cell of a resolved INSERT row before the clock: its value, and the expression of a
value that reads the clock, with NULL as the value. -/
abbrev RowCell := Value × Option Resolved.Expr

/-- One {lit}`VALUES` item, a constant expression of a write (ADR 0012, slices 3a and
6e2): the expression resolved as a query expression with no column in scope and an
aggregate as SQLite's {lit}`misuse of aggregate function`. Its value, so {lit}`1 + 2` is 3
and {lit}`CAST('7' AS INTEGER)` is 7, or NULL and its expression when it reads the clock.
An identifier, a rowid name included, is a double-quoted string or {lit}`no such column`,
as no table is in scope. A value whose JSON function may fail is a model restriction,
because the model does not describe when SQLite evaluates a constant. -/
def constantCell (dqs : Bool) (expression : Syntax.Expr) : Except ValueIssue RowCell :=
  resolveOperand dqs [] true expression >>= fun operand =>
    if operand.1.readsClock then
      if operand.1.callsJson then .error (.restriction [] .constantFunctionError) else .ok (.null, some operand.1)
    else if operand.1.mayFail [] then .error (.restriction [] .constantFunctionError)
    else .ok (operand.1.eval [], none)

/-- The cell of an omitted column: its default ({name}`defaultValue`) stored with the
column's affinity; or NULL and the time keyword of a default that is one, such as
{lit}`DEFAULT CURRENT_TIMESTAMP`. -/
def omittedCell (column : CatalogColumn) : Except ValueIssue RowCell :=
  match column.defaultValue with
  | some { expression := .currentTime keyword, .. } => .ok (.null, some (.now (Resolved.timeKeywordNamed keyword)))
  | _ => (defaultValue column).map fun value => (storeValue column.affinity value, none)

/-- One full row of cells in table order: the written cell of a named column, its value
stored with the column's affinity, or the cell of an omitted column ({name}`omittedCell`). -/
def fullCells (columns : List CatalogColumn) (positions : List Nat) (row : List RowCell) :
    Except ValueIssue (List RowCell) :=
  resolveAll (fun position column => match positions.idxOf? position with
    | some written =>
      let (value, clock) := row[written]?.getD (.null, none)
      .ok (storeValue column.affinity value, clock)
    | none => omittedCell column) columns

/-- The clock cells of full rows ({name}`fullCells`): one for each cell with an expression,
with its row, its column position and the column's affinity. -/
def clockCells (columns : List CatalogColumn) (rows : List (List RowCell)) : List Resolved.ClockCell :=
  rows.zipIdx.flatMap fun (row, rowIndex) => row.zipIdx.filterMap fun ((_, clock), column) =>
    clock.map fun value => { row := rowIndex, column, value, affinity := (columns[column]?.map (·.affinity)).getD .blob }

/-- An INSERT statement over full rows of cells: the statement over their values, wrapped as
{name}`Resolved.Statement.clocked` with its clock cells when it has some. -/
def withClockCells (columns : List CatalogColumn) (rows : List (List RowCell))
    (statement : List (List Value) → Resolved.Statement) : Resolved.Statement :=
  let cells := clockCells columns rows
  if cells.isEmpty then statement (rows.map (·.map Prod.fst)) else .clocked (statement (rows.map (·.map Prod.fst))) cells

end Belay.Sqlite
