import Belay.Sqlite.Resolution.RightJoinExamples

set_option doc.verso true

/-! Examples of {lit}`USING` and {lit}`NATURAL` with right and full joins (ADR 0012,
amendment 3; slice 4d), checked by {lit}`#guard`: the operand of an unqualified merged
name for each kind of join and for chains, {lit}`*`, the coalesced left side of a later
{lit}`USING`, and SQLite's {lit}`ambiguous reference to a in USING()`. -/

namespace Belay.Sqlite.Resolution.MergedNameExamples
open Belay.Sqlite Syntax Resolution.Examples Resolution.JoinExamples Resolution.UsingExamples

/-- {lit}`t(a INTEGER, b TEXT)`, {lit}`r(a REAL, e TEXT)`, {lit}`u(A INTEGER, c TEXT)`,
{lit}`w(a, f TEXT)`, whose {lit}`a` has no declared type, and {lit}`v(a INTEGER, d TEXT)`,
at positions 0 to 4; each has two columns. -/
def merging : Catalog := catalogOf (schema [.createTable "t" [column "a" (some "INTEGER"), column "b"] [],
  .createTable "r" [column "a" (some "REAL"), column "e"] [],
  .createTable "u" [column "A" (some "INTEGER"), column "c"] [],
  .createTable "w" [column "a" none, column "f"] [],
  .createTable "v" [column "a" (some "INTEGER"), column "d"] []])

