import Belay.Sqlite.JsonReady
import Belay.Sqlite.Execution

set_option doc.verso true

/-! Checked examples of where a JSON failure is part of the outcome (ADR 0012, amendment
5, slice 6b). Each fact was checked on native SQLite 3.51.0, one statement per line; the
conformance cases compare them with it. -/

namespace Belay.Sqlite.Resolved.JsonFaultExamples

/-- The text of a string, as a literal. -/
def text (string : String) : Expr := .literal (.text string.toUTF8.toList)

/-- {lit}`json_extract('x', '$')`, which fails with {lit}`malformed JSON`. -/
def malformed : Expr := .json .extract (.cons (text "x") (.cons (text "$") .nil))

/-- {lit}`json_extract('{"a":1}', '$.a')`, which is 1. -/
def selected : Expr := .json .extract (.cons (text "{\"a\":1}") (.cons (text "$.a") .nil))

/-- {lit}`SELECT json_extract('x', '$')`: a query without {lit}`FROM`. -/
def fromless : Query where
  table := none
  filter := none
  aggregate := false
  groupBy := []
  columns := [.scalar malformed]
  names := ["v"]
  orderBy := []
  offset := 0
  limit := none

/-- An empty table {lit}`t(a)` at catalog position 0. -/
def empty : Database := fun position =>
  if position = 0 then some { shape := { columns := [{ name := "a", declaredType := none }] }, rows := [] } else none

#guard selected.eval [] == .integer 1 && malformed.eval [] == .null
-- SQLite certainly reports the failure of a result column without FROM, and the step
-- fails with it.
#guard fromless.mustFail [[]] && queryJsonReady fromless empty
#guard match step (.query fromless) empty with
  | .failure position reason _ => position == 0 && reason == .functionError
  | .success _ | .pending .. => false
-- Under LIMIT 0 SQLite evaluates nothing; OFFSET 1 skips the result column; WHERE 0
-- leaves no row. The model does not describe the first two, and the third succeeds.
#guard !{ fromless with limit := some 0 }.mustFail [[]] && !queryJsonReady { fromless with limit := some 0 } empty
#guard !{ fromless with offset := 1 }.mustFail [[]] && !queryJsonReady { fromless with offset := 1 } empty
#guard !{ fromless with filter := some (.literal (.integer 0)) }.mayFail [[]]
-- An aggregate operand fails also under OFFSET.
#guard { fromless with aggregate := true, columns := [.aggregate (.count malformed)], offset := 1 }.mustFail [[]]
-- SQLite may skip an operand of AND, so a failure under AND is not certain.
#guard !queryJsonReady { fromless with columns := [.scalar (.and (.literal (.integer 0)) malformed)] } empty
-- A constant WHERE term is evaluated once before the rows, also over an empty table;
-- a result column is not.
#guard !queryJsonReady { fromless with table := some 0, filter := some malformed, columns := [] } empty
#guard queryJsonReady { fromless with table := some 0 } empty
-- An aggregate query evaluates its result row over NULL cells when no row passes WHERE.
#guard
  let columns : List Output := [.scalar malformed, .aggregate .countRows]
  !queryJsonReady { fromless with table := some 0, aggregate := true, columns := columns } empty
-- The model gives a write no JSON error: a DELETE whose WHERE may fail is not ready.
#guard (empty 0).all fun table => !deleteJsonReady table (some malformed) [] && deleteJsonReady table (some selected) []

end Belay.Sqlite.Resolved.JsonFaultExamples
