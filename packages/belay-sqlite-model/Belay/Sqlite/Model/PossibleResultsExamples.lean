import Belay.Sqlite.Model.PossibleResults
import Belay.Sqlite.Model.SqlExecution
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the results that SQLite may give (ADR 0018, D6), each checked by the kernel: the
guide's row order cases, a window that cuts one or two tie groups, the guide's pagination with
equal priorities, and {lit}`DISTINCT` and {lit}`GROUP BY` with {lit}`LIMIT`. -/

namespace Belay.Sqlite.Model.PossibleResultsExamples

open Belay.Sqlite.Model Syntax Resolution.Examples

/-- A column with the type, or none. -/
def plain (text : String) (declaredType : Option String := none) : ColumnDefinition :=
  { name := Identifier.ofString text, declaredType, constraints := [] }

/-- A name as written. -/
def name (text : String) : Expr := .identifier (Identifier.ofString text) .none

/-- A text literal. -/
def text (value : String) : Expr := .string value.toUTF8.toList

/-- A text value. -/
def textValue (value : String) : Value := .text value.toUTF8.toList

/-- {lit}`SELECT columns FROM t [ORDER BY terms] [LIMIT limit] [OFFSET offset]`, with
{lit}`DISTINCT` and {lit}`GROUP BY` terms when given. -/
def selectT (columns : List Expr) (orderBy : List OrderTerm := []) (limit offset : Option Nat := none)
    (groupBy : List Expr := []) (distinct : Bool := false) : Syntax.Statement :=
  .select (columns.map fun column => .expression column none "") (some { table := Identifier.ofString "t", alias := none })
    [] none groupBy orderBy (limit.map fun n => .numeric (toString n)) (offset.map fun n => .numeric (toString n)) []
    none distinct

/-- An ascending {lit}`ORDER BY` term of a column. -/
def ascending (column : String) : OrderTerm := { expression := name column, descending := false }

/-- The results that SQLite may give for the last statement of the script, a query, after the
statements before it from the empty catalog. -/
def possible (script : List Syntax.Statement) : Option (List (List (List Value))) :=
  match (statements (migration [] script)).reverse with
  | (.query query subqueries) :: earlier =>
    let database := (runSql (bindValues earlier.reverse []) {}).database
    query.possibleOn 0 [] database subqueries
  | (.createTable ..) :: _ | (.createIndex ..) :: _ | (.createTrigger ..) :: _ | (.addColumn ..) :: _ | (.drop ..) :: _
  | .begin :: _ | .commit :: _ | .rollback :: _ | (.insert ..) :: _ | (.upsert ..) :: _ | (.update ..) :: _
  | (.delete ..) :: _ | (.prepareError _) :: _ | (.setting ..) :: _ | [] => none

/-- {lit}`CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, p INTEGER)` with rows. -/
def withRows (rows : List (List Expr)) : List Syntax.Statement :=
  [.createTable (name! "t") [plain "id" (some "INTEGER"), plain "name" (some "TEXT"), plain "p" (some "INTEGER")] [],
   .insert (name! "t") none rows []]

/-- The guide's customers: bob before ada in rowid order. -/
def customers : List Syntax.Statement :=
  withRows [[.numeric "1", text "bob", .numeric "1"], [.numeric "2", text "ada", .numeric "1"]]

-- Without ORDER BY, one result in normal form: ada, bob.
example : possible (customers ++ [selectT [name "name"]]) = some [[[textValue "ada"], [textValue "bob"]]] := by
  decide +kernel
-- LIMIT 1 without ORDER BY: ada or bob.
example : possible (customers ++ [selectT [name "name"] [] (some 1)]) =
    some [[[textValue "bob"]], [[textValue "ada"]]] := by decide +kernel
-- When every choice gives the same rows, one result.
example : possible (customers ++ [selectT [.numeric "1"] [] (some 1)]) = some [[[.integer 1]]] := by decide +kernel
-- ORDER BY with ties: the tied rows in normal form.
example : possible (customers ++ [selectT [name "name"] [ascending "p"]]) =
    some [[[textValue "ada"], [textValue "bob"]]] := by decide +kernel

/-- Three rows of priority 1 and one of priority 2. -/
def jobs : List Syntax.Statement :=
  withRows [[.numeric "1", text "a", .numeric "1"], [.numeric "2", text "b", .numeric "1"],
    [.numeric "3", text "c", .numeric "1"], [.numeric "4", text "d", .numeric "2"]]

-- OFFSET 1 LIMIT 1 in one group of three: any of the three.
example : possible (jobs ++ [selectT [name "name"] [ascending "p"] (some 1) (some 1)]) =
    some [[[textValue "a"]], [[textValue "b"]], [[textValue "c"]]] := by decide +kernel
-- OFFSET 2 LIMIT 2 over two groups: one of the first group, then d.
example : possible (jobs ++ [selectT [name "name"] [ascending "p"] (some 2) (some 2)]) =
    some [[[textValue "a"], [textValue "d"]], [[textValue "b"], [textValue "d"]], [[textValue "c"], [textValue "d"]]] := by
  decide +kernel
-- Pagination: pages 0 and 1 of size 2 over ties may share a row, as page 1 may give a again.
#guard ((possible (jobs ++ [selectT [name "name"] [ascending "p"] (some 2) (some 2)])).getD []).any
  (·.contains [textValue "a"])
#guard ((possible (jobs ++ [selectT [name "name"] [ascending "p"] (some 2) none])).getD []).any
  (·.contains [textValue "a"])
-- DISTINCT and GROUP BY with LIMIT: the distinct priorities, or the groups, one of two.
example : possible (jobs ++ [selectT [name "p"] [] (some 1) none [] true]) = some [[[.integer 1]], [[.integer 2]]] := by
  decide +kernel
example : possible (jobs ++ [selectT [name "p"] [] (some 1) none [name "p"]]) = some [[[.integer 1]], [[.integer 2]]] := by
  decide +kernel

-- The normal form is one list for any input order: NULL comes before a NaN REAL, which
-- Value.compare alone would call equal, and the integer 1 before the real 1.0.
example : Resolved.normalForm [[.real 0x7FF8000000000000], [.null]] = Resolved.normalForm [[.null], [.real 0x7FF8000000000000]] := by
  decide +kernel
example : Resolved.normalForm [[.real 0x3FF0000000000000], [.integer 1]] = [[.integer 1], [.real 0x3FF0000000000000]] := by
  decide +kernel

end Belay.Sqlite.Model.PossibleResultsExamples
