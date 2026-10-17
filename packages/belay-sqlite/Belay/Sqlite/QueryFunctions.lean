import Belay.Sqlite.QueryJoins
import Belay.Sqlite.Json.Each

set_option doc.verso true

/-! The {lit}`json_each` sources of a query (ADR 0012, amendment 5, slice 6d). Each joins
the rows before it as SQLite's nested loop does: for each row, the rows of
{lit}`json_each` over the values of its arguments on that row, each appended to the row,
that the {lit}`ON` condition keeps. A source whose {lit}`json_each` fails gives no rows
here; the supported-subset check refuses a statement in which it may fail
({lit}`JsonReady.lean`). -/

namespace Belay.Sqlite.Resolved

/-- The rows of {lit}`json_each` over the values of the source's arguments on a row, or
its error. -/
def EachSource.cells (each : EachSource) (row : List Value) : Except Json.JsonError (List (List Value)) :=
  Json.eachRows (each.json.eval row) (each.path.map (·.eval row))

/-- The joined rows of one row with the source: the row followed by each row of
{name}`EachSource.cells` that the {lit}`ON` condition keeps; none when it fails. -/
def EachSource.join (each : EachSource) (row : List Value) : List (List Value) :=
  match each.cells row with
  | .ok cells => (cells.map (row ++ ·)).filter fun joined => each.condition.all fun condition =>
      truthy (condition.eval joined)
  | .error _ => []

/-- The rows of the sources up to and including the {lit}`json_each` sources: the
{name}`EachSource.join` of each row before each source, in order. -/
def joinFunctions (rows : List (List Value)) (functions : List EachSource) : List (List Value) :=
  functions.foldl (fun rows each => rows.flatMap each.join) rows

/-- The source rows of a query over a database: the rows of its tables
({name}`Query.tableSource`) joined with its {lit}`json_each` sources in order
({name}`joinFunctions`); none when a table is missing. A query without {lit}`json_each`
has the rows of its tables. -/
def Query.source (query : Query) (database : Database) : Option (List (List Value)) :=
  (query.tableSource database).map (joinFunctions · query.functions)

/-- Each {lit}`json_each` source of a query with the rows before it, on which SQLite
evaluates its arguments; none when a table is missing. -/
def Query.eachInputs (query : Query) (database : Database) : Option (List (EachSource × List (List Value))) :=
  (query.tableSource database).map fun rows =>
    (query.functions.foldl (fun (rows, found) each => (rows.flatMap each.join, found ++ [(each, rows)]))
      (rows, [])).2

end Belay.Sqlite.Resolved
