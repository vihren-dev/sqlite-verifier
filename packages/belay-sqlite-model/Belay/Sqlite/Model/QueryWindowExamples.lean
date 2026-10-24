import Belay.Sqlite.Model.Execution
import Belay.Sqlite.Model.QueryExamples

set_option doc.verso true

/-! Examples of {lit}`LIMIT ?` and {lit}`OFFSET ?` (ADR 0019, slice 1), with the values of native
SQLite 3.51.0. {lit}`windowInteger` reads each kind of value as {lit}`OP_MustBeInt` does, and a
query statement over the table {lit}`t(k, v)` of {lit}`Resolved.QueryExamples` fails with
{lit}`datatype mismatch` when a value that SQLite reads is not an integer. The kernel checks each
example ({lit}`decide +kernel`). -/

namespace Belay.Sqlite.Model.QueryWindowExamples

open Resolved

/-- A text value from a string. -/
def text (string : String) : Value := .text string.toUTF8.toList

-- An integer, a whole REAL (2.0, whose bits are 0x4000000000000000) and text that numeric
-- affinity makes a whole number give the integer: '2', ' 2 ', '+2', '2.0' and '1e1'.
example : [windowInteger (.integer 2), windowInteger (.real 0x4000000000000000), windowInteger (text "2"),
    windowInteger (text " 2 "), windowInteger (text "+2"), windowInteger (text "2.0"), windowInteger (text "1e1")] =
    [some 2, some 2, some 2, some 2, some 2, some 2, some 10] := by decide +kernel
-- NULL, a blob, '', 'abc' and '0x10' have no integer.
example : [windowInteger .null, windowInteger (.blob [2]), windowInteger (text ""), windowInteger (text "abc"),
    windowInteger (text "0x10")] = [none, none, none, none, none] := by decide +kernel
-- 2.5 (bits 0x4004000000000000), '2.5', 1e20 (bits 0x4415AF1D78B58C40) and integer text
-- outside 64 bits have no integer.
example : [windowInteger (.real 0x4004000000000000), windowInteger (text "2.5"), windowInteger (.real 0x4415AF1D78B58C40),
    windowInteger (text "9223372036854775808")] = [none, none, none, none] := by decide +kernel

/-- {lit}`SELECT v FROM t ORDER BY k LIMIT ?1 OFFSET ?2`. -/
def windowed : Query :=
  { QueryExamples.plain with
    orderBy := [{ key := .expression (.column 0) }], limitParameter := some 1, offsetParameter := some 2 }

/-- {lit}`SELECT v FROM t WHERE 0 LIMIT 2 OFFSET ?1`. -/
def empty : Query :=
  { QueryExamples.plain with filter := some (.literal (.integer 0)), limit := some 2, offsetParameter := some 1 }

/-- The database with {lit}`t` of {lit}`Resolved.QueryExamples` at catalog position 0. -/
def database : Database := .ofTables [((name! "t"), QueryExamples.table)]

/-- The result rows of a query statement over {name}`database` with the values, or none. -/
def rowsOf (query : Query) (values : List Value) : Option (List (List Value)) :=
  (query.runOn 0 {} values database []).map (·.2.rows)

/-- The error of a query statement over {name}`database` with the values, or none when it succeeds;
the statement changes nothing in both cases. -/
def errorOf (query : Query) (values : List Value) : Option ExecutionError :=
  match step 0 {} values (.query query []) database with
  | .ok _ => none
  | .error (error, _) => some error

-- The rows of t in the order of k are 'c' (k is NULL), 'a', 'b' and 'd'. LIMIT 2 OFFSET 1 skips
-- 'c'; a negative LIMIT has no limit; a negative OFFSET skips no rows; '+2' and ' 1 ' are 2 and 1.
example : [rowsOf windowed [.integer 2, .integer 1], rowsOf windowed [.integer (-1), .integer 3],
    rowsOf windowed [.integer 1, .integer (-5)], rowsOf windowed [text "+2", text " 1 "]] =
    [some [[.text [97]], [.text [98]]], some [[.text [100]]], some [[.text [99]]], some [[.text [97]], [.text [98]]]] := by
  decide +kernel
-- A LIMIT of 0 skips the read of the OFFSET: NULL there gives no rows and no error.
example : errorOf windowed [.integer 0, .null] = none ∧ rowsOf windowed [.integer 0, .null] = some [] := by
  decide +kernel
-- With a LIMIT of -1 SQLite reads the OFFSET, and NULL fails the statement; a LIMIT that is not
-- an integer fails it too; a value that is not given is NULL.
example : [errorOf windowed [.integer (-1), .null], errorOf windowed [text "abc", .integer 0],
    errorOf windowed [.integer 1]] = [some .datatypeMismatch, some .datatypeMismatch, some .datatypeMismatch] := by
  decide +kernel
-- SQLite reads the window before the first row: WHERE 0 with OFFSET NULL fails, and with OFFSET 1
-- it gives no rows.
example : errorOf empty [.null] = some .datatypeMismatch ∧ errorOf empty [.integer 1] = none ∧
    rowsOf empty [.integer 1] = some [] := by
  decide +kernel

end Belay.Sqlite.Model.QueryWindowExamples
