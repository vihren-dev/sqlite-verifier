import Belay.Sqlite.Model.Resolution.Defaults
import Belay.Sqlite.Model.Resolution.QueryExprs
import Belay.Sqlite.Model.Resolution.Assignments
import Belay.Sqlite.Model.Resolution.Resolved

set_option doc.verso true

/-! The cells of a resolved INSERT row (ADR 0012, slices 3a and 6e2; ADR 0013, D6). A
{lit}`VALUES` item or an omitted column gets its value at resolution, stored with the
column's affinity; one whose value reads the statement's clock, such as
{lit}`CURRENT_TIMESTAMP` or {lit}`DEFAULT CURRENT_TIMESTAMP`, stays an expression
({lit}`Resolved.Cell.expression`), which the execution evaluates at the statement's clock
value and stores. -/

namespace Belay.Sqlite.Model

/-- One {lit}`VALUES` item, a constant expression of a write (ADR 0012, slices 3a and
6e2): the expression resolved as a query expression with no column in scope and an
aggregate as SQLite's {lit}`misuse of aggregate function`. Its value, so {lit}`1 + 2` is 3
and {lit}`CAST('7' AS INTEGER)` is 7, computed at the clock value 0, which it does not
read; or the expression when it reads the clock or a parameter, or names a subquery of the statement
({lit}`shapes`, {lit}`Resolved.Expr.namesSubquery`). An identifier, a rowid name included, is
a double-quoted string or {lit}`no such column`, as no table is in scope. A value whose
JSON function may fail is a model restriction, because the model does not describe when
SQLite evaluates a constant. The value is not yet stored with the column's affinity
({lit}`fullCells` stores it). In a trigger's body, {lit}`scope` has the trigger's rows (ADR
0018, D5), and an item that names them stays an expression too; elsewhere it is empty. -/
def constantCell (dqs : Bool) (shapes : SubqueryShapes) (expression : Syntax.Expr) (scope : Scope := []) :
    Except ValueIssue Resolved.Cell :=
  resolveOperand dqs scope shapes true expression >>= fun operand =>
    if operand.1.readsClock || operand.1.readsRunValue || operand.1.any Resolved.Expr.namesSubquery ||
        mentionsColumn scope expression then
      if operand.1.any Resolved.Expr.isFallibleCall then .error (.restriction [] .constantFunctionError)
      else .ok (.expression operand.1)
    else if operand.1.mayFailOn (.plain 0) [] then .error (.restriction [] .constantFunctionError)
    else .ok (.value (operand.1.eval (.plain 0) []))

/-- The cell of an omitted column: its default ({name}`defaultValue`) stored with the
column's affinity; or the time keyword of a default that is one, such as
{lit}`DEFAULT CURRENT_TIMESTAMP`. -/
def omittedCell (column : CatalogColumn) : Except ValueIssue Resolved.Cell :=
  match column.defaultValue with
  | some { form := .clock keyword, .. } => .ok (.expression (.now keyword))
  | some { form := .literal .., .. } | none => (defaultValue column).map fun value => .value (Value.store column.affinity value)

/-- A written cell stored with a column's affinity: a value is stored ({name}`Value.store`);
an expression stays as it is, and the execution stores its value. -/
def Resolved.Cell.stored (affinity : Affinity) : Resolved.Cell → Resolved.Cell
  | .value written => .value (Value.store affinity written)
  | .expression term => .expression term

/-- One full row of cells in table order: the written cell of a named column stored with
the column's affinity ({name}`Resolved.Cell.stored`), or the cell of an omitted column
({name}`omittedCell`). -/
def fullCells (columns : List CatalogColumn) (positions : List Nat) (row : List Resolved.Cell) :
    Except ValueIssue (List Resolved.Cell) :=
  resolveAll (fun position column => match positions.idxOf? position with
    | some written => .ok ((row[written]?.getD (.value .null)).stored column.affinity)
    | none => omittedCell column) columns

end Belay.Sqlite.Model
