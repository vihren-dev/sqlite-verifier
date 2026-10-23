import Belay.Sqlite.Model.OutputRepr
import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! The outputs of a script as text tables: each result as a table, with the names of its
columns, as the {lit}`sqlite3` shell shows them with {lit}`.mode column`, and each other output
as its {lit}`Repr` writes it ({lit}`OutputRepr.lean`). The names of the columns of each
statement come from its resolution on the connection before it. For example, a query of two
columns {lit}`id` and {lit}`customer` with one row is two lines, {lit}`id | customer` and
{lit}`1  | acme`. -/

namespace Belay.Sqlite.Model

/-- The names of the result columns of the statement: those of a query, and those of the
{lit}`RETURNING` clause of a write; none for another statement. -/
def Resolved.Statement.resultNames : Resolved.Statement → List String
  | .query resolved _ => resolved.names
  | .insert _ _ returning .. | .update _ _ _ returning .. | .upsert _ _ _ returning .. | .delete _ _ returning .. =>
    returning.map (·.2)
  | .createTable .. | .createIndex .. | .createTrigger .. | .addColumn .. | .drop .. | .begin | .commit | .rollback
  | .prepareError _ | .setting _ => []

/-- The names of the result columns of each statement, on the connection before it: the
connection that the run of the statements before it, with their values and the optional
clock, reaches ({name}`runScriptFrom`). A statement that does not resolve has none. -/
def scriptResultNames (context : ResolveContext) (clock : Option Clock) (connection : Connection)
    (statements : List (Syntax.Statement × List Value)) : List (List String) :=
  statements.zipIdx.map fun ((statement, _), index) =>
    let before := (runScriptFrom context clock 0 connection (statements.take index)).connection
    match resolveStatement context before.resolveState statement with
    | .ok (resolved, _) => resolved.resultNames
    | .error _ => []

/-- The value as a cell of a table: a text as its characters, without quotes; NULL as
{lit}`NULL`; another value as {name}`Value.display` shows it. -/
def Value.cellText : Value → String
  | .null => "NULL"
  | .text bytes => match String.fromUTF8? ⟨bytes.toArray⟩ with
    | some decoded => decoded
    | none => s!"text x'{hexBytes bytes}'"
  | value@(.integer _) | value@(.real _) | value@(.blob _) => toString (Value.display value)

/-- The lines of a table: the names, then one line for each row, each cell padded to the width
of its column, with {lit}`" | "` between the cells and no space at the end of a line. -/
def textTable (names : List String) (rows : List (List String)) : String :=
  let lines := names :: rows
  let widths := (List.range names.length).map fun column =>
    lines.foldl (fun width line => max width ((line[column]?.getD "").length)) 0
  let render := fun (line : List String) =>
    (" | ".intercalate ((line.zip widths).map fun (cell, width) => cell.pushn ' ' (width - cell.length))).trimAsciiEnd.toString
  "\n".intercalate (lines.map render)

/-- The output as text, with the names of the result columns: rows as a table
({name}`textTable`); for {name}`Output.oneOf`, the number of results and each result as a table;
another output as its {lit}`Repr` writes it. -/
def Output.table (names : List String) : Output → String
  | .rows found => textTable names (found.map (·.map Value.cellText))
  | .oneOf results => s!"one of {results.length} results:" ++
    String.join (results.map fun result => "\n\n" ++ textTable names (result.map (·.map Value.cellText)))
  | output@(.done _) | output@(.error _) | output@(.unmodeled _) => toString (repr output)

end Belay.Sqlite.Model
