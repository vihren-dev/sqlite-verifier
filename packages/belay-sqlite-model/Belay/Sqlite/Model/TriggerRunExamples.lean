import Belay.Sqlite.Model.SqlExecution
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the triggers that writes run (ADR 0018, D5), each checked by the kernel: the times
and events with {lit}`NEW` and {lit}`OLD`, the order of two triggers, {lit}`WHEN`, {lit}`UPDATE OF`,
each {lit}`RAISE`, a trigger that would fire itself, REPLACE, a foreign-key action that fires a
trigger, and the change count. The cases follow native SQLite 3.51.0, and the authored corpus of
the slice checks them against it. -/

namespace Belay.Sqlite.Model.TriggerRunExamples

open Belay.Sqlite.Model Syntax Resolution.Examples

/-- A column with the type, or none. -/
def plain (text : String) (declaredType : Option String := none) (constraints : List ColumnConstraint := []) :
    ColumnDefinition :=
  { name := Identifier.ofString text, declaredType, constraints }

/-- {lit}`CREATE TABLE t(id INTEGER PRIMARY KEY, v)` and {lit}`CREATE TABLE log(x)`. -/
def tables : List Syntax.Statement :=
  [.createTable (name! "t") [plain "id" (some "INTEGER") [.primaryKey false], plain "v"] [],
   .createTable (name! "log") [plain "x"] []]

/-- {lit}`CREATE TRIGGER name time event ON t [WHEN condition] BEGIN body END`. -/
def trigger (name : String) (time : TriggerTime) (event : TriggerEvent) (body : List BodyStatement)
    (condition : Option Expr := none) (table : String := "t") : Syntax.Statement :=
  .createTrigger (Identifier.ofString name) false time event (Identifier.ofString table) condition body

/-- {lit}`INSERT INTO log VALUES (value)` in a body. -/
def logged (value : Expr) : BodyStatement := .insert (name! "log") none [[value]] []

/-- {lit}`source.column`. -/
def column (source name : String) : Expr := .qualified (Identifier.ofString source) (Identifier.ofString name)

/-- A text literal. -/
def text (value : String) : Expr := .string value.toUTF8.toList

/-- {lit}`SELECT result [WHERE filter]` in a body. -/
def selected (result : Expr) (filter : Option Expr := none) : BodyStatement :=
  .select [.expression result none ""] none [] filter [] [] none none

/-- {lit}`INSERT INTO t VALUES rows`. -/
def insertT (rows : List (List Expr)) (algorithm : Option ConflictAlgorithm := none) : Syntax.Statement :=
  .insert (name! "t") none rows [] algorithm

/-- The rows of the table at the position after the script from the empty catalog, and whether
the script failed. -/
def run (script : List Syntax.Statement) (position : Nat) (profile : Profile := defaults) :
    List (List Value) × Bool :=
  let outcome := runSql (bindValues (statements (migration [] script profile)) []) {}
  let failed := match outcome with
    | .success _ => false
    | .failure .. => true
    | .pending _ _ error => error.isSome
  ((outcome.database.rows.getD position []).map (·.values), failed)

/-- The log of the script after the two tables. -/
def logOf (script : List Syntax.Statement) : List (List Value) × Bool := run (tables ++ script) 1

-- AFTER INSERT logs NEW.id; BEFORE INSERT sees -1 for a NULL rowid alias, as SQLite has not
-- assigned the rowid yet. Of two AFTER triggers, the newer one runs first.
example : logOf [trigger "a" .after .insert [logged (column "new" "id")], insertT [[.null, .numeric "7"]]] =
    ([[.integer 1]], false) := by decide +kernel
example : logOf [trigger "c" .before .insert [logged (column "new" "id")], insertT [[.null, .numeric "7"]]] =
    ([[.integer (-1)]], false) := by decide +kernel
example : logOf [trigger "a" .after .insert [logged (text "a")], trigger "b" .after .insert [logged (text "b")],
    insertT [[.null, .numeric "1"], [.null, .numeric "2"]]] =
    ([[.text [98]], [.text [97]], [.text [98]], [.text [97]]], false) := by decide +kernel

-- UPDATE and DELETE read OLD; UPDATE OF v fires for SET v only; WHEN false skips the row.
example : logOf [insertT [[.numeric "1", .numeric "5"]], trigger "u" .after (.update [name! "v"]) [logged (column "old" "v")],
    .update (name! "t") [(name! "v", .numeric "6")] none, .update (name! "t") [(name! "id", .numeric "2")] none] =
    ([[.integer 5]], false) := by decide +kernel
example : logOf [insertT [[.numeric "1", .numeric "5"], [.numeric "2", .numeric "6"]],
    trigger "d" .after .delete [logged (column "old" "v")] (some (.compare .gt (column "old" "v") (.numeric "5"))),
    .delete (name! "t") none] = ([[.integer 6]], false) := by decide +kernel

