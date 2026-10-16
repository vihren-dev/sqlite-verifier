import Belay.Sqlite.Resolution.Examples

set_option doc.verso true

/-! Examples of the resolution of a {lit}`SELECT` (ADR 0012, slice 1), checked by
{lit}`#guard`: names, result column names, the prepare errors of queries, the
affinity rules of a comparison, and the restrictions of the slice. -/

namespace Belay.Sqlite.Resolution.QueryResolutionExamples

open Belay.Sqlite Syntax Resolution.Examples

/-- A catalog with {lit}`t(Abc INTEGER, b TEXT)` at position 0. -/
def catalog : Catalog :=
  [{ name := "t", entry := .table { columns := [{ name := "Abc", declaredType := some "INTEGER" },
    { name := "b", declaredType := some "TEXT" }] } }]

/-- A {lit}`SELECT` from {lit}`t` with the given parts. -/
def select (columns : List ResultColumn) (filter : Option Expr := none) (groupBy : List Expr := [])
    (orderBy : List OrderTerm := []) (limit offset : Option Expr := none) : Syntax.Statement :=
  .select columns (some { table := "t", alias := none }) [] filter groupBy orderBy limit offset

/-- A result column written as an expression without an alias. -/
def written (value : Expr) (text : String) : ResultColumn := .expression value none text

/-- The single statement of a resolution, or a prepare error for a restriction. -/
def resolvedOne (statement : Syntax.Statement) : Option Resolved.Statement :=
  (statements (migration catalog [statement])).head?

/-- The query of a resolution, if it is one. -/
def queryOf (statement : Syntax.Statement) : Option Resolved.Query :=
  match resolvedOne statement with
  | some (.query query) => some query
  | some (.createTable ..) | some (.createIndex ..) | some (.addColumn ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.prepareError _) | none => none

/-- The prepare error of a resolution, if it is one. -/
def errorOf (statement : Syntax.Statement) : Option PrepareError :=
  match resolvedOne statement with
  | some (.prepareError error) => some error
  | some (.createTable ..) | some (.createIndex ..) | some (.addColumn ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.query _) | none => none

/-- Whether the statement is a model restriction. -/
def restrictedOne (statement : Syntax.Statement) : Bool := restricted (migration catalog [statement])

-- `*` and a bare column take the defined names; an expression keeps its text.
#guard (queryOf (select [.star])).map (·.names) == some ["Abc", "b"]
#guard (queryOf (select [written (.identifier "ABC" false) "ABC",
  written (.equals (.identifier "abc" false) (.numeric "1")) "abc = 1"])).map (·.names) == some ["Abc", "abc = 1"]
#guard (queryOf (select [.expression (.callStar "count") (some "n") "count(*)", written (.callStar "count") "count(*)"])).map
  (·.names) == some ["n", "count(*)"]
-- Names that SQLite refuses while it prepares the query.
#guard errorOf (select [written (.identifier "missing" false) "missing"]) == some (.noSuchColumn "missing")
#guard errorOf (.select [.star] (some { table := "absent", alias := none }) [] none [] [] none none) == some (.noSuchTable "absent")
#guard errorOf (select [.star] (filter := some (.equals (.callStar "count") (.numeric "1")))) ==
  some (.misuseOfAggregate "count")
#guard errorOf (select [written (.call "MAX" (.call "min" (.identifier "b" false))) "MAX(min(b))"]) ==
  some (.misuseOfAggregate "min")
#guard errorOf (select [.star] (orderBy := [{ expression := .numeric "3", descending := false }])) ==
  some (.orderByOutOfRange 1 2)
