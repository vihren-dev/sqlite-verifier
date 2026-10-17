import Belay.Sqlite.JsonFaults
import Belay.Sqlite.RowUpdate
import Belay.Sqlite.QueryFunctions
import Belay.Sqlite.Resolution.ConflictForm

set_option doc.verso true

/-! Where the model describes the JSON failures of a statement (ADR 0012, amendment 5,
slice 6b), as a part of the supported-subset check {lit}`statementReady`. A query is
ready when no JSON call may fail ({lit}`Query.mayFail`) or SQLite certainly reports the
failure ({lit}`Query.mustFail`). A write is ready only when no
JSON call of its conditions and values may fail: the model gives a write no JSON error.
Each check also evaluates the expressions over the row with no cells, which reads NULL
in every column, because SQLite evaluates a constant {lit}`WHERE` term once before it
reads the rows. -/

namespace Belay.Sqlite

/-- Whether no {lit}`json_each` source of the query may fail: for each source, over every
row before it ({name}`Resolved.Query.eachInputs`), its rows have no error, which SQLite
reports only when it scans the source for a row. True when a table is missing. -/
def eachJsonReady (query : Resolved.Query) (database : Database) : Bool :=
  (query.eachInputs database).all fun inputs => inputs.all fun (each, rows) =>
    rows.all fun row => match each.cells row with
      | .ok _ => true
      | .error _ => false

/-- For every query without {lit}`json_each` sources and every database, no
{lit}`json_each` source may fail ({name}`eachJsonReady`). Proof sketch: with no source,
{name}`Resolved.Query.eachInputs` gives no input for a present table and none for a
missing one, so both cases of the table rows reduce to true. -/
theorem eachJsonReady_plain (query : Resolved.Query) (database : Database) (plain : query.functions = []) :
    eachJsonReady query database = true := by
  unfold eachJsonReady Resolved.Query.eachInputs
  rw [plain]
  cases query.tableSource database <;> rfl

/-- Whether the query over the database is ready: its tables are missing, or no JSON
call may fail over its source rows, or SQLite certainly reports the failure; and no
{lit}`json_each` source may fail ({name}`eachJsonReady`). -/
def queryJsonReady (query : Resolved.Query) (database : Database) : Bool :=
  (query.source database).all (fun rows => !query.mayFail rows || query.mustFail rows) &&
    eachJsonReady query database

/-- The {lit}`RETURNING` expressions of a write. -/
def returningExpressions (returning : List (Resolved.Expr × String)) : List Resolved.Expr :=
  returning.map (·.1)

/-- Whether an UPDATE over the table is ready: no JSON call of {lit}`WHERE` may fail
over a row of the table or over the empty row, no JSON call of a {lit}`SET` value may
fail over a row that {lit}`WHERE` selects, and no {lit}`RETURNING` expression has a JSON
call. -/
def updateJsonReady (table : Table) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) (returning : List (Resolved.Expr × String)) : Bool :=
  let rows := table.rows.map Row.values
  let chosen := (table.rows.filter (LiteralData.selected filter)).map Row.values
  !Resolved.anyMayFail ([] :: rows) filter.toList &&
  !Resolved.anyMayFail chosen (assignments.map (·.2)) &&
  !(returningExpressions returning).any Resolved.Expr.callsJson

/-- Whether a DELETE over the table is ready: no JSON call of {lit}`WHERE` may fail over
a row of the table or over the empty row, and no {lit}`RETURNING` expression has a JSON
call. -/
def deleteJsonReady (table : Table) (filter : Option Resolved.Expr)
    (returning : List (Resolved.Expr × String)) : Bool :=
  !Resolved.anyMayFail ([] :: table.rows.map Row.values) filter.toList &&
  !(returningExpressions returning).any Resolved.Expr.callsJson

/-- The expressions of an {lit}`ON CONFLICT` clause: the values and the filter of
{lit}`DO UPDATE`; none for {lit}`DO NOTHING`. -/
def Resolved.ConflictClause.expressions (clause : Resolved.ConflictClause) : List Resolved.Expr :=
  match clause.action with
  | .nothing => []
  | .update assignments filter => assignments.map (·.2) ++ filter.toList

/-- Whether an INSERT with {lit}`ON CONFLICT` clauses is ready: no clause and no
{lit}`RETURNING` expression has a JSON call. -/
def upsertJsonReady (clauses : List Resolved.ConflictClause) (returning : List (Resolved.Expr × String)) :
    Bool :=
  !(clauses.flatMap Resolved.ConflictClause.expressions ++ returningExpressions returning).any
    Resolved.Expr.callsJson

end Belay.Sqlite
