import Belay.Sqlite.QueryEval

set_option doc.verso true

/-! Checked examples of query evaluation (ADR 0012, slice 1) over one small table.
Native SQLite is the authority for these rules; the conformance cases compare them
with it. These examples fix the intended reading of each step. -/

namespace Belay.Sqlite.Resolved.QueryExamples

/-- A table {lit}`t(k, v)` with rows in an order other than rowid order: rowid 3 has
NULL, rowids 1 and 2 have the key 1, rowid 4 has the key 2. -/
def table : Table where
  shape := { columns := [{ name := "k", declaredType := none }, { name := "v", declaredType := none }] }
  rows := [⟨3, [.null, .text [99]]⟩, ⟨1, [.integer 1, .text [97]]⟩, ⟨2, [.integer 1, .text [98]]⟩,
    ⟨4, [.integer 2, .text [100]]⟩]

/-- {lit}`SELECT v FROM t`: one row per table row, without a defined order. -/
def plain : Query where
  table := some 0
  filter := none
  aggregate := false
  groupBy := []
  columns := [.scalar (.column 1)]
  names := ["v"]
  orderBy := []
  offset := 0
  limit := none

#guard plain.run (sourceRows table) == [[.text [97]], [.text [98]], [.text [99]], [.text [100]]]
-- WHERE k = 1 keeps the rows whose comparison is true; NULL = 1 is NULL, not true.
#guard { plain with filter := some (.compare .eq (.column 0) (.literal (.integer 1))) }.run (sourceRows table) ==
  [[.text [97]], [.text [98]]]
-- ORDER BY k DESC puts NULL last; the tie between rowids 1 and 2 keeps rowid order.
#guard { plain with orderBy := [(.expression (.column 0), true)] }.run (sourceRows table) ==
  [[.text [100]], [.text [97]], [.text [98]], [.text [99]]]
-- ORDER BY k with LIMIT 2 OFFSET 1: NULL first, then the window.
#guard { plain with orderBy := [(.expression (.column 0), false)], offset := 1, limit := some 2 }.run (sourceRows table) ==
  [[.text [97]], [.text [98]]]
/-- {lit}`SELECT k, COUNT(*), MIN(v), COUNT(k) FROM t GROUP BY k ORDER BY 1`. -/
def grouped : Query where
  table := some 0
  filter := none
  aggregate := true
  groupBy := [.column 0]
  columns := [.scalar (.column 0), .aggregate .countRows, .aggregate (.min (.column 1)), .aggregate (.count (.column 0))]
  names := ["k", "count(*)", "min(v)", "count(k)"]
  orderBy := [(.output 0, false)]
  offset := 0
  limit := none

#guard grouped.run (sourceRows table) ==
  [[.null, .integer 1, .text [99], .integer 0], [.integer 1, .integer 2, .text [97], .integer 2],
   [.integer 2, .integer 1, .text [100], .integer 1]]
-- An aggregate query without GROUP BY gives one row, also for an empty table.
#guard { plain with aggregate := true, columns := [.aggregate .countRows, .aggregate (.max (.column 0))] }.run
  [] == [[.integer 0, .null]]

/-- The three logical values as expressions: true, false and NULL. -/
def yes : Expr := .literal (.integer 1)
/-- The false value. -/
def no : Expr := .literal (.integer 0)
/-- The NULL value. -/
def unknown : Expr := .literal .null

-- AND: false wins over NULL, NULL wins over true.
#guard [(yes, yes), (yes, no), (no, unknown), (unknown, yes), (unknown, unknown)].map
  (fun (a, b) => (Expr.and a b).eval []) == [.integer 1, .integer 0, .integer 0, .null, .null]
-- OR: true wins over NULL, NULL wins over false.
#guard [(no, no), (yes, no), (yes, unknown), (unknown, no), (unknown, unknown)].map
  (fun (a, b) => (Expr.or a b).eval []) == [.integer 0, .integer 1, .integer 1, .null, .null]
-- NOT keeps NULL.
#guard [yes, no, unknown].map (fun a => (Expr.not a).eval []) == [.integer 0, .integer 1, .null]
-- IS NULL and IS NOT NULL never give NULL.
#guard [unknown, no].map (fun a => (Expr.isNull a false).eval []) == [.integer 1, .integer 0]
#guard [unknown, no].map (fun a => (Expr.isNull a true).eval []) == [.integer 0, .integer 1]

-- Values: storage classes, exact integer-real comparison, bytes, and NULL in comparisons.
#guard compareValues (.integer 1) (.real 0x3FF0000000000000) == .eq
#guard compareValues (.integer 9007199254740993) (.real 0x4340000000000001) == .lt
#guard compareValues .null (.integer (-5)) == .lt
#guard compareValues (.real 0xFFF0000000000000) (.integer (-(2 ^ 63))) == .lt
#guard compareValues (.integer 7) (.text []) == .lt
#guard compareValues (.text [255]) (.blob []) == .lt
#guard compareValues (.text [97]) (.text [97, 0]) == .lt
#guard compareValues (.real 0x8000000000000000) (.real 0) == .eq
#guard Comparison.eq.apply .null .null == .null
#guard Comparison.is.apply .null .null == .integer 1
#guard Comparison.isNot.apply .null (.integer 0) == .integer 1

-- A SUM that overflows fails the query, except under LIMIT 0, which SQLite does not
-- evaluate.
#guard
  let large : Table := { table with rows := [⟨1, [.integer int64Maximum, .null]⟩, ⟨2, [.integer 1, .null]⟩] }
  let total : Query := { plain with aggregate := true, columns := [.aggregate (.sum (.column 0))] }
  total.fails (sourceRows large) && !({ total with limit := some 0 }).fails (sourceRows large) &&
    !total.fails (sourceRows table)

end Belay.Sqlite.Resolved.QueryExamples
