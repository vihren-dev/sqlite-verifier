import Belay.Sqlite.Model.CounterExamples
import Belay.Sqlite.Model.TriggerRunExamples
import Belay.Sqlite.Model.ForeignKeyExamples

set_option doc.verso true

/-! Examples of the counters of a connection after writes that run row by row (ADR 0024, D2),
each checked by the kernel: the rows of trigger programs and foreign-key actions count for
{lit}`total_changes()` and not for {lit}`changes()`, a nested insert does not set
{lit}`last_insert_rowid()`, a nested write that completed counts also when the statement fails
later, REPLACE does not count the row that it deletes, and DROP TABLE counts the rows of the table
and the rows of the actions. The expected values are the values that native SQLite 3.51.0 gives
for the same statements. -/

namespace Belay.Sqlite.Model.CounterRowExamples

open Belay.Sqlite.Model Syntax Resolution.Examples TriggerRunExamples

/-- The counters after the statements, from the empty database on a new connection, under the
profile. -/
def countersUnder (profile : Profile) (script : List Syntax.Statement) : Counters :=
  (runScriptFrom { profile, mode := .execution } none 0 { state := { database := {}, counters := Counters.newConnection } }
    (bindValues script [])).connection.state.counters

/-- The state after the resolved statements from the state, where a statement that halts leaves its
counts on the counters, as {name}`Connection.afterError` does. The kernel cannot reduce the support
check of every statement ({name}`runScriptFrom` makes it), so these examples run the transitions
({name}`advance`) without it. -/
def stateAfter (position : Nat) : List (Resolved.Statement × List Value) → SqlState → SqlState
  | [], state => state
  | (statement, parameters) :: rest, state => match advance position statement parameters state with
    | .next next => stateAfter (position + 1) rest next
    | .halt _ => { state with counters := state.counters.apply (state.statementRun (state.clock position) parameters statement).counts }

/-- The counters after the statements, from the empty database on a new connection, under the
profile, without the support check of {name}`stateAfter`. -/
def countersOfRun (profile : Profile) (script : List Syntax.Statement) : Counters :=
  (stateAfter 0 (bindValues (statements (migration [] script profile)) [])
    { database := {}, counters := Counters.newConnection }).counters

/-- {lit}`INSERT INTO log VALUES (0), (0), (0)`: the table {lit}`log` has the rowids 1 to 3. -/
def logThree : Syntax.Statement := .insert (name! "log") none [[.numeric "0"], [.numeric "0"], [.numeric "0"]] []

/-- {lit}`INSERT INTO t VALUES (NULL, 7)`. -/
def insertSeven : Syntax.Statement := insertT [[.null, .numeric "7"]]

/-- The trigger of {lit}`t` that runs the body after each INSERT, if {lit}`new.v = 8` when the flag is set. -/
def afterInsert (body : List BodyStatement) (onlyEight : Bool := false) : Syntax.Statement :=
  trigger "a" .after .insert body (if onlyEight then some (.compare .eq (column "new" "v") (.numeric "8")) else none)

/-- A trigger program that inserts a row into {lit}`log` changes one row of {lit}`changes()` (the
row of the statement), adds both rows to the total, and leaves the last rowid at the rowid 1 of the
row in {lit}`t`, not the rowid 4 of the row in {lit}`log`. -/
example : countersUnder defaults (tables ++ [afterInsert [logged (.numeric "1")], logThree, insertSeven]) =
    { changes := some 1, totalChanges := some 5, lastInsertRowid := some 1 } := by decide +kernel

/-- A program that fails with {lit}`RAISE(ABORT)` after a nested insert: the statement changes none,
the completed nested insert counts for the total, and the last rowid keeps the rowid of the row
that the statement inserted before the failure. -/
example : countersUnder defaults (tables ++ [afterInsert [logged (.numeric "1"), selected (.raise .abort (some (text "no")))],
    insertSeven]) = { changes := some 0, totalChanges := some 1, lastInsertRowid := some 1 } := by decide +kernel

/-- A program that fails with {lit}`RAISE(FAIL)` on the second of three rows: the statement keeps
the two rows that it reached, and the one nested insert counts for the total. -/
example : countersUnder defaults (tables ++ [afterInsert [logged (.numeric "1"), selected (.raise .fail (some (text "no")))] true,
    insertT [[.null, .numeric "7"], [.null, .numeric "8"], [.null, .numeric "9"]]]) =
    { changes := some 2, totalChanges := some 3, lastInsertRowid := some 2 } := by decide +kernel

