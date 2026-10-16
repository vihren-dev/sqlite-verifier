import Belay.Sqlite.Resolution.Examples
import Belay.Sqlite.QueryJoins

set_option doc.verso true

/-! Examples of joins (ADR 0012, amendment 2, slice 4), checked by {lit}`#guard`: the
resolution of sources and names, SQLite's prepare errors, the restrictions, and the rows
of inner and left joins. -/

namespace Belay.Sqlite.Resolution.JoinExamples
open Belay.Sqlite Syntax Resolution.Examples

/-- A catalog with {lit}`t(a INTEGER, b TEXT)` at position 0 and {lit}`u(a INTEGER, c TEXT)`
at position 1. -/
def tables : Catalog := catalogOf (schema [.createTable "t" [column "a" (some "INTEGER"), column "b"] [],
  .createTable "u" [column "a" (some "INTEGER"), column "c"] []])

/-- A table reference without an alias. -/
def table (name : String) : TableReference := { table := name, alias := none }

/-- A join with the operator keywords to a table, with an optional ON condition. -/
def joined (operator : List String) (source : TableReference) (condition : Option Expr := none) : Join :=
  { operator, source, condition, usingColumns := none }

/-- {lit}`x.c` as written. -/
def qualified (source column : String) : Expr := .qualified source column

/-- {lit}`t.a = u.a`. -/
def onA : Expr := .equals (qualified "t" "a") (qualified "u" "a")

/-- The single statement of a resolution of a {lit}`SELECT *` with these sources. -/
def resolvedOne (results : List ResultColumn) (source : TableReference) (joins : List Join)
    (filter : Option Expr := none) : Option Resolved.Statement :=
  (statements (migration tables [.select results (some source) joins filter [] [] none none])).head?

/-- Whether the resolution is a model restriction. -/
def restrictedOne (results : List ResultColumn) (source : TableReference) (joins : List Join) : Bool :=
  restricted (migration tables [.select results (some source) joins none [] [] none none])

/-- The resolved join of {lit}`u` on {lit}`t.a = u.a`: the cell of {lit}`u.a` follows the two
cells of {lit}`t`. -/
def joinU : Resolved.Join := { kind := .inner, table := 1, condition := some (.compare .eq (.column 0) (.column 2)) }

-- An inner join: `*` names the columns of both tables, and ON reads the joined row.
#guard resolvedOne [.star] (table "t") [joined [] (table "u") (some onA)] ==
  some (.query { table := some 0, joins := [joinU], filter := none, aggregate := false, groupBy := [],
                 columns := [.scalar (.column 0), .scalar (.column 1), .scalar (.column 2), .scalar (.column 3)],
                 names := ["a", "b", "a", "c"], orderBy := [], offset := 0, limit := none })
-- An unqualified name of a column of both tables is SQLite's ambiguous column name.
#guard resolvedOne [.expression (.identifier "a" false) none "a"] (table "t") [joined [] (table "u")] ==
  some (.prepareError (.ambiguousColumn "a"))
-- An alias hides the table name; an unknown qualifier names no column; `x.*` of no source.
#guard resolvedOne [.expression (qualified "t" "a") none "t.a"] { table := "t", alias := some "x" } [] ==
  some (.prepareError (.noSuchColumn "t.a"))
#guard resolvedOne [.sourceStar "zz"] (table "t") [] == some (.prepareError (.noSuchSource "zz"))
-- `x.*` in RETURNING is SQLite's prepare error, after the errors of the write itself.
#guard (statements (migration tables [.returning (.delete "t" none) [.star, .sourceStar "t"]])).head? ==
  some (.prepareError .returningSourceStar)
-- SQLite expands the wildcards first: `t.*` wins over a missing name in an earlier column.
#guard (statements (migration tables
  [.returning (.delete "t" none) [.expression (.identifier "zz" false) none "zz", .sourceStar "t"]])).head? ==
  some (.prepareError .returningSourceStar)
#guard (statements (migration tables
  [.returning (.delete "t" (some (.identifier "zz" false))) [.sourceStar "t"]])).head? ==
  some (.prepareError (.noSuchColumn "zz"))
-- 65 tables are SQLite's limit error.
#guard resolvedOne [.star] (table "t") ((List.range 64).map fun item =>
  joined [] { table := "t", alias := some s!"t{item}" }) == some (.prepareError .tooManyTables)
-- Another operator and two sources with the same name are restrictions.
#guard restrictedOne [.star] (table "t") [joined ["OUTER", "LEFT"] (table "u") (some onA)]
#guard restrictedOne [.star] (table "t") [joined ["INNER"] (table "t")]
-- Lean reads the operator keywords without ASCII case.
#guard joinOperator ["Left", "outer"] == some (.left, false)
#guard joinOperator ["NATURAL", "cross"] == some (.inner, true)
#guard joinOperator ["left", "inner"] == none

/-- A table of two rows, with {lit}`a` 1 and 2. -/
def left : Table :=
  { shape := { columns := [{ name := "a", declaredType := some "INTEGER" }] },
    rows := [{ rowid := 1, values := [.integer 1] }, { rowid := 2, values := [.integer 2] }] }

/-- A table of one row, with {lit}`a` 1. -/
def right : Table :=
  { shape := { columns := [{ name := "a", declaredType := some "INTEGER" }] },
    rows := [{ rowid := 1, values := [.integer 1] }] }

/-- The join condition {lit}`left.a = right.a` over the joined row. -/
def equal : Option Resolved.Expr := some (.compare .eq (.column 0) (.column 1))

-- An inner join keeps the matching row; a left join also pads the unmatched left row.
#guard Resolved.joinRows 1 (Resolved.sourceRows left) { kind := .inner, table := 1, condition := equal } right ==
  [[.integer 1, .integer 1]]
#guard Resolved.joinRows 1 (Resolved.sourceRows left) { kind := .left, table := 1, condition := equal } right ==
  [[.integer 1, .integer 1], [.integer 2, .null]]

end Belay.Sqlite.Resolution.JoinExamples
