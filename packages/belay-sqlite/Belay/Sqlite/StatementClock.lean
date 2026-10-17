import Belay.Sqlite.Resolution.Resolved
import Belay.Sqlite.ClockSubstitution
import Belay.Sqlite.StoreValue
import Belay.Sqlite.QueryEval

set_option doc.verso true

/-! A resolved statement at a clock value (ADR 0012, amendment 5, slice 6e2): every time
keyword of its expressions becomes the text that SQLite gives for it at the clock value
({lit}`Expr.atClock`), and every cell of a {lit}`Statement.clocked`
INSERT gets its value at the clock value, stored with its affinity. The execution applies
the clock value of each statement in this way before it runs the statement, so the steps
of the execution never read the clock. -/

namespace Belay.Sqlite.Resolved

/-- An aggregate at a clock value. -/
def Aggregate.atClock (clock : Int) : Aggregate → Aggregate
  | .countRows => .countRows
  | .count operand => .count (operand.atClock clock)
  | .min operand => .min (operand.atClock clock)
  | .max operand => .max (operand.atClock clock)
  | .sum operand => .sum (operand.atClock clock)
  | .avg operand => .avg (operand.atClock clock)

/-- A result column at a clock value. -/
def Output.atClock (clock : Int) : Output → Output
  | .scalar term => .scalar (term.atClock clock)
  | .aggregate function => .aggregate (function.atClock clock)

/-- An {lit}`ORDER BY` key at a clock value. -/
def SortKey.atClock (clock : Int) : SortKey → SortKey
  | .expression term => .expression (term.atClock clock)
  | .output index => .output index

/-- A query at a clock value: each of its expressions at the clock value. -/
def Query.atClock (clock : Int) (query : Query) : Query :=
  { query with
    joins := query.joins.map fun join => { join with condition := join.condition.map (·.atClock clock) }
    functions := query.functions.map fun each =>
      { json := each.json.atClock clock, path := each.path.map (·.atClock clock),
        condition := each.condition.map (·.atClock clock) }
    filter := query.filter.map (·.atClock clock)
    groupBy := query.groupBy.map (·.atClock clock)
    columns := query.columns.map (·.atClock clock)
    orderBy := query.orderBy.map fun (key, descending) => (key.atClock clock, descending) }

/-- The {lit}`RETURNING` columns at a clock value. -/
def returningAtClock (clock : Int) (returning : List (Expr × String)) : List (Expr × String) :=
  returning.map fun (expression, name) => (expression.atClock clock, name)

/-- An {lit}`ON CONFLICT` clause at a clock value. -/
def ConflictClause.atClock (clock : Int) (clause : ConflictClause) : ConflictClause :=
  { clause with action := match clause.action with
    | .nothing => .nothing
    | .update assignments filter =>
      .update (assignments.map fun (position, value) => (position, value.atClock clock))
        (filter.map (·.atClock clock)) }

/-- The rows of an INSERT with each cell set to its value at a clock value: the value of
the cell's expression, which reads no column, stored with the cell's affinity. -/
def ClockCell.fill (clock : Int) (rows : List (List Value)) (cell : ClockCell) : List (List Value) :=
  rows.modify cell.row fun row => row.set cell.column (storeValue cell.affinity ((cell.value.atClock clock).eval []))

/-- The expressions of a statement at a clock value ({name}`Expr.atClock`). A clocked
INSERT keeps its cells; {lit}`Statement.atClock` fills them first. -/
def Statement.expressionsAtClock (clock : Int) : Statement → Statement
  | .insert at_ rows keys returning => .insert at_ rows keys (returningAtClock clock returning)
  | .upsert at_ rows clauses keys returning policy =>
    .upsert at_ rows (clauses.map (·.atClock clock)) keys (returningAtClock clock returning) policy
  | .update at_ assignments filter keys returning =>
    .update at_ (assignments.map fun (position, value) => (position, value.atClock clock))
      (filter.map (·.atClock clock)) keys (returningAtClock clock returning)
  | .delete at_ filter returning => .delete at_ (filter.map (·.atClock clock)) (returningAtClock clock returning)
  | .query inner => .query (inner.atClock clock)
  | .clocked statement cells => .clocked statement cells
  | .createTable at_ name table => .createTable at_ name table
  | .createIndex at_ name index => .createIndex at_ name index
  | .addColumn at_ column => .addColumn at_ column
  | .begin => .begin
  | .commit => .commit
  | .rollback => .rollback
  | .prepareError error => .prepareError error