-- RAISE(IGNORE) in a BEFORE trigger skips its row; in an AFTER trigger it keeps the row and skips
-- the triggers after it for that row.
example : run (tables ++ [trigger "c" .before .insert [selected (.raise .ignore none)
      (some (.compare .eq (column "new" "v") (.numeric "8")))], insertT [[.null, .numeric "8"], [.null, .numeric "9"]]]) 0 =
    ([[.integer 1, .integer 9]], false) := by decide +kernel
example : logOf [trigger "a" .after .insert [logged (text "a")], trigger "i" .after .insert [selected (.raise .ignore none)],
    insertT [[.null, .numeric "1"]]] = ([], false) := by decide +kernel

-- RAISE(ABORT) fails and keeps nothing; RAISE(FAIL) for the second of three rows keeps two.
example : run (tables ++ [trigger "f" .after .insert [selected (.raise .abort (some (text "no")))],
    insertT [[.null, .numeric "1"]]]) 0 = ([], true) := by decide +kernel
example : run (tables ++ [trigger "f" .after .insert [selected (.raise .fail (some (text "no")))
      (some (.compare .eq (column "new" "v") (.numeric "2")))],
    insertT [[.null, .numeric "1"], [.null, .numeric "2"], [.null, .numeric "3"]]]) 0 =
    ([[.integer 1, .integer 1], [.integer 2, .integer 2]], true) := by decide +kernel

-- A trigger that writes its own table does not fire itself: one more row, not more.
example : run (tables ++ [trigger "s" .after .insert [.insert (name! "t") none [[.null, .numeric "0"]] []],
    insertT [[.null, .numeric "1"]]]) 0 = ([[.integer 1, .integer 1], [.integer 2, .integer 0]], false) := by
  decide +kernel

-- With recursive triggers off, REPLACE fires no DELETE trigger.
example : logOf [insertT [[.numeric "1", .numeric "1"]], trigger "d" .after .delete [logged (text "d")],
    insertT [[.numeric "1", .numeric "2"]] (some .replace)] = ([], false) := by decide +kernel

-- A CASCADE of a parent's DELETE fires the child's AFTER DELETE trigger.
example : run [.pragma (.setting .foreignKeys (some true)), .createTable (name! "p") [plain "id" none [.primaryKey false]] [],
    .createTable (name! "c") [plain "x" none [.references (name! "p") [] .cascade .noAction]] [],
    .createTable (name! "log") [plain "x"] [], .insert (name! "p") none [[.numeric "1"]] [],
    .insert (name! "c") none [[.numeric "1"]] [],
    trigger "d" .after .delete [logged (column "old" "x")] none "c",
    .delete (name! "p") none] 2 = ([[.integer 1]], false) := by decide +kernel

-- The programs inherit the statement's algorithm: under INSERT OR IGNORE, the duplicate that a
-- trigger inserts into u(a UNIQUE) is ignored too, as natively both tables keep one row.
example : run [.createTable (name! "t") [plain "a"] [], .createTable (name! "u") [plain "a" none [.unique]] [],
    .insert (name! "u") none [[.numeric "1"]] [],
    trigger "r" .after .insert [.insert (name! "u") none [[column "new" "a"]] []],
    .insert (name! "t") none [[.numeric "1"]] [] (some .ignore)] 1 = ([[.integer 1]], false) := by decide +kernel

/-- The log after the script with a trigger that logs {lit}`CURRENT_TIMESTAMP`, under a clock of
Julian day 2460000 for every statement. -/
def clockLog : List (List Value) :=
  let script := statements (migration [] (tables ++ [trigger "a" .after .insert [logged (.currentTime "CURRENT_TIMESTAMP")],
    insertT [[.null, .numeric "1"]]]))
  ((runSqlAt (fun _ => 2460000 * 86400000) (bindValues script []) {}).database.rows.getD 1 []).map (·.values)

-- A statement whose trigger reads the clock reads it: the trigger logs the time, not NULL.
#guard clockLog.all fun row => row.all (· matches .text _)
#guard clockLog.length == 1

/-- The change count of the last statement of the script after the two tables. -/
def changes (script : List Syntax.Statement) : Option (List Row) :=
  match (statements (migration [] (tables ++ script))).reverse with
  | last :: earlier =>
    let state := match runSqlFrom 0 (bindValues earlier.reverse []) { database := {} } with
      | .success database => database
      | .failure _ _ database | .pending database _ _ => database
    (runStatement 0 [] last state).keyRows
  | [] => none

-- The change count of a write counts its own rows only, not those of its triggers.
#guard (changes [trigger "a" .after .insert [logged (text "a"), logged (text "b")],
  insertT [[.null, .numeric "1"], [.null, .numeric "2"]]]).map (·.length) == some 2

end Belay.Sqlite.Model.TriggerRunExamples
