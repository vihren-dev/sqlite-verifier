import Belay.Sqlite.Model.Resolution.RightJoinExamples

set_option doc.verso true

/-! Examples of {lit}`USING` and {lit}`NATURAL` with right and full joins (ADR 0012,
amendment 3; slice 4d), checked by {lit}`#guard`: the operand of an unqualified merged
name for each kind of join and for chains, {lit}`*`, the coalesced left side of a later
{lit}`USING`, and SQLite's {lit}`ambiguous reference to a in USING()`. -/

namespace Belay.Sqlite.Model.Resolution.MergedNameExamples
open Belay.Sqlite.Model Syntax Resolution.Examples Resolution.JoinExamples Resolution.UsingExamples

/-- {lit}`t(a INTEGER, b TEXT)`, {lit}`r(a REAL, e TEXT)`, {lit}`u(A INTEGER, c TEXT)`,
{lit}`w(a, f TEXT)`, whose {lit}`a` has no declared type, and {lit}`v(a INTEGER, d TEXT)`,
at positions 0 to 4; each has two columns. -/
def merging : Catalog := catalogOf (schema [.createTable (name! "t") [column (name! "a") (some "INTEGER"), column (name! "b")] [],
  .createTable (name! "r") [column (name! "a") (some "REAL"), column (name! "e")] [],
  .createTable (name! "u") [column (name! "A") (some "INTEGER"), column (name! "c")] [],
  .createTable (name! "w") [column (name! "a") none, column (name! "f")] [],
  .createTable (name! "v") [column (name! "a") (some "INTEGER"), column (name! "d")] []])

/-- The query of a {lit}`SELECT` over {name}`merging`, if it resolves to one. -/
def query (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option Resolved.Query :=
  match (statements (migration merging [.select results (some source) joins none [] [] none none])).head? with
  | some (.query query _) => some query
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.prepareError _) | none => none

/-- The prepare error of a {lit}`SELECT` over {name}`merging`, if it has one. -/
def error (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option PrepareError :=
  match (statements (migration merging [.select results (some source) joins none [] [] none none])).head? with
  | some (.prepareError error) => some error
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.query ..) | none => none

/-- The result columns of {lit}`SELECT a` over the joins from {lit}`t`. -/
def bareA (joins : List Join) : Option (List Resolved.Output) := (query [bare (name! "a")] (table (name! "t")) joins).map (·.columns)

/-- {lit}`t.b = r.e`, a written condition of two TEXT columns. -/
def onText : Expr := .compare .eq (qualified (name! "t") (name! "b")) (qualified (name! "r") (name! "e"))

-- An inner or left join keeps the left column; a right join takes its own; a full join coalesces.
#guard bareA [usingJoin [] (name! "r") [(name! "a")]] == some [.scalar (.column 0)]
#guard bareA [usingJoin ["RIGHT"] (name! "r") [(name! "a")]] == some [.scalar (.column 2)]
#guard bareA [usingJoin ["FULL"] (name! "r") [(name! "a")]] == some [.scalar (.coalesce (.column 0) (.column 2))]
-- Chains: full then full, right then full, full then right, full then inner, left then full.
#guard bareA [usingJoin ["FULL"] (name! "r") [(name! "a")], usingJoin ["FULL"] (name! "w") [(name! "a")]] ==
  some [.scalar (.coalesce (.column 0) (.coalesce (.column 2) (.column 4)))]
#guard bareA [usingJoin ["RIGHT"] (name! "r") [(name! "a")], usingJoin ["FULL"] (name! "w") [(name! "a")]] ==
  some [.scalar (.coalesce (.column 2) (.column 4))]
#guard bareA [usingJoin ["FULL"] (name! "r") [(name! "a")], usingJoin ["RIGHT"] (name! "w") [(name! "a")]] == some [.scalar (.column 4)]
#guard bareA [usingJoin ["FULL"] (name! "r") [(name! "a")], usingJoin [] (name! "w") [(name! "a")]] ==
  some [.scalar (.coalesce (.column 0) (.column 2))]
#guard bareA [usingJoin ["LEFT"] (name! "r") [(name! "a")], usingJoin ["FULL"] (name! "w") [(name! "a")]] ==
  some [.scalar (.coalesce (.column 0) (.column 4))]
-- `*` shows the merged name at the left column's place, under the left column's name.
#guard (query [.star] (table (name! "t")) [usingJoin ["FULL"] (name! "r") [(name! "a")]]).map (fun query => (query.columns, query.names)) ==
  some ([.scalar (.coalesce (.column 0) (.column 2)), .scalar (.column 1), .scalar (.column 3)], ["a", "b", "e"])
