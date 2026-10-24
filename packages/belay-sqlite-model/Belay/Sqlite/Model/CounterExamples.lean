import Belay.Sqlite.Model.ScriptRunExamples

set_option doc.verso true

/-! Examples of the counters of a connection after plain writes (ADR 0024, D2), each checked by
the kernel. The expected values are the values that native SQLite 3.51.0 gives for the same
statements (ADR 0024, "Examples"): an INSERT of two rows changes two and sets the last rowid; a
failed INSERT changes none and keeps the rowid of the last row stored before the failure; an
UPDATE or DELETE leaves the last rowid; a query, {lit}`BEGIN` and {lit}`ROLLBACK` leave all
three counters; a total that is unknown stays unknown. -/

namespace Belay.Sqlite.Model.CounterExamples

open Belay.Sqlite.Model Syntax Resolution.Examples ScriptRunExamples

/-- The counters after the statements, from the empty database on a connection with the supplied
counters: a new connection ({name}`Counters.newConnection`) by default. -/
def countersAfter (script : List Syntax.Statement) (start : Counters := Counters.newConnection) : Counters :=
  (runScriptFrom { profile := defaults, mode := .execution } none 0 { state := { database := {}, counters := start } }
    (bindValues script [])).connection.state.counters

/-- {lit}`INSERT INTO t VALUES (5, 'a'), (9, 'b')`. -/
def insertTwo : Syntax.Statement :=
  .insert (name! "t") none [[.numeric "5", .string "a".toUTF8.toList], [.numeric "9", .string "b".toUTF8.toList]] [] none

/-- {lit}`INSERT INTO t VALUES (3, 'x'), (5, 'y')`: the second row has a rowid that the table
holds after {name}`insertTwo`. -/
def insertFailing : Syntax.Statement :=
  .insert (name! "t") none [[.numeric "3", .string "x".toUTF8.toList], [.numeric "5", .string "y".toUTF8.toList]] [] none

/-- {lit}`UPDATE t SET name = 'z'`. -/
def updateAll : Syntax.Statement := .update (name! "t") [(name! "name", .string "z".toUTF8.toList)] none []

/-- {lit}`DELETE FROM t WHERE id = 5`. -/
def deleteFive : Syntax.Statement := .delete (name! "t") (some (.compare .eq (.identifier (name! "id") .none) (.numeric "5"))) []

/-- A statement that changes no counter leaves a new connection as it was. -/
example : countersAfter [createT, selectNames, .begin, .commit] = Counters.newConnection := by decide +kernel

/-- An INSERT of two rows changes two, adds two to the total, and sets the last rowid to 9. -/
example : countersAfter [createT, insertTwo] = { changes := some 2, totalChanges := some 2, lastInsertRowid := some 9 } := by
  decide +kernel

/-- A failed INSERT changes none, adds none to the total, and keeps the rowid 3 of the row that it
stored before the failing row. -/
example : countersAfter [createT, insertT "1" "a", insertT "5" "b", insertFailing] =
    { changes := some 0, totalChanges := some 2, lastInsertRowid := some 3 } := by
  decide +kernel

/-- An UPDATE of two rows changes two and adds two to the total, and keeps the last rowid. -/
example : countersAfter [createT, insertTwo, updateAll] =
    { changes := some 2, totalChanges := some 4, lastInsertRowid := some 9 } := by
  decide +kernel

/-- A DELETE of one row changes one and adds one to the total, and keeps the last rowid. -/
example : countersAfter [createT, insertTwo, deleteFive] =
    { changes := some 1, totalChanges := some 3, lastInsertRowid := some 9 } := by
  decide +kernel

/-- A ROLLBACK keeps the counters of the INSERT that it rolls back. -/
example : countersAfter [createT, .begin, insertTwo, .rollback] =
    { changes := some 2, totalChanges := some 2, lastInsertRowid := some 9 } := by
  decide +kernel

/-- {lit}`INSERT INTO t VALUES (5, 'q') ON CONFLICT(id) DO UPDATE SET name = 'q'`: the row
conflicts with the row 5 that {name}`insertTwo` stored. -/
def upsertUpdate : Syntax.Statement :=
  .insert (name! "t") none [[.numeric "5", .string "q".toUTF8.toList]]
    [{ target := some [name! "id"], action := .update [(name! "name", .string "q".toUTF8.toList)] none }] none

/-- {lit}`INSERT INTO t VALUES (5, 'q'), (11, 'n') ON CONFLICT DO NOTHING`: the first row
conflicts with the row 5 that {name}`insertTwo` stored. -/
def upsertSkipping : Syntax.Statement :=
  .insert (name! "t") none [[.numeric "5", .string "q".toUTF8.toList], [.numeric "11", .string "n".toUTF8.toList]]
    [{ target := none, action := .nothing }] none

/-- An upsert that takes the {lit}`DO UPDATE` branch changes one row and adds one to the total, and
leaves the last rowid: the updated row is no inserted row. -/
example : countersAfter [createT, insertTwo, upsertUpdate] =
    { changes := some 1, totalChanges := some 3, lastInsertRowid := some 9 } := by
  decide +kernel

/-- An upsert that skips one row and inserts the other changes one row, adds one to the total, and
sets the last rowid to the rowid 11 of the inserted row. -/
example : countersAfter [createT, insertTwo, upsertSkipping] =
    { changes := some 1, totalChanges := some 3, lastInsertRowid := some 11 } := by
  decide +kernel

/-- An {lit}`INSERT OR IGNORE` that skips its only row changes none, adds none to the total, and
leaves the last rowid. -/
example : countersAfter [createT, insertTwo, insertT "5" "q" (some .ignore)] =
    { changes := some 0, totalChanges := some 2, lastInsertRowid := some 9 } := by
  decide +kernel

/-- An {lit}`INSERT OR FAIL` that stops at its second row keeps the first: it changes one row, adds
one to the total, and sets the last rowid to the rowid 11 of the kept row. -/
example : countersAfter [createT, insertTwo,
      .insert (name! "t") none [[.numeric "11", .string "n".toUTF8.toList], [.numeric "5", .string "q".toUTF8.toList]] [] (some .fail)] =
    { changes := some 1, totalChanges := some 3, lastInsertRowid := some 11 } := by
  decide +kernel

/-- An {lit}`INSERT OR ABORT` that stops at its second row takes the first back: it changes none and
adds none to the total, but the last rowid keeps the rowid 11 that the statement stored. -/
example : countersAfter [createT, insertTwo,
      .insert (name! "t") none [[.numeric "11", .string "n".toUTF8.toList], [.numeric "5", .string "q".toUTF8.toList]] [] (some .abort)] =
    { changes := some 0, totalChanges := some 2, lastInsertRowid := some 11 } := by
  decide +kernel

/-- A connection with unknown counters learns {lit}`changes()` and the last rowid from an INSERT, and
keeps its total unknown. -/
example : countersAfter [createT, insertTwo] {} = { changes := some 2, lastInsertRowid := some 9 } := by
  decide +kernel

end Belay.Sqlite.Model.CounterExamples
