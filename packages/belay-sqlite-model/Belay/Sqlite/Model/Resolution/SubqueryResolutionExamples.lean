import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the resolution of subqueries (ADR 0018, D1), checked by {lit}`#guard`: a
correlated name is a cell of the outer row, a name resolves in its own query first, the
affinity and collation of {lit}`IN` and of a scalar subquery come from the subquery's result
column, and the prepare errors and restrictions of subqueries. -/

namespace Belay.Sqlite.Model.Resolution.SubqueryResolutionExamples

open Belay.Sqlite.Model Syntax Resolution.Examples

/-- A catalog with {lit}`t(k INTEGER, v TEXT)` at position 0 and
{lit}`u(x, s TEXT COLLATE NOCASE, k)` at position 1. -/
def catalog : Catalog :=
  [{ name := (name! "t"), entry := .table { columns := [{ name := (name! "k"), declaredType := some "INTEGER" },
      { name := (name! "v"), declaredType := some "TEXT" }] } },
   { name := (name! "u"), entry := .table { columns := [{ name := (name! "x"), declaredType := none },
      { name := (name! "s"), declaredType := some "TEXT", collation := .nocase }, { name := (name! "k"), declaredType := none }] } }]

/-- A name as written, without quotes. -/
def name (text : String) : Expr := .identifier (Identifier.ofString text) .none

/-- A result column written as an expression without an alias. -/
def written (value : Expr) : ResultColumn := .expression value none "e"

/-- A table reference without alias. -/
def table (text : String) : TableReference := { table := Identifier.ofString text, alias := none }

/-- {lit}`SELECT columns FROM t [WHERE filter]` with the subqueries. -/
def fromT (columns : List ResultColumn) (filter : Option Expr) (subqueries : List Subquery) : Syntax.Statement :=
  .select columns (some (table "t")) [] filter [] [] none none subqueries

/-- {lit}`SELECT columns FROM u [WHERE filter]` as a subquery inside the query {lit}`parent`. -/
def fromU (columns : List ResultColumn) (filter : Option Expr) (parent : Option Nat := none) : Subquery :=
  { columns, source := some (table "u"), joins := [], filter, groupBy := [], orderBy := [], limit := none,
    offset := none, parent }

/-- The single statement of a resolution. -/
def resolvedOne (statement : Syntax.Statement) : Option Resolved.Statement :=
  (statements (migration catalog [statement])).head?

/-- The resolved query and subqueries of a resolution, if it is a query. -/
def queryOf (statement : Syntax.Statement) : Option (Resolved.Query × List Resolved.Query) :=
  match resolvedOne statement with
  | some (.query query subqueries) => some (query, subqueries)
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.prepareError _)
  | none => none

/-- Whether the statement is a model restriction. -/
def restrictedOne (statement : Syntax.Statement) : Bool := restricted (migration catalog [statement])

/-- The prepare error of a resolution, if it is one. -/
def errorOf (statement : Syntax.Statement) : Option PrepareError :=
  match resolvedOne statement with
  | some (.prepareError error) => some error
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | some (.query ..)
  | none => none

-- EXISTS (SELECT 1 FROM u WHERE u.x = t.v): t's cells are 0 and 1, u's start at 2; x without a type has BLOB affinity.
#guard (queryOf (fromT [written (name "k")] (some (.exists 0))
    [fromU [written (.numeric "1")] (some (.compare .eq (.qualified (Identifier.ofString "u") (Identifier.ofString "x"))
      (.qualified (Identifier.ofString "t") (Identifier.ofString "v"))))])).map
  (fun (query, subqueries) => (query.filter, subqueries.map (·.filter), subqueries.map (·.outer))) ==
  some (some (.exists 0), [some (.compare .eq (some .blob) (.column 2) (.column 1) .binary)], [2])
-- A name resolves in its own query first: k is u.k (cell 4), v is t.v (cell 1).
#guard (queryOf (fromT [written (name "k")] (some (.exists 0))
    [fromU [written (name "k")] (some (.compare .eq (name "x") (name "v")))])).map
  (fun (_, subqueries) => subqueries.map fun subquery => (subquery.columns, subquery.filter)) ==
  some [([.scalar (.column 4)], some (.compare .eq (some .blob) (.column 2) (.column 1) .binary))]
-- Depth two: the inner subquery reads t.v as cell 1, past u's cells.
#guard (queryOf (fromT [written (name "k")] (some (.exists 0))
    [fromU [written (.numeric "1")] (some (.exists 1)),
     fromU [written (.numeric "1")] (some (.compare .eq (name "x") (name "v"))) (some 0)])).map
  (fun (_, subqueries) => subqueries.map (·.filter)) ==
  some [some (.exists 1), some (.compare .eq (some .blob) (.column 5) (.column 1) .binary)]
-- k IN (SELECT s FROM u) compares under NUMERIC and k's BINARY; 'a' IN (...) under s's NOCASE.
#guard (queryOf (fromT [written (.inQuery (name "k") 0 false)] none [fromU [written (name "s")] none])).map
  (·.1.columns) == some [.scalar (.inQuery (.column 0) 0 (some .numeric) .binary false)]