/-- An INSERT with its cells set to their values at a clock value ({name}`ClockCell.fill`);
any other statement unchanged. -/
def Statement.fillCells (clock : Int) (cells : List ClockCell) : Statement → Statement
  | .insert at_ rows keys returning => .insert at_ (cells.foldl (ClockCell.fill clock) rows) keys returning
  | .upsert at_ rows clauses keys returning policy =>
    .upsert at_ (cells.foldl (ClockCell.fill clock) rows) clauses keys returning policy
  | statement@(.update ..) | statement@(.delete ..) | statement@(.query _) | statement@(.clocked ..)
  | statement@(.createTable ..) | statement@(.createIndex ..) | statement@(.addColumn ..) | statement@.begin
  | statement@.commit | statement@.rollback | statement@(.prepareError _) => statement

/-- A statement at a clock value: a clocked INSERT with its cells filled in
({name}`Statement.fillCells`), then every statement with its expressions at the clock value
({name}`Statement.expressionsAtClock`). -/
def Statement.atClock (clock : Int) : Statement → Statement
  | .clocked statement cells => (statement.fillCells clock cells).expressionsAtClock clock
  | statement@(.insert ..) | statement@(.upsert ..) | statement@(.update ..) | statement@(.delete ..)
  | statement@(.query _) | statement@(.createTable ..) | statement@(.createIndex ..) | statement@(.addColumn ..)
  | statement@.begin | statement@.commit | statement@.rollback | statement@(.prepareError _) =>
    statement.expressionsAtClock clock

/-- Whether a result column reads the clock. -/
def Output.readsClock : Output → Bool
  | .scalar term => term.readsClock
  | .aggregate .countRows => false
  | .aggregate (.count operand) | .aggregate (.min operand) | .aggregate (.max operand)
  | .aggregate (.sum operand) | .aggregate (.avg operand) => operand.readsClock

/-- Whether an {lit}`ORDER BY` key reads the clock. -/
def SortKey.readsClock : SortKey → Bool
  | .expression term => term.readsClock
  | .output _ => false

/-- Whether some expression of a query reads the clock. -/
def Query.readsClock (query : Query) : Bool :=
  query.joins.any (·.condition.any Expr.readsClock) ||
  query.functions.any (fun each => each.json.readsClock || each.path.any Expr.readsClock ||
    each.condition.any Expr.readsClock) ||
  query.filter.any Expr.readsClock || query.groupBy.any Expr.readsClock || query.columns.any Output.readsClock ||
  query.orderBy.any (·.1.readsClock)

/-- Whether some {lit}`RETURNING` column reads the clock. -/
def returningReadsClock (returning : List (Expr × String)) : Bool :=
  returning.any (·.1.readsClock)

/-- Whether an {lit}`ON CONFLICT` clause reads the clock. -/
def ConflictClause.readsClock (clause : ConflictClause) : Bool :=
  match clause.action with
  | .nothing => false
  | .update assignments filter => assignments.any (·.2.readsClock) || filter.any Expr.readsClock

/-- Whether a statement reads the clock: a clocked INSERT, or a statement with an
expression that reads it. A statement that does not is unchanged at every clock value
({lit}`Statement.atClock_of_readsClock`). -/
def Statement.readsClock : Statement → Bool
  | .insert _ _ _ returning => returningReadsClock returning
  | .upsert _ _ clauses _ returning _ => clauses.any ConflictClause.readsClock || returningReadsClock returning
  | .update _ assignments filter _ returning =>
    assignments.any (·.2.readsClock) || filter.any Expr.readsClock || returningReadsClock returning
  | .delete _ filter returning => filter.any Expr.readsClock || returningReadsClock returning
  | .query inner => inner.readsClock
  | .clocked .. => true
  | .createTable .. | .createIndex .. | .addColumn .. | .begin | .commit | .rollback | .prepareError _ => false

end Belay.Sqlite.Resolved
