import Belay.Sqlite.Model.JsonReady
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! Checked examples of where a JSON failure is part of the outcome (ADR 0012, amendment
5, slice 6b). Each fact was checked on native SQLite 3.51.0, one statement per line; the
conformance cases compare them with it. -/

namespace Belay.Sqlite.Model.Resolved.JsonFaultExamples

/-- The text of a string, as a literal. -/
def text (string : String) : Expr := .literal (.text string.toUTF8.toList)

/-- {lit}`json_extract('x', '$')`, which fails with {lit}`malformed JSON`. -/
def malformed : Expr := .json .extract (.cons (text "x") (.cons (text "$") .nil))

/-- {lit}`json_extract('{"a":1}', '$.a')`, which is 1. -/
def selected : Expr := .json .extract (.cons (text "{\"a\":1}") (.cons (text "$.a") .nil))

/-- {lit}`SELECT json_extract('x', '$')`: a query without {lit}`FROM`. -/
def fromless : Query where
  sources := []
  filter := none
  aggregate := false
  groupBy := []
  columns := [.scalar malformed]
  names := ["v"]
  orderBy := []
  offset := 0
  limit := none

/-- An empty table {lit}`t(a)` at catalog position 0. -/
def empty : Database :=
  .ofTables [((name! "t"), { shape := { columns := [{ name := (name! "a"), declaredType := none }] }, rows := [] })]

#guard selected.eval (.plain 0) [] == .integer 1 && malformed.eval (.plain 0) [] == .null
-- SQLite certainly reports the failure of a result column without FROM, and the step
-- fails with it.
#guard fromless.mustFail (.plain 0) [[]] && statementReady 0 {} [] (.query fromless []) empty
#guard match step 0 {} [] (.query fromless []) empty with
  | .error (reason, _) => reason == .functionError
  | .ok _ => false
-- Under LIMIT 0 SQLite evaluates nothing; OFFSET 1 skips the result column; WHERE 0
-- leaves no row. The model does not describe the first two, and the third succeeds.
#guard !{ fromless with limit := some 0 }.mustFail (.plain 0) [[]] && !statementReady 0 {} [] (.query { fromless with limit := some 0 } []) empty
#guard !{ fromless with offset := 1 }.mustFail (.plain 0) [[]] && !statementReady 0 {} [] (.query { fromless with offset := 1 } []) empty
#guard !{ fromless with filter := some (.literal (.integer 0)) }.mayFail (.plain 0) [[]]
-- An aggregate operand fails also under OFFSET.
#guard { fromless with aggregate := true, columns := [.aggregate (.count malformed)], offset := 1 }.mustFail (.plain 0) [[]]
-- SQLite may skip an operand of AND, so a failure under AND is not certain.
#guard !statementReady 0 {} [] (.query { fromless with columns := [.scalar (.and (.literal (.integer 0)) malformed)] } []) empty
-- A constant WHERE term is evaluated once before the rows, also over an empty table;
-- a result column is not.
#guard !statementReady 0 {} [] (.query { fromless with sources := [.first 0], filter := some malformed, columns := [] } []) empty
#guard statementReady 0 {} [] (.query { fromless with sources := [.first 0] } []) empty
-- An aggregate query evaluates its result row over NULL cells when no row passes WHERE.
#guard
  let columns : List Output := [.scalar malformed, .aggregate .countRows]
  !statementReady 0 {} [] (.query { fromless with sources := [.first 0], aggregate := true, columns := columns } []) empty
-- A JSON aggregate writes its operand as json_array does: JSONB that the model does not
-- describe (a header longer than needed) is a possible failure, and a failing operand stays
-- certain.
#guard
  let blob : Query := { fromless with aggregate := true, columns := [.aggregate (.jsonGroupArray (.literal (.blob [0xc7, 1, 0x61])))] }
  blob.mayFail (.plain 0) [[]] && !blob.mustFail (.plain 0) [[]] && (blob.run (.plain 0) [[]]).fault == .may
#guard
  let column : Output := .aggregate (.jsonGroupObject (text "a") (.literal (.blob [0xc7, 1, 0x61])))
  let blob : Query := { fromless with aggregate := true, columns := [column] }
  blob.mayFail (.plain 0) [[]] && !blob.mustFail (.plain 0) [[]]
#guard { fromless with aggregate := true, columns := [.aggregate (.jsonGroupArray malformed)] }.mustFail (.plain 0) [[]]
#guard { fromless with aggregate := true, columns := [.aggregate (.jsonGroupObject malformed (text "x"))] }.mustFail (.plain 0) [[]]
#guard !{ fromless with aggregate := true, columns := [.aggregate (.jsonGroupArray selected)] }.mayFail (.plain 0) [[]]
-- The model gives a write no JSON error: a DELETE whose WHERE may fail is not ready.
#guard (empty.table 0).all fun table => !deleteJsonReady (.plain 0) table (some malformed) [] && deleteJsonReady (.plain 0) table (some selected) []

end Belay.Sqlite.Model.Resolved.JsonFaultExamples