#guard (query [.star] (table (name! "u")) [usingJoin ["RIGHT"] (name! "t") [(name! "a")]]).map (fun query => (query.columns, query.names)) ==
  some ([.scalar (.column 2), .scalar (.column 1), .scalar (.column 3)], ["A", "c", "b"])
-- `x.*` of the left table of a full or right join shows the merged name; of the right table, its own.
#guard (query [.sourceStar (name! "t"), .sourceStar (name! "r")] (table (name! "t")) [usingJoin ["FULL"] (name! "r") [(name! "a")]]).map (·.columns) ==
  some [.scalar (.coalesce (.column 0) (.column 2)), .scalar (.column 1), .scalar (.column 2), .scalar (.column 3)]
#guard (query [.sourceStar (name! "t")] (table (name! "t")) [usingJoin ["RIGHT"] (name! "r") [(name! "a")]]).map (·.columns) ==
  some [.scalar (.column 2), .scalar (.column 1)]
#guard (query [.sourceStar (name! "t")] (table (name! "t")) [usingJoin ["LEFT"] (name! "r") [(name! "a")]]).map (·.columns) ==
  some [.scalar (.column 0), .scalar (.column 1)]
-- A bare merged name is named as declared for one column, and as written for a coalesce.
#guard (query [bare (name! "A")] (table (name! "t")) [usingJoin ["RIGHT"] (name! "u") [(name! "a")]]).map (·.names) == some ["A"]
#guard (query [bare (name! "A")] (table (name! "t")) [usingJoin ["FULL"] (name! "u") [(name! "a")]]).map (·.names) == some ["A"]
#guard (query [bare (name! "A")] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")]]).map (·.names) == some ["a"]
-- With a right or full join, a later USING compares the coalesce of the left columns.
#guard (query [.star] (table (name! "t")) [usingJoin ["FULL"] (name! "r") [(name! "a")], usingJoin [] (name! "w") [(name! "a")]]).map
  (fun query => (query.sources.drop 1).map (·.condition)) ==
  some [some (.compare .eq (some .numeric) (.column 0) (.column 2)),
        some (.compare .eq (some .blob) (.coalesce (.column 0) (.column 2)) (.column 4))]
-- Without one, it compares the left-most column, as in slice 4b.
#guard (query [.star] (table (name! "t")) [usingJoin [] (name! "r") [(name! "a")], usingJoin [] (name! "v") [(name! "a")]]).map
  (fun query => (query.sources.drop 1).map (·.condition)) ==
  some [some (.compare .eq (some .numeric) (.column 0) (.column 2)), some (.compare .eq (some .numeric) (.column 0) (.column 4))]
-- A coalesce has no affinity, so against an INTEGER column the comparison has INTEGER affinity.
#guard (query [.star] (table (name! "t")) [usingJoin ["FULL"] (name! "r") [(name! "a")], usingJoin [] (name! "v") [(name! "a")]]).map
  (fun query => (query.sources.drop 1).map (·.condition)) ==
  some [some (.compare .eq (some .numeric) (.column 0) (.column 2)),
        some (.compare .eq (some .integer) (.coalesce (.column 0) (.column 2)) (.column 4))]
-- A left table that does not merge the name: also for a join before the right join, and for NATURAL.
#guard error [.star] (table (name! "t")) [joined [] (table (name! "r")) (some onText), usingJoin ["RIGHT"] (name! "w") [(name! "a")]] ==
  some (.expression (.ambiguousUsingReference (name! "a")))
#guard error [.star] (table (name! "t"))
  [joined [] (table (name! "r")) (some onText), usingJoin [] (name! "w") [(name! "a")], joined ["RIGHT"] (table (name! "u")) (some onA)] ==
  some (.expression (.ambiguousUsingReference (name! "a")))
#guard error [.star] (table (name! "t")) [joined [] (table (name! "r")) (some onText), joined ["NATURAL", "FULL"] (table (name! "w"))] ==
  some (.expression (.ambiguousUsingReference (name! "a")))
-- The errors of slice 4b still come first in their join.
#guard error [.star] (table (name! "t")) [usingJoin ["RIGHT"] (name! "r") [(name! "zz")]] == some (.expression (.joinUsingColumn (name! "zz")))


end Belay.Sqlite.Model.Resolution.MergedNameExamples