/-- A DELETE whose cascade deletes a child row: the statement changes one row, and the cascade adds
one to the total only. The two inserts of the schema set the last rowid to the rowid 1 of the child. -/
example : countersOfRun ForeignKeyExamples.keysOn (ForeignKeyExamples.schema .cascade .noAction ++ [ForeignKeyExamples.deleteOne]) =
    { changes := some 1, totalChanges := some 5, lastInsertRowid := some 1 } := by decide +kernel

/-- A DROP TABLE of a table that a child references with a cascade: the statement changes the two
rows of the table, and the total adds them with the one row of the cascade. -/
example : countersOfRun ForeignKeyExamples.keysOn
    (ForeignKeyExamples.schema .cascade .noAction ++ [.dropTable (name! "p") false]) =
    { changes := some 2, totalChanges := some 6, lastInsertRowid := some 1 } := by decide +kernel

/-- An {lit}`INSERT OR REPLACE` that replaces a row whose child cascades: the statement changes the
one row that it inserted, the replaced row does not count, the cascade adds one to the total, and the
last rowid is the rowid 3 of the new row. -/
example : countersOfRun ForeignKeyExamples.keysOn (ForeignKeyExamples.schema .cascade .noAction ++
    [.insert (name! "p") none [[.numeric "1"]] [] (some .replace)]) =
    { changes := some 1, totalChanges := some 5, lastInsertRowid := some 3 } := by decide +kernel

/-- {lit}`CREATE TABLE p(id PRIMARY KEY)`, {lit}`CREATE TABLE c(x REFERENCES p)`, the rows 1 and 2 of
{lit}`p` and the row 1 of {lit}`c`: the schema of {name}`ForeignKeyExamples.schema` without actions. -/
def plainSchema : List Syntax.Statement := ForeignKeyExamples.schema .noAction .noAction

/-- {lit}`INSERT INTO c VALUES (value), ...`. -/
def insertChildren (values : List String) : Syntax.Statement :=
  .insert (name! "c") none (values.map fun value => [.numeric value]) []

/-- A single-row INSERT without a parent fails before it stores the row: it changes none, and
leaves the last rowid at the rowid 1 of the earlier child. -/
example : countersOfRun ForeignKeyExamples.keysOn (plainSchema ++ [insertChildren ["9"]]) =
    { changes := some 0, totalChanges := some 3, lastInsertRowid := some 1 } := by decide +kernel

/-- An INSERT of two rows checks the keys at its end, after it stored both rows, so the last rowid
is the rowid 3 of the second row also when the first row has no parent. -/
example : countersOfRun ForeignKeyExamples.keysOn (plainSchema ++ [insertChildren ["9", "2"]]) =
    { changes := some 0, totalChanges := some 3, lastInsertRowid := some 3 } := by decide +kernel

/-- {lit}`PRAGMA recursive_triggers = ON`: the DELETE of a REPLACE fires its triggers. -/
def recursiveOn : Profile := { defaults with recursiveTriggers := true }

/-- {lit}`INSERT OR REPLACE INTO t VALUES (1, 'b')` after the row {lit}`(1, 'a')`, and the trigger
{lit}`AFTER DELETE ON t` with the body. -/
def replaceWithDeleteTrigger (body : List BodyStatement) : List Syntax.Statement :=
  tables ++ [insertT [[.numeric "1", text "a"]], trigger "d" .after .delete body,
    insertT [[.numeric "1", text "b"]] (some .replace)]

/-- A trigger of the DELETE of a REPLACE that fails with {lit}`RAISE(FAIL)`: the statement keeps the
delete and not the new row. It changes none, because the row that REPLACE deletes is no changed row,
and the total keeps the one row of the earlier INSERT. -/
example : countersOfRun recursiveOn (replaceWithDeleteTrigger [selected (.raise .fail (some (text "no")))]) =
    { changes := some 0, totalChanges := some 1, lastInsertRowid := some 1 } := by decide +kernel

/-- The same trigger with a nested insert before the failure: the nested insert counts for the
total. -/
example : countersOfRun recursiveOn
    (replaceWithDeleteTrigger [logged (.numeric "1"), selected (.raise .fail (some (text "no")))]) =
    { changes := some 0, totalChanges := some 2, lastInsertRowid := some 1 } := by decide +kernel

end Belay.Sqlite.Model.CounterRowExamples