#guard errorOf (select [written (.callStar "COUNT") "COUNT(*)"] (groupBy := [.numeric "1"])) == some .aggregateInGroupBy
#guard restrictedOne (select [written (.call "group_concat" (.identifier "b" false)) "group_concat(b)"])
-- SQLite's own tables are not in the catalog; querying one is a model restriction.
#guard restrictedOne (.select [.star] (some { table := "sqlite_master", alias := none }) [] none [] [] none none)
-- A declared type that is a standard type name is kept in capitals, as SQLite reports it.
#guard reportedType (some "int") == some "INT" && reportedType (some "VarChar(10)") == some "VarChar(10)"
-- A double-quoted name that names no column is a string literal.
#guard (queryOf (select [written (.identifier "x" true) "\"x\""])).isSome
-- Comparisons whose affinity rule would convert a value are model restrictions.
#guard restrictedOne (select [.star] (filter := some (.equals (.identifier "b" false) (.numeric "5"))))
#guard restrictedOne (select [.star] (filter := some (.equals (.identifier "Abc" false) (.string [53]))))
#guard restrictedOne (select [.star] (filter := some (.equals (.identifier "Abc" false) (.identifier "b" false))))
#guard (queryOf (select [.star] (filter := some (.equals (.identifier "Abc" false) (.numeric "5"))))).isSome
-- The restrictions of slice 1.
#guard restrictedOne (select [written (.identifier "b" false) "b", written (.callStar "count") "count(*)"])
#guard restrictedOne (select [.star] (filter := some (.identifier "Abc" false)))
#guard restrictedOne (select [.star] (offset := some (.negate (.numeric "1"))))
-- SQLite resolves a result column alias in WHERE and in ORDER BY expressions; the
-- model restricts it, even when the alias is written in double quotes.
#guard restrictedOne (select [.expression (.identifier "Abc" false) (some "d") "Abc"]
  (filter := some (.equals (.identifier "d" true) (.numeric "0"))))
#guard restrictedOne (select [.expression (.identifier "Abc" false) (some "d") "Abc"]
  (orderBy := [{ expression := .isNull (.identifier "D" false) false, descending := false }]))
-- Numbers (slice 2): a REAL literal has SQLite's value; unary minus of a column is
-- `0 - column`; a CAST has the affinity of its type name; COALESCE needs two arguments.
#guard (queryOf (select [written (.numeric "1.5") "1.5"])).map (·.columns) == some [.scalar (.literal (.real 0x3FF8000000000000))]
#guard (queryOf (select [written (.negate (.identifier "Abc" false)) "-Abc"])).map (·.columns) ==
  some [.scalar (.arithmetic .subtract (.literal (.integer 0)) (.column 0))]
#guard (queryOf (select [written (.cast (.identifier "b" false) "int") "CAST(b AS int)"])).map (·.columns) ==
  some [.scalar (.cast .integer (.column 1))]
#guard errorOf (select [written (.call "Coalesce" (.identifier "b" false)) "Coalesce(b)"]) == some (.wrongArgumentCount "Coalesce")
#guard errorOf (select [written (.callPair "count" (.identifier "b" false) (.identifier "b" false)) "count(b, b)"]) ==
  some (.wrongArgumentCount "count")
#guard errorOf (select [written (.negate (.numeric "0x8000000000000000")) "-0x8000000000000000"]) ==
  some (.hexLiteralTooBig "-0x8000000000000000")
-- A COALESCE with a column may be TEXT, which a numeric column would convert: a restriction.
#guard restrictedOne (select [.star] (filter := some (.equals (.identifier "Abc" false)
  (.callPair "coalesce" (.identifier "b" false) (.numeric "0")))))
-- Arithmetic gives a number, so it can be a condition.
#guard (queryOf (select [.star] (filter := some (.arithmetic .add (.identifier "Abc" false) (.numeric "1"))))).isSome
-- Constant expressions in writes (slice 3a) are computed and stored at resolution; a SET
-- value that names a column stays an expression over the old row (slice 3b).
#guard resolvedOne (.insert "t" none [[.arithmetic .add (.numeric "1") (.numeric "2"), .string [120]]] []) ==
  some (.insert 0 [[.integer 3, .text [120]]] [] [])
#guard resolvedOne (.update "t" [("Abc", .cast (.string [55]) "INTEGER")] none) ==
  some (.update 0 [(0, .literal (.integer 7))] none [] [])
#guard errorOf (.insert "t" none [[.callStar "count", .null]] []) == some (.misuseOfAggregate "count")
#guard resolvedOne (.update "t" [("b", .arithmetic .add (.identifier "Abc" false) (.numeric "1"))] none) ==
  some (.update 0 [(1, .arithmetic .add (.column 0) (.literal (.integer 1)))] none [] [])
-- The filter is a condition, resolved as in SELECT: `WHERE Abc = 1 + 2`.
#guard resolvedOne (.update "t" [("b", .string [120])] (some (.equals (.identifier "Abc" false)
  (.arithmetic .add (.numeric "1") (.numeric "2"))))) == some (.update 0 [(1, .literal (.text [120]))]
  (some (.compare .eq (.column 0) (.arithmetic .add (.literal (.integer 1)) (.literal (.integer 2))))) [] [])