/-- The query of a {lit}`SELECT` over {name}`merging`, if it resolves to one. -/
def query (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option Resolved.Query :=
  match (statements (migration merging [.select results (some source) joins none [] [] none none])).head? with
  | some (.query query) => some query
  | some (.createTable ..) | some (.createIndex ..) | some (.addColumn ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.prepareError _) | some (.clocked ..) | none => none

/-- The prepare error of a {lit}`SELECT` over {name}`merging`, if it has one. -/
def error (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option PrepareError :=
  match (statements (migration merging [.select results (some source) joins none [] [] none none])).head? with
  | some (.prepareError error) => some error
  | some (.createTable ..) | some (.createIndex ..) | some (.addColumn ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.query _) | some (.clocked ..) | none => none

/-- The result columns of {lit}`SELECT a` over the joins from {lit}`t`. -/
def bareA (joins : List Join) : Option (List Resolved.Output) := (query [bare "a"] (table "t") joins).map (·.columns)

/-- {lit}`t.b = r.e`, a written condition of two TEXT columns. -/
def onText : Expr := .equals (qualified "t" "b") (qualified "r" "e")

-- An inner or left join keeps the left column; a right join takes its own; a full join coalesces.
#guard bareA [usingJoin [] "r" ["a"]] == some [.scalar (.column 0)]
#guard bareA [usingJoin ["RIGHT"] "r" ["a"]] == some [.scalar (.column 2)]
#guard bareA [usingJoin ["FULL"] "r" ["a"]] == some [.scalar (.coalesce (.column 0) (.column 2))]
-- Chains: full then full, right then full, full then right, full then inner, left then full.
#guard bareA [usingJoin ["FULL"] "r" ["a"], usingJoin ["FULL"] "w" ["a"]] ==
  some [.scalar (.coalesce (.column 0) (.coalesce (.column 2) (.column 4)))]
#guard bareA [usingJoin ["RIGHT"] "r" ["a"], usingJoin ["FULL"] "w" ["a"]] ==
  some [.scalar (.coalesce (.column 2) (.column 4))]
#guard bareA [usingJoin ["FULL"] "r" ["a"], usingJoin ["RIGHT"] "w" ["a"]] == some [.scalar (.column 4)]
#guard bareA [usingJoin ["FULL"] "r" ["a"], usingJoin [] "w" ["a"]] ==
  some [.scalar (.coalesce (.column 0) (.column 2))]
#guard bareA [usingJoin ["LEFT"] "r" ["a"], usingJoin ["FULL"] "w" ["a"]] ==
  some [.scalar (.coalesce (.column 0) (.column 4))]
-- `*` shows the merged name at the left column's place, under the left column's name.
#guard (query [.star] (table "t") [usingJoin ["FULL"] "r" ["a"]]).map (fun query => (query.columns, query.names)) ==
  some ([.scalar (.coalesce (.column 0) (.column 2)), .scalar (.column 1), .scalar (.column 3)], ["a", "b", "e"])
#guard (query [.star] (table "u") [usingJoin ["RIGHT"] "t" ["a"]]).map (fun query => (query.columns, query.names)) ==
  some ([.scalar (.column 2), .scalar (.column 1), .scalar (.column 3)], ["A", "c", "b"])
-- `x.*` of the left table of a full or right join shows the merged name; of the right table, its own.
#guard (query [.sourceStar "t", .sourceStar "r"] (table "t") [usingJoin ["FULL"] "r" ["a"]]).map (·.columns) ==
  some [.scalar (.coalesce (.column 0) (.column 2)), .scalar (.column 1), .scalar (.column 2), .scalar (.column 3)]
#guard (query [.sourceStar "t"] (table "t") [usingJoin ["RIGHT"] "r" ["a"]]).map (·.columns) ==
  some [.scalar (.column 2), .scalar (.column 1)]
#guard (query [.sourceStar "t"] (table "t") [usingJoin ["LEFT"] "r" ["a"]]).map (·.columns) ==
  some [.scalar (.column 0), .scalar (.column 1)]
-- A bare merged name is named as declared for one column, and as written for a coalesce.
#guard (query [bare "A"] (table "t") [usingJoin ["RIGHT"] "u" ["a"]]).map (·.names) == some ["A"]
#guard (query [bare "A"] (table "t") [usingJoin ["FULL"] "u" ["a"]]).map (·.names) == some ["A"]
#guard (query [bare "A"] (table "t") [usingJoin [] "u" ["a"]]).map (·.names) == some ["a"]
-- With a right or full join, a later USING compares the coalesce of the left columns.
#guard (query [.star] (table "t") [usingJoin ["FULL"] "r" ["a"], usingJoin [] "w" ["a"]]).map
  (·.joins.map (·.condition)) ==
  some [some (.compare .eq (.column 0) (.column 2)),
        some (.compare .eq (.coalesce (.column 0) (.column 2)) (.column 4))]
-- Without one, it compares the left-most column, as in slice 4b.
#guard (query [.star] (table "t") [usingJoin [] "r" ["a"], usingJoin [] "v" ["a"]]).map
  (·.joins.map (·.condition)) ==
  some [some (.compare .eq (.column 0) (.column 2)), some (.compare .eq (.column 0) (.column 4))]
-- A coalesce has no affinity, so against an INTEGER column it would convert text: a restriction.
#guard reason (migration merging [.select [.star] (some (table "t")) [usingJoin ["FULL"] "r" ["a"], usingJoin [] "v" ["a"]]
  none [] [] none none]) == RestrictionKind.textToNumber.message
-- A left table that does not merge the name: also for a join before the right join, and for NATURAL.
#guard error [.star] (table "t") [joined [] (table "r") (some onText), usingJoin ["RIGHT"] "w" ["a"]] ==
  some (.ambiguousUsingReference "a")
#guard error [.star] (table "t")
  [joined [] (table "r") (some onText), usingJoin [] "w" ["a"], joined ["RIGHT"] (table "u") (some onA)] ==
  some (.ambiguousUsingReference "a")
#guard error [.star] (table "t") [joined [] (table "r") (some onText), joined ["NATURAL", "FULL"] (table "w")] ==
  some (.ambiguousUsingReference "a")
-- The errors of slice 4b still come first in their join.
#guard error [.star] (table "t") [usingJoin ["RIGHT"] "r" ["zz"]] == some (.joinUsingColumn "zz")


end Belay.Sqlite.Resolution.MergedNameExamples
