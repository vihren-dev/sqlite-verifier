import Belay.Sqlite.Resolution.JoinExamples

set_option doc.verso true

/-! Examples of {lit}`USING` and {lit}`NATURAL` joins (ADR 0012, amendment 2, owner
decision 1; slice 4b), checked by {lit}`#guard`: the generated condition, the merged
columns in {lit}`*` and in names, SQLite's prepare errors and their order. -/

namespace Belay.Sqlite.Resolution.UsingExamples
open Belay.Sqlite Syntax Resolution.Examples Resolution.JoinExamples

/-- {lit}`t(a INTEGER, b TEXT)`, {lit}`u(A INTEGER, c TEXT)`,
{lit}`v(a INTEGER, b TEXT, d TEXT)`, {lit}`z(q INTEGER)` and {lit}`w(a TEXT)`, at
positions 0 to 4. -/
def sources : Catalog := catalogOf (schema [.createTable "t" [column "a" (some "INTEGER"), column "b"] [],
  .createTable "u" [column "A" (some "INTEGER"), column "c"] [],
  .createTable "v" [column "a" (some "INTEGER"), column "b", column "d"] [],
  .createTable "z" [column "q" (some "INTEGER")] [], .createTable "w" [column "a"] []])

/-- The single statement of a resolution of a {lit}`SELECT` over {name}`sources`. -/
def over (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option Resolved.Statement :=
  (statements (migration sources [.select results (some source) joins none [] [] none none])).head?

/-- The query of a resolution over {name}`sources`, if it is one. -/
def queryOver (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option Resolved.Query :=
  match over results source joins with
  | some (.query query) => some query
  | some (.createTable ..) | some (.createIndex ..) | some (.addColumn ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.prepareError _) | none => none

/-- A join with {lit}`USING` and the names. -/
def usingJoin (operator : List String) (name : String) (names : List String) : Join :=
  { joined operator (table name) with usingColumns := some names }

/-- An unqualified column as a result column. -/
def bare (name : String) : ResultColumn := .expression (.identifier name false) none name

-- USING and NATURAL resolve to the join with the written ON condition `t.a = u.A`.
#guard (queryOver [.star] (table "t") [usingJoin [] "u" ["a"]]).map (·.joins) ==
  (queryOver [.star] (table "t") [joined [] (table "u") (some (.equals (qualified "t" "a") (qualified "u" "A")))]).map (·.joins)
#guard (queryOver [.star] (table "t") [joined ["NATURAL"] (table "u")]).map (·.joins) ==
  (queryOver [.star] (table "t") [usingJoin [] "u" ["a"]]).map (·.joins)
#guard (queryOver [.star] (table "t") [usingJoin ["LEFT"] "u" ["a"]]).map (·.joins) ==
  some [{ kind := .left, table := 1, condition := some (.compare .eq (.column 0) (.column 2)) }]
-- `*` omits the merged right column; an unqualified `a` names the left one, `u.a` the right one.
#guard (queryOver [.star] (table "t") [usingJoin [] "u" ["a"]]).map (·.names) == some ["a", "b", "c"]
#guard (queryOver [.star] (table "u") [usingJoin [] "t" ["a"]]).map (·.names) == some ["A", "c", "b"]
#guard (queryOver [.sourceStar "u"] (table "t") [usingJoin [] "u" ["a"]]).map (·.names) == some ["A", "c"]
#guard (queryOver [bare "a", .expression (qualified "u" "a") none "u.a"] (table "t") [usingJoin ["LEFT"] "u" ["a"]]).map
  (·.columns) == some [.scalar (.column 0), .scalar (.column 2)]
-- NATURAL compares each common name with the left-most left column: `t.a` and `t.b`, not `u.A`.
#guard (queryOver [.star] (table "t") [joined [] (table "u") (some onA), joined ["NATURAL"] (table "v")]).map
  (fun query => (query.joins.map (·.condition), query.names)) ==
  some ([some (.compare .eq (.column 0) (.column 2)), some (.and (.compare .eq (.column 0) (.column 4)) (.compare .eq (.column 1) (.column 5)))],
        ["a", "b", "A", "c", "d"])
-- Without a common column NATURAL is a cross join; a repeated USING name is accepted.
#guard (queryOver [.star] (table "t") [joined ["NATURAL"] (table "z")]).map (·.joins) ==
  some [{ kind := .inner, table := 3, condition := none }]
#guard (queryOver [.star] (table "t") [usingJoin [] "u" ["a", "A"]]).map (·.names) == some ["a", "b", "c"]
-- The generated comparison has the rules of a written one: INTEGER `t.a` against TEXT `w.a`
-- would convert a value, which is the same model restriction for USING as for ON.
#guard reason (migration sources [.select [.star] (some (table "t")) [usingJoin [] "w" ["a"]] none [] [] none none]) ==
  RestrictionKind.mixedAffinityComparison.message
#guard reason (migration sources [.select [.star] (some (table "t"))
  [joined [] (table "w") (some (.equals (qualified "t" "a") (qualified "w" "a")))] none [] [] none none]) ==
  RestrictionKind.mixedAffinityComparison.message
-- A merged name stays ambiguous with a third source that has the name.
#guard over [bare "a"] (table "t") [usingJoin [] "u" ["a"]] |>.isSome
#guard over [bare "a"] (table "t") [usingJoin [] "u" ["a"], joined [] (table "v")] ==
  some (.prepareError (.ambiguousColumn "a"))
-- SQLite's errors: a USING name not in both inputs, also a rowid name, and NATURAL with ON or USING.
#guard over [.star] (table "t") [usingJoin [] "u" ["b"]] == some (.prepareError (.joinUsingColumn "b"))
#guard over [.star] (table "t") [usingJoin [] "u" ["rowid"]] == some (.prepareError (.joinUsingColumn "rowid"))
#guard over [.star] (table "t") [joined ["NATURAL"] (table "u") (some (.numeric "1"))] ==
  some (.prepareError .naturalJoinCondition)
#guard over [.star] (table "t") [usingJoin ["NATURAL"] "u" ["a"]] == some (.prepareError .naturalJoinCondition)
-- A missing table of a later join comes first; then the joins in order; then the result columns.
#guard over [.star] (table "t") [usingJoin [] "u" ["q"], joined [] (table "zz")] ==
  some (.prepareError (.noSuchTable "zz"))
#guard over [.star] (table "t") [usingJoin [] "u" ["q"], joined ["NATURAL"] (table "v") (some (.numeric "1"))] ==
  some (.prepareError (.joinUsingColumn "q"))
#guard over [bare "zz"] (table "t") [usingJoin [] "u" ["q"]] == some (.prepareError (.joinUsingColumn "q"))

end Belay.Sqlite.Resolution.UsingExamples