-- RETURNING (slice 3a): `*` and named expressions over the written row; an aggregate is
-- a misuse, a rowid a restriction, and an error in the values comes first.
#guard (resolvedOne (.returning (.insert "t" none [[.numeric "1", .string [120]]] []) [.star, .expression (.identifier "B" false) none "B"]))
  == some (.insert 0 [[.integer 1, .text [120]]] [] [(.column 0, "Abc"), (.column 1, "b"), (.column 1, "b")])
#guard errorOf (.returning (.insert "t" none [[.numeric "1", .string [120]]] []) [written (.callStar "count") "count(*)"]) ==
  some (.misuseOfAggregate "count")
#guard restrictedOne (.returning (.update "t" [("b", .string [120])] none) [written (.identifier "rowid" false) "rowid"])
#guard errorOf (.returning (.insert "t" none [[.identifier "missing" false, .null]] []) [written (.identifier "other" false) "other"]) ==
  some (.noSuchColumn "missing")
-- GROUP BY resolves a name to a source column before a result alias, so an alias
-- of an aggregate does not hide the column `b`.
#guard (queryOf (select [.expression (.callStar "count") (some "b") "count(*)"] (groupBy := [.identifier "b" false]))).map
  (·.groupBy) == some [.column 1]
-- A negative LIMIT means no limit; ORDER BY an alias names the result column.
#guard (queryOf (select [.star] (limit := some (.negate (.numeric "1"))))).map (·.limit) == some none
#guard (queryOf (select [.expression (.identifier "b" false) (some "k") "b"]
  (orderBy := [{ expression := .identifier "K" false, descending := true }]))).map (·.orderBy) ==
  some [(.output 0, true)]

-- A rowid name that is not a column is a restriction in every expression, since SQLite
-- reads the rowid: in a result column, in WHERE, in a SET value and in a DELETE filter.
#guard restrictedOne (select [written (.identifier "rowid" false) "rowid"])
#guard restrictedOne (select [.star] (filter := some (.equals (.identifier "oid" false) (.numeric "1"))))
#guard restrictedOne (.update "t" [("b", .identifier "_rowid_" false)] none)
#guard restrictedOne (.delete "t" (some (.equals (.identifier "rowid" true) (.numeric "1"))))
-- In VALUES no table is in scope, and SQLite reports `no such column: rowid`.
#guard errorOf (.insert "t" none [[.identifier "rowid" false, .null]] []) == some (.noSuchColumn "rowid")


/-- A {lit}`SELECT` without {lit}`FROM` with the given parts (ADR 0012, amendment 5, slice 6a). -/
def bare (columns : List ResultColumn) (filter : Option Expr := none) (groupBy : List Expr := []) : Syntax.Statement :=
  .select columns none [] filter groupBy [] none none

/-- The rows of a resolved query over its source of one row with no cells. -/
def bareRows (statement : Syntax.Statement) : Option (List (List Value)) :=
  (queryOf statement).map fun query => query.run [[]]

/-- The condition {lit}`1 = 0`, which is false. -/
def never : Expr := .equals (.numeric "1") (.numeric "0")

-- A SELECT without FROM has no table and one row, or none when WHERE is not true.
#guard (queryOf (bare [written (.numeric "1") "1"])).map (·.table) == some none
#guard bareRows (bare [written (.arithmetic .add (.numeric "1") (.numeric "2")) "1 + 2"]) == some [[.integer 3]]
#guard bareRows (bare [written (.numeric "1") "1"] (filter := some never)) == some []
-- Aggregates read the rows that pass WHERE, and GROUP BY gives one group.
#guard bareRows (bare [written (.callStar "count") "count(*)"]) == some [[.integer 1]]
#guard bareRows (bare [written (.callStar "count") "count(*)"] (filter := some never)) == some [[.integer 0]]
#guard bareRows (bare [written (.numeric "1") "1"] (groupBy := [.numeric "1"])) == some [[.integer 1]]
-- `*` is SQLite's `no tables specified`; a column, also qualified, is `no such column`.
#guard errorOf (bare [.star]) == some .noTablesSpecified
#guard errorOf (bare [written (.identifier "a" false) "a"]) == some (.noSuchColumn "a")
#guard errorOf (bare [written (.qualified "t" "a") "t.a"]) == some (.noSuchColumn "t.a")

end Belay.Sqlite.Resolution.QueryResolutionExamples
