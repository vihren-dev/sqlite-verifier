import Belay.Sqlite.Model.Resolution.Examples
import Belay.Sqlite.Model.Execution

set_option doc.verso true

/-! Examples of aggregates inside expressions, {lit}`HAVING` and {lit}`SELECT DISTINCT`
(ADR 0018, D3), checked by {lit}`#guard`: each query is resolved over a small database and run.
The rows are those of native SQLite 3.51.0 over {lit}`t(g, v INTEGER, s TEXT COLLATE NOCASE)`
with the rows {lit}`(1, 10, 'a')`, {lit}`(1, 20, 'A')`, {lit}`(2, 5, 'b')` and
{lit}`(3, NULL, 'c')`. -/

namespace Belay.Sqlite.Model.Resolution.GroupExamples

open Belay.Sqlite.Model Syntax Resolution.Examples

/-- The table {lit}`t` of the examples. -/
def table : Table where
  shape := { columns := [{ name := (name! "g"), declaredType := none }, { name := (name! "v"), declaredType := some "INTEGER" },
    { name := (name! "s"), declaredType := some "TEXT", collation := .nocase }] }
  rows := [⟨1, [.integer 1, .integer 10, .text [97]]⟩, ⟨2, [.integer 1, .integer 20, .text [65]]⟩,
    ⟨3, [.integer 2, .integer 5, .text [98]]⟩, ⟨4, [.integer 3, .null, .text [99]]⟩]

/-- The database with {lit}`t` at catalog position 0. -/
def database : Database := .ofTables [((name! "t"), table)]

/-- A name as written, without quotes. -/
def col (text : String) : Expr := .identifier (Identifier.ofString text) .none

/-- A result column written as an expression without an alias. -/
def written (value : Expr) : ResultColumn := .expression value none "e"

/-- {lit}`SELECT columns FROM t [GROUP BY] [HAVING] [ORDER BY]` with {lit}`DISTINCT`. -/
def query (columns : List ResultColumn) (groupBy : List Expr := []) (having : Option Expr := none)
    (orderBy : List OrderTerm := []) (distinct : Bool := false) : Syntax.Statement :=
  .select columns (some { table := Identifier.ofString "t", alias := none }) [] none groupBy orderBy none none [] having
    distinct

/-- What a statement of the examples gives: its result rows, a prepare error, or a model
restriction (or another statement). -/
inductive Answer where
  /-- The result rows of a query. -/
  | rows (rows : List (List Value))
  /-- SQLite's prepare error. -/
  | error (error : PrepareError)
  /-- A model restriction, or a statement that is no query. -/
  | restricted
  deriving DecidableEq

/-- The answer of a statement over the database ({name}`Answer`). -/
def rowsOf (statement : Syntax.Statement) : Answer :=
  match (statements (migration database.catalog [statement])).head? with
  | some (.query resolved subqueries) => match resolved.runOn 0 {} [] database subqueries with
    | some (_, run) => .rows run.rows
    | none => .restricted
  | some (.prepareError error) => .error error
  | some (.createTable ..) | some (.createIndex ..) | some (.createTrigger ..) | some (.addColumn ..) | some (.drop ..) | some (.setting ..) | some .begin | some .commit
  | some .rollback | some (.insert ..) | some (.upsert ..) | some (.update ..) | some (.delete ..) | none => .restricted

/-- {lit}`count(*)`, written as a call. -/
def count : Expr := .callStar "count"

/-- An ascending {lit}`ORDER BY` term. -/
def by_ (expression : Expr) : OrderTerm := { expression, descending := false }

-- SELECT g, count(*) + 1, max(v) - min(v) FROM t GROUP BY g ORDER BY g.
#guard rowsOf (query [written (col "g"), written (.arithmetic .add count (.numeric "1")),
    written (.arithmetic .subtract (.call "max" [col "v"]) (.call "min" [col "v"]))] [col "g"] none [by_ (col "g")]) ==
  (.rows [[.integer 1, .integer 3, .integer 10], [.integer 2, .integer 2, .integer 0], [.integer 3, .integer 2, .null]])
-- HAVING count(*) > 1 OR g = 3 keeps the groups 1 and 3.
#guard rowsOf (query [written (col "g")] [col "g"]
    (some (.or (.compare .gt count (.numeric "1")) (.compare .eq (col "g") (.numeric "3")))) [by_ (col "g")]) ==
  (.rows [[.integer 1], [.integer 3]])
-- HAVING without GROUP BY, over the one group of all rows; and on a non-aggregate query.
#guard rowsOf (query [written count] [] (some (.compare .gt count (.numeric "1")))) == (.rows [[.integer 4]])
#guard rowsOf (query [written (col "v")] [] (some (.compare .gt (col "v") (.numeric "1")))) ==
  (.error (.expression .havingNonAggregate))
-- ORDER BY sum(v) DESC, g: the sums 30, 5 and NULL.
#guard rowsOf (query [written (col "g")] [col "g"] none [{ expression := .call "sum" [col "v"], descending := true },
    by_ (col "g")]) == (.rows [[.integer 1], [.integer 2], [.integer 3]])
-- count() without an argument is an aggregate too (corpus case select1-2.3): SELECT count() FROM t is 4.
#guard rowsOf (query [written (.call "Count" [])]) == .rows [[.integer 4]]
-- An aggregate in an expression over an empty group: SELECT count(*) + 1 FROM t WHERE 0 is 1.
#guard match (statements (migration database.catalog [.select [written (.arithmetic .add count (.numeric "1"))]
    (some { table := Identifier.ofString "t", alias := none }) [] (some (.numeric "0")) [] [] none none])).head? with
  | some (.query resolved _) => (resolved.runOn 0 {} [] database []).map (·.2.rows) == some [[.integer 1]]
  | _ => false
-- SELECT DISTINCT g gives each group once; DISTINCT s is not described, as 'a' and 'A' are one row.
#guard rowsOf (query [written (col "g")] [] none [by_ (col "g")] true) ==
  (.rows [[.integer 1], [.integer 2], [.integer 3]])
#guard match (statements (migration database.catalog [query [written (col "s")] [] none [] true])).head? with
  | some (.query resolved _) => (resolved.runOn 0 {} [] database []).map (·.2.fault) == some .may
  | _ => false
-- HAVING or an ORDER BY aggregate does not make a query an aggregate query: SQLite's prepare errors.
#guard rowsOf (query [written (.numeric "1")] [] (some (.compare .gt count (.numeric "0")))) ==
  .error (.expression .havingNonAggregate)
#guard rowsOf (query [written (col "g")] [] none [by_ count]) == .error (.expression (.misuseOfAggregate "count"))
-- SQLite resolves the result columns first: SELECT missing FROM t HAVING 1 is no such column.
#guard rowsOf (query [written (col "missing")] [] (some (.numeric "1"))) ==
  .error (.expression (.noSuchColumn (Identifier.ofString "missing")))
-- GROUP BY 1 over a result column with an aggregate.
#guard rowsOf (query [written (.arithmetic .add count (.numeric "1"))] [.numeric "1"]) ==
  .error (.expression .aggregateInGroupBy)
-- A bare column in HAVING is a restriction; a nested aggregate is SQLite's misuse.
#guard rowsOf (query [written (col "g")] [col "g"] (some (.compare .gt (col "v") (.numeric "6")))) == .restricted
#guard rowsOf (query [written (.call "sum" [count])]) == (.error (.expression (.misuseOfAggregate "count")))

end Belay.Sqlite.Model.Resolution.GroupExamples