#guard (queryOf (fromT [written (.inQuery (.string [97]) 0 true)] none [fromU [written (name "s")] none])).map
  (·.1.columns) == some [.scalar (.inQuery (.literal (.text [97])) 0 (some .text) .nocase true)]
-- A scalar subquery has the affinity of its result column: (SELECT s FROM u) = 1 compares as TEXT.
#guard (queryOf (fromT [written (.compare .eq (.subquery 0) (.numeric "1"))] none [fromU [written (name "s")] none])).map
  (·.1.columns) == some [.scalar (.compare .eq (some .text) (.subquery 0) (.literal (.integer 1)) .binary)]
-- A subquery with two result columns where one is needed is SQLite's prepare error.
#guard errorOf (fromT [written (.subquery 0)] none [fromU [.star] none]) == some (.expression (.subqueryColumns 3))
#guard errorOf (fromT [written (.inQuery (name "k") 0 false)] none [fromU [.star] none]) ==
  some (.expression (.subqueryColumns 3))
#guard (queryOf (fromT [written (name "k")] (some (.exists 0)) [fromU [.star] none])).isSome
-- * in a subquery without FROM names no table, also inside a query with one.
#guard errorOf (fromT [written (name "k")] (some (.exists 0))
  [{ fromU [.star] none with source := none }]) == some (.expression .noTablesSpecified)
-- An aggregate whose argument reads an outer column belongs to the outer query in SQLite.
#guard restrictedOne (fromT [written (.subquery 0)] none [fromU [written (.call "count" [name "v"])] none])
#guard (queryOf (fromT [written (.subquery 0)] none [fromU [written (.call "count" [name "x"])] none])).isSome
-- An alias of the outer query in a subquery's WHERE, and a subquery in ON, are restrictions.
#guard restrictedOne (.select [.expression (name "k") (some (Identifier.ofString "z")) "k"] (some (table "t")) []
  (some (.exists 0)) [] [] none none [fromU [written (.numeric "1")] (some (.compare .eq (name "x") (name "z")))])
/-- {lit}`JOIN u ON EXISTS (q)`, where {lit}`q` is subquery 0. -/
def joinOnExists : Join := { operator := [], source := table "u", condition := some (.exists 0), usingColumns := none }

#guard restrictedOne (.select [.star] (some (table "t")) [joinOnExists] none [] [] none none [fromU [written (.numeric "1")] none])
-- json_each without arguments is SQLite's eponymous table-valued function, not a missing table,
-- also in a subquery of an ON condition (corpus case json101-17.1).
#guard ["json_each", "JSONB_TREE", "pragma_table_info", "dbstat"].all fun eponymous =>
  restrictedOne (.select [.star] (some (table eponymous)) [] none [] [] none none)
#guard errorOf (.select [.star] (some (table "json_eachx")) [] none [] [] none none) ==
  some (.noSuchTable (Identifier.ofString "json_eachx"))
#guard restrictedOne (.select [.star] (some (table "t")) [joinOnExists] none [] [] none none
  [{ fromU [written (name "v")] none with source := some (table "json_each") }])
-- Writes: in UPDATE t SET v = (SELECT s FROM u WHERE x = k), k is u.k (cell 4), u's own column.
#guard match resolvedOne (.update (Identifier.ofString "t") [(Identifier.ofString "v", .subquery 0)] none []
    [fromU [written (name "s")] (some (.compare .eq (name "x") (name "k")))]) with
  | some (.update 0 [(1, .subquery 0)] none [] [subquery]) =>
    subquery.filter == some (.compare .eq (some .blob) (.column 2) (.column 4) .binary)
  | _ => false
-- DELETE FROM t WHERE k IN (SELECT x FROM u), and INSERT INTO t VALUES ((SELECT count(*) FROM u)).
#guard match resolvedOne (.delete (Identifier.ofString "t") (some (.inQuery (name "k") 0 false)) []
    [fromU [written (name "x")] none]) with
  | some (.delete 0 (some (.inQuery (.column 0) 0 (some .numeric) .binary false)) [] [_]) => true
  | _ => false
#guard match resolvedOne (.insert (Identifier.ofString "t") none [[.subquery 0, .null]] [] none []
    [fromU [written (.callStar "count")] none]) with
  | some (.insert 0 [[.expression (.subquery 0), .value .null]] [] [_]) => true
  | _ => false
-- A subquery of a write that reads the written table.
#guard restrictedOne (.update (Identifier.ofString "t") [(Identifier.ofString "v", .subquery 0)] none []
  [{ fromU [written (name "v")] none with source := some (table "t") }])
-- A subquery that names a query after it is malformed syntax, which the model refuses.
#guard restrictedOne (fromT [written (name "k")] (some (.exists 0)) [fromU [written (.numeric "1")] none (some 0)])
-- A query without FROM with a subquery and a call that can fail.
#guard restrictedOne (.select [written (.call "json" [.subquery 0])] none [] none [] [] none none
  [fromU [written (name "s")] none])

end Belay.Sqlite.Model.Resolution.SubqueryResolutionExamples
