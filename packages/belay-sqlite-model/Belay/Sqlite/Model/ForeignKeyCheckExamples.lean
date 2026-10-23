import Belay.Sqlite.Model.ValidityExamples
import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! Examples of {lit}`PRAGMA foreign_key_check` (ADR 0019, D2), each checked by the kernel. With
foreign keys off, the writes store child rows without a parent, which the pragma reports. The
rows and errors are SQLite's (3.51.0, checked natively with the {lit}`sqlite3` shell). The order of
the rows shows in {name}`Belay.Sqlite.Model.Database.foreignKeyCheckRows`; a query without
{lit}`ORDER BY` gives them in normal form. -/

namespace Belay.Sqlite.Model.ForeignKeyCheckExamples

open Belay.Sqlite.Model Syntax Resolution.Examples ValidityExamples

/-- The outputs of a run of the statements from the empty database, with the default profile. -/
def outputs (script : List Syntax.Statement) : List Output :=
  (runScriptFrom { profile := defaults, mode := .execution } none 0 { state := { database := {} } }
    (script.map (·, []))).outputs

/-- A column without a type that references the table {lit}`parent`, at the columns. -/
def refers (column parent : String) (columns : List String := []) : ColumnDefinition :=
  typed column none [.references (.ofString parent) (columns.map .ofString) .noAction .noAction]

/-- {lit}`CREATE TABLE p(x, y UNIQUE)`, {lit}`CREATE TABLE c2(a REFERENCES q)` and
{lit}`CREATE TABLE w(k PRIMARY KEY, a REFERENCES q, b REFERENCES p(y)) WITHOUT ROWID`, with the row
1 of {lit}`c2` and the rows {lit}`(1, 2, 3)` and {lit}`(0, NULL, 4)` of {lit}`w`. No table
{lit}`q` exists. -/
def orphans : List Syntax.Statement :=
  [.createTable (name! "p") [typed "x" none, typed "y" none [.unique]] [],
   .createTable (name! "c2") [refers "a" "q"] [], .insert (name! "c2") none [[.numeric "1"]] [],
   .createTable (name! "w") [typed "k" none [.primaryKey false], refers "a" "q", refers "b" "p" ["y"]] []
     { withoutRowid := true },
   .insert (name! "w") none [[.numeric "1", .numeric "2", .numeric "3"], [.numeric "0", .null, .numeric "4"]] []]

/-- The rows of the pragma with the table name, the rowid, the parent and the id. -/
def keyRow (table : String) (rowid : Option Int) (parent : String) (id : Int) : List Value :=
  [textValue table, (rowid.map Value.integer).getD .null, textValue parent, .integer id]

-- For each row in scan order, for each key by id: the key of the last column has id 0. A NULL
-- satisfies its key, and a missing parent table finds no row. A WITHOUT ROWID table has no rowid.
example : (built orphans).foreignKeyCheckRows (some 2) =
    some [keyRow "w" none "p" 0, keyRow "w" none "p" 0, keyRow "w" none "q" 1] := by decide +kernel
example : outputs (orphans ++ [.pragma (.foreignKeyCheck (some (name! "C2"))), .pragma (.foreignKeyCheck (some (name! "p")))]) =
    [.done 0, .done 0, .done 1, .done 0, .done 2, .rows [keyRow "c2" (some 1) "q" 0], .rows []] := by decide +kernel
-- Without a table name, two tables with rows give no result; a missing table fails at prepare.
example : (outputs (orphans ++ [.pragma (.foreignKeyCheck none)])).getLast?.map Output.endsRun = some true := by
  decide +kernel
example : (outputs [.pragma (.foreignKeyCheck (some (name! "nosuch")))]) = [.error 1] := by decide +kernel
-- The rows are no rows exactly when the foreign keys hold.
example : (built orphans).foreignKeyCheckRows none = none ∧ ¬(built orphans).ForeignKeysHold := by decide +kernel
example : (built (orphans.take 2)).foreignKeyCheckRows none = some [] ∧ (built (orphans.take 2)).ForeignKeysHold := by
  decide +kernel

/-- {lit}`CREATE TABLE c1(a REFERENCES p(x))`, whose parent column has no unique index. -/
def mismatched (table : String) : Syntax.Statement := .createTable (.ofString table) [refers "a" "p" ["x"]] []

-- A mismatch fails at prepare, before any row, also when another table gives rows. Two tables
-- with a mismatch are a restriction, because SQLite reports the first in its own order.
example : (statements (migration [] (orphans ++ [mismatched "c1", .pragma (.foreignKeyCheck none)]))).getLast? =
    some (.prepareError (.foreignKeyMismatch (name! "c1") (name! "p"))) := by decide +kernel
example : (statements (migration [] (orphans ++ [mismatched "c1", .pragma (.foreignKeyCheck (some (name! "c2")))]))).getLast?.map
    (·.isControl) = some false := by decide +kernel
example : restricted (migration [] (orphans ++ [mismatched "c1", mismatched "c3", .pragma (.foreignKeyCheck none)])) = true := by
  decide +kernel

end Belay.Sqlite.Model.ForeignKeyCheckExamples
