import Belay.Sqlite.Model.Resolution.JoinExamples
import Belay.Sqlite.Model.QueryRun

set_option doc.verso true

/-! Examples of the source list in written order (ADR 0013, D5), checked by {lit}`#guard`:
{lit}`json_each` before a table, {lit}`LEFT JOIN json_each` with a correlated argument, the
forms that stay restricted, and two sources with the same name. Each row list was checked on native SQLite 3.51.0 with
the same schema and rows. -/

namespace Belay.Sqlite.Model.Resolution.SourceListExamples
open Belay.Sqlite.Model Syntax Resolution.Examples Resolution.JoinExamples

/-- The text value of a string. -/
def text (value : String) : Value := .text value.toUTF8.toList

/-- The database over {name}`tables`: {lit}`t` has the rows {lit}`(1, '[1,2]')` and
{lit}`(2, '[]')`, and {lit}`u` has no row. -/
def database : Database :=
  { catalog := tables,
    rows := [[{ rowid := 1, values := [.integer 1, text "[1,2]"] }, { rowid := 2, values := [.integer 2, text "[]"] }],
      []] }

/-- {lit}`json_each(argument) AS alias`. -/
def each (alias : Identifier) (argument : Expr) : TableReference :=
  { table := (name! "json_each"), alias := some alias, arguments := some [argument] }

/-- The query of a resolved statement; none for any other statement and for no statement. -/
def queryOf : Option Resolved.Statement → Option Resolved.Query
  | some (.query query _) => some query
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.update ..) | some (.upsert ..) | some (.delete ..)
  | some (.prepareError _) | none => none

/-- The result rows of a {lit}`SELECT` with these result columns and sources over
{name}`database`; none when it does not resolve to a query or a table is missing. -/
def rowsOf (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option (List (List Value)) :=
  (queryOf (resolvedOne results source joins)).bind fun query =>
    (query.source (.plain 0) database).map fun source => query.results (.plain 0) source.rows

/-- A result column of {lit}`x.c`. -/
def named (source column : Identifier) : ResultColumn :=
  .expression (qualified source column) none s!"{source.text}.{column.text}"

-- `SELECT e.value, t.a FROM json_each('[5,6]') AS e, t`: a table after json_each. Native SQLite
-- scans `t` first; without ORDER BY the order of the rows is not defined.
#guard rowsOf [named (name! "e") (name! "value"), named (name! "t") (name! "a")] (each (name! "e") (.string "[5,6]".toUTF8.toList)) [joined [] (table (name! "t"))] ==
  some [[.integer 5, .integer 1], [.integer 5, .integer 2], [.integer 6, .integer 1], [.integer 6, .integer 2]]
-- `SELECT t.a, e.value FROM t LEFT JOIN json_each(t.b) AS e`: the row without an element is padded.
#guard rowsOf [named (name! "t") (name! "a"), named (name! "e") (name! "value")] (table (name! "t")) [joined ["LEFT"] (each (name! "e") (qualified (name! "t") (name! "b")))] ==
  some [[.integer 1, .integer 1], [.integer 1, .integer 2], [.integer 2, .null]]
-- `SELECT t.a, e.value FROM t JOIN json_each(t.b) AS e`: an inner join keeps no row for `[]`.
#guard rowsOf [named (name! "t") (name! "a"), named (name! "e") (name! "value")] (table (name! "t")) [joined [] (each (name! "e") (qualified (name! "t") (name! "b")))] ==
  some [[.integer 1, .integer 1], [.integer 1, .integer 2]]
-- json_each as the right operand of RIGHT JOIN, and with NATURAL or USING, is restricted.
#guard restrictedOne [.star] (table (name! "t")) [joined ["RIGHT"] (each (name! "e") (qualified (name! "t") (name! "b")))]
#guard restrictedOne [.star] (table (name! "t")) [joined ["NATURAL"] (each (name! "e") (qualified (name! "t") (name! "b")))]
#guard restrictedOne [.star] (table (name! "t")) [{ joined [] (each (name! "e") (qualified (name! "t") (name! "b"))) with usingColumns := some [(name! "a")] }]
-- NATURAL after json_each is restricted: SQLite skips the hidden columns `json` and `root`.
#guard restrictedOne [.star] (each (name! "e") (qualified (name! "t") (name! "b"))) [joined ["NATURAL"] (table (name! "u"))]
-- An argument that reads a later source is restricted, also when the later source is a table.
#guard restrictedOne [.star] (each (name! "e") (qualified (name! "t") (name! "b"))) [joined [] (table (name! "t"))]

/-- The resolution of {lit}`SELECT results FROM t, t`, two sources with the same name. -/
def overTwice (results : List ResultColumn) (joins : List Join := [joined [] (table (name! "t"))]) : Option Resolved.Statement :=
  resolvedOne results (table (name! "t")) joins

-- `SELECT count(*) FROM t, t` counts every pair of rows: 4.
#guard rowsOf [.expression (.callStar "count") none "count(*)"] (table (name! "t")) [joined [] (table (name! "t"))] ==
  some [[.integer 4]]
-- Over two sources named `t`, a name, a qualified name, `t.*` and `*` are ambiguous; the
-- expansion of a star names the schema, the source and the declared column.
#guard overTwice [.expression (.identifier (name! "a") .none) none "a"] == some (.prepareError (.expression (.ambiguousColumn (name! "a"))))
#guard overTwice [.expression (qualified (name! "t") (name! "a")) none "t.a"] == some (.prepareError (.expression (.ambiguousColumn (name! "t.a"))))
#guard overTwice [.sourceStar (name! "t")] == some (.prepareError (.expression (.ambiguousColumn (name! "main.t.a"))))
#guard overTwice [.star] == some (.prepareError (.expression (.ambiguousColumn (name! "main.t.a"))))
-- A source is named by its alias, else by the table name as declared: `FROM T, t`.
#guard resolvedOne [.star] (table (name! "T")) [joined [] (table (name! "t"))] == some (.prepareError (.expression (.ambiguousColumn (name! "main.t.a"))))
-- `FROM t JOIN t USING (a)`: `t.a` is the left column, `t.b` and `*` are ambiguous.
#guard (queryOf (overTwice [.expression (qualified (name! "t") (name! "a")) none "t.a"]
  [{ joined [] (table (name! "t")) with usingColumns := some [(name! "a")] }])).map (·.columns) == some [.scalar (.column 0)]
#guard overTwice [.expression (qualified (name! "t") (name! "b")) none "t.b"] [{ joined [] (table (name! "t")) with usingColumns := some [(name! "a")] }] ==
  some (.prepareError (.expression (.ambiguousColumn (name! "t.b"))))
#guard overTwice [.star] [{ joined [] (table (name! "t")) with usingColumns := some [(name! "a")] }] ==
  some (.prepareError (.expression (.ambiguousColumn (name! "main.t.b"))))
-- `SELECT t.c FROM t, u AS t`: only the second source named `t` has `c`.
#guard (queryOf (resolvedOne [.expression (qualified (name! "t") (name! "c")) none "t.c"] (table (name! "t"))
  [joined [] { table := (name! "u"), alias := some (name! "t") }])).map (·.columns) == some [.scalar (.column 3)]

end Belay.Sqlite.Model.Resolution.SourceListExamples
