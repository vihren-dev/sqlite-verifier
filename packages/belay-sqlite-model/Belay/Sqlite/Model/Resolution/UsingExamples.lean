import Belay.Sqlite.Model.Resolution.JoinExamples

set_option doc.verso true

/-! Examples of {lit}`USING` and {lit}`NATURAL` joins (ADR 0012, amendment 2, owner
decision 1; slice 4b), checked by {lit}`#guard`: the generated condition, the merged
columns in {lit}`*` and in names, SQLite's prepare errors and their order. -/

namespace Belay.Sqlite.Model.Resolution.UsingExamples
open Belay.Sqlite.Model Syntax Resolution.Examples Resolution.JoinExamples

/-- {lit}`t(a INTEGER, b TEXT)`, {lit}`u(A INTEGER, c TEXT)`,
{lit}`v(a INTEGER, b TEXT, d TEXT)`, {lit}`z(q INTEGER)` and {lit}`w(a TEXT)`, at
positions 0 to 4. -/
def sources : Catalog := catalogOf (schema [.createTable (name! "t") [column (name! "a") (some "INTEGER"), column (name! "b")] [],
  .createTable (name! "u") [column (name! "A") (some "INTEGER"), column (name! "c")] [],
  .createTable (name! "v") [column (name! "a") (some "INTEGER"), column (name! "b"), column (name! "d")] [],
  .createTable (name! "z") [column (name! "q") (some "INTEGER")] [], .createTable (name! "w") [column (name! "a")] []])

/-- The single statement of a resolution of a {lit}`SELECT` over {name}`sources`. -/
def over (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option Resolved.Statement :=
  (statements (migration sources [.select results (some source) joins none [] [] none none])).head?

/-- The query of a resolution over {name}`sources`, if it is one. -/
def queryOver (results : List ResultColumn) (source : TableReference) (joins : List Join) : Option Resolved.Query :=
  match over results source joins with
  | some (.query query _) => some query
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.prepareError _) | none => none

/-- A join with {lit}`USING` and the names. -/
def usingJoin (operator : List String) (name : Identifier) (names : List Identifier) : Join :=
  { joined operator (table name) with usingColumns := some names }

/-- An unqualified column as a result column. -/
def bare (name : Identifier) : ResultColumn := .expression (.identifier name .none) none name.text

-- USING and NATURAL resolve to the join with the written ON condition `t.a = u.A`.
#guard (queryOver [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")]]).map (·.sources.drop 1) ==
  (queryOver [.star] (table (name! "t")) [joined [] (table (name! "u")) (some (.compare .eq (qualified (name! "t") (name! "a")) (qualified (name! "u") (name! "A"))))]).map (·.sources.drop 1)
#guard (queryOver [.star] (table (name! "t")) [joined ["NATURAL"] (table (name! "u"))]).map (·.sources.drop 1) ==
  (queryOver [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")]]).map (·.sources.drop 1)
#guard (queryOver [.star] (table (name! "t")) [usingJoin ["LEFT"] (name! "u") [(name! "a")]]).map (·.sources.drop 1) ==
  some [{ kind := .left, source := .table 1, condition := some (.compare .eq (some .numeric) (.column 0) (.column 2)) }]
-- `*` omits the merged right column; an unqualified `a` names the left one, `u.a` the right one.
#guard (queryOver [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")]]).map (·.names) == some ["a", "b", "c"]
#guard (queryOver [.star] (table (name! "u")) [usingJoin [] (name! "t") [(name! "a")]]).map (·.names) == some ["A", "c", "b"]
#guard (queryOver [.sourceStar (name! "u")] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")]]).map (·.names) == some ["A", "c"]
#guard (queryOver [bare (name! "a"), .expression (qualified (name! "u") (name! "a")) none "u.a"] (table (name! "t")) [usingJoin ["LEFT"] (name! "u") [(name! "a")]]).map
  (·.columns) == some [.scalar (.column 0), .scalar (.column 2)]
-- NATURAL compares each common name with the left-most left column: `t.a` and `t.b`, not `u.A`.
#guard (queryOver [.star] (table (name! "t")) [joined [] (table (name! "u")) (some onA), joined ["NATURAL"] (table (name! "v"))]).map
  (fun query => ((query.sources.drop 1).map (·.condition), query.names)) ==
  some ([some (.compare .eq (some .numeric) (.column 0) (.column 2)),
    some (.and (.compare .eq (some .numeric) (.column 0) (.column 4)) (.compare .eq (some .blob) (.column 1) (.column 5)))],
        ["a", "b", "A", "c", "d"])
-- Without a common column NATURAL is a cross join; a repeated USING name is accepted.
#guard (queryOver [.star] (table (name! "t")) [joined ["NATURAL"] (table (name! "z"))]).map (·.sources.drop 1) ==
  some [{ kind := .inner, source := .table 3, condition := none }]
#guard (queryOver [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a"), (name! "A")]]).map (·.names) == some ["a", "b", "c"]
-- The generated comparison has the rules of a written one: INTEGER `t.a` against the
-- untyped (BLOB) `w.a` compares with NUMERIC affinity, for USING as for ON.
#guard (queryOver [.star] (table (name! "t")) [usingJoin [] (name! "w") [(name! "a")]]).map (·.sources.drop 1) ==
  some [{ kind := .inner, source := .table 4, condition := some (.compare .eq (some .numeric) (.column 0) (.column 2)) }]
#guard (queryOver [.star] (table (name! "t")) [usingJoin [] (name! "w") [(name! "a")]]).map (·.sources.drop 1) ==
  (queryOver [.star] (table (name! "t")) [joined [] (table (name! "w")) (some (.compare .eq (qualified (name! "t") (name! "a")) (qualified (name! "w") (name! "a"))))]).map
    (·.sources.drop 1)
-- A merged name stays ambiguous with a third source that has the name.
#guard over [bare (name! "a")] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")]] |>.isSome
#guard over [bare (name! "a")] (table (name! "t")) [usingJoin [] (name! "u") [(name! "a")], joined [] (table (name! "v"))] ==
  some (.prepareError (.expression (.ambiguousColumn (name! "a"))))
-- SQLite's errors: a USING name not in both inputs, also a rowid name, and NATURAL with ON or USING.
#guard over [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "b")]] == some (.prepareError (.expression (.joinUsingColumn (name! "b"))))
#guard over [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "rowid")]] == some (.prepareError (.expression (.joinUsingColumn (name! "rowid"))))
#guard over [.star] (table (name! "t")) [joined ["NATURAL"] (table (name! "u")) (some (.numeric "1"))] ==
  some (.prepareError (.expression .naturalJoinCondition))
#guard over [.star] (table (name! "t")) [usingJoin ["NATURAL"] (name! "u") [(name! "a")]] == some (.prepareError (.expression .naturalJoinCondition))
-- A missing table of a later join comes first; then the joins in order; then the result columns.
#guard over [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "q")], joined [] (table (name! "zz"))] ==
  some (.prepareError (.noSuchTable (name! "zz")))
#guard over [.star] (table (name! "t")) [usingJoin [] (name! "u") [(name! "q")], joined ["NATURAL"] (table (name! "v")) (some (.numeric "1"))] ==
  some (.prepareError (.expression (.joinUsingColumn (name! "q"))))
#guard over [bare (name! "zz")] (table (name! "t")) [usingJoin [] (name! "u") [(name! "q")]] == some (.prepareError (.expression (.joinUsingColumn (name! "q"))))

end Belay.Sqlite.Model.Resolution.UsingExamples
