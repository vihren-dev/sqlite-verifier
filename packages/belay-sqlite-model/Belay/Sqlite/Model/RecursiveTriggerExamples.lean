import Belay.Sqlite.Model.TriggerRunExamples
import Belay.Sqlite.Model.ScriptRun

set_option doc.verso true

/-! Examples of {lit}`PRAGMA recursive_triggers` (ADR 0019, D2), each checked by the kernel: a
trigger that fires itself with the setting on and off, the depth limit of the profile, also for
a program whose {lit}`WHEN` condition is false, the DELETE triggers of the rows that REPLACE
deletes, whose programs inherit REPLACE, the setting of the profile at the start of a script,
the setting inside a transaction, and the query form. The cases follow native SQLite 3.51.0, with
{lit}`.limit trigger_depth 3` in the shell for the depth limit. -/

namespace Belay.Sqlite.Model.RecursiveTriggerExamples

open Belay.Sqlite.Model Syntax Resolution.Examples TriggerRunExamples

/-- {lit}`PRAGMA recursive_triggers = 1`. -/
def recursiveOn : Syntax.Statement := .pragma (.setting .recursiveTriggers (some true))

/-- {lit}`CREATE TRIGGER s AFTER INSERT ON t WHEN new.v < bound BEGIN INSERT INTO t VALUES
(NULL, new.v + 1); END`: with recursive triggers on, an INSERT of the row with {lit}`v` 1 gives
the rows 1 to {lit}`bound`. -/
def chain (bound : String) : Syntax.Statement :=
  trigger "s" .after .insert [.insert (name! "t") none [[.null, .arithmetic .add (column "new" "v") (.numeric "1")]] []]
    (some (.compare .lt (column "new" "v") (.numeric bound)))

/-- {lit}`INSERT INTO t VALUES (NULL, 1)`. -/
def insertOne : Syntax.Statement := insertT [[.null, .numeric "1"]]

/-- The default profile with a trigger depth limit of 3. -/
def shallow : Profile := { defaults with limits := { defaults.limits with triggerDepth := 3 } }

/-- The default profile with recursive triggers on. -/
def recursiveProfile : Profile := { defaults with recursiveTriggers := true }

/-- The outputs of a run of the statements from the empty database with the profile. -/
def outputsWith (profile : Profile) (script : List Syntax.Statement) : List Output :=
  (runScriptFrom { profile, mode := .execution } none 0 { state := { database := {} } } (bindValues script [])).outputs

-- With the setting on, the trigger fires again while it runs: the rows 1, 2 and 3. With it off,
-- it does not fire itself: one more row.
example : run (tables ++ [recursiveOn, chain "3", insertOne]) 0 =
    ([[.integer 1, .integer 1], [.integer 2, .integer 2], [.integer 3, .integer 3]], false) := by decide +kernel
example : run (tables ++ [chain "3", insertOne]) 0 = ([[.integer 1, .integer 1], [.integer 2, .integer 2]], false) := by
  decide +kernel

-- The profile's setting is the setting at the start: the same three rows without the pragma.
example : run (tables ++ [chain "3", insertOne]) 0 recursiveProfile =
    ([[.integer 1, .integer 1], [.integer 2, .integer 2], [.integer 3, .integer 3]], false) := by decide +kernel

-- Under a depth limit of 3, the chain of 3 rows runs the programs of the rows 1 to 3; the program
-- of row 3 has a false condition. The chain of 4 rows enters a program at depth 4, which SQLite
-- refuses also when its condition is false, so the model does not describe the INSERT.
example : run (tables ++ [recursiveOn, chain "3", insertOne]) 0 shallow =
    ([[.integer 1, .integer 1], [.integer 2, .integer 2], [.integer 3, .integer 3]], false) := by decide +kernel
example : (outputsWith shallow (tables ++ [recursiveOn, chain "4", insertOne])).getLast? matches some (.unmodeled _) := by
  decide +kernel

-- With the setting on, the row that REPLACE deletes fires the DELETE trigger; with it off, it
-- fires nothing (TriggerRunExamples).
example : logOf [recursiveOn, insertT [[.numeric "1", .numeric "1"]], trigger "d" .after .delete [logged (text "d")],
    insertT [[.numeric "1", .numeric "2"]] (some .replace)] = ([[.text [100]]], false) := by decide +kernel

-- The programs of the rows that REPLACE deletes inherit REPLACE: the BEFORE DELETE program inserts
-- the duplicate key 7 into u(a UNIQUE), which replaces the old row of u and does not fail.
example : run [recursiveOn, .createTable (name! "t") [plain "k" none [.unique], plain "v"] [],
    .createTable (name! "u") [plain "a" none [.unique], plain "b"] [],
    .insert (name! "t") none [[.numeric "1", text "old"]] [], .insert (name! "u") none [[.numeric "7", text "u-old"]] [],
    trigger "d" .before .delete [.insert (name! "u") none [[.numeric "7", text "new"]] []],
    .insert (name! "t") none [[.numeric "1", text "new"]] [] (some .replace)] 1 =
    ([[.integer 7, .text [110, 101, 119]]], false) := by decide +kernel

-- Inside a transaction the pragma takes effect, unlike PRAGMA foreign_keys.
example : run (tables ++ [.begin, recursiveOn, chain "3", insertOne, .commit]) 0 =
    ([[.integer 1, .integer 1], [.integer 2, .integer 2], [.integer 3, .integer 3]], false) := by decide +kernel

-- The query gives one row with the column recursive_triggers: 0 on an idle connection, and 1
-- after the pragma turns the setting on.
example : outputsWith defaults [.pragma (.setting .recursiveTriggers none), recursiveOn,
    .pragma (.setting .recursiveTriggers none)] = [.rows [[.integer 0]], .done 0, .rows [[.integer 1]]] := by
  decide +kernel

end Belay.Sqlite.Model.RecursiveTriggerExamples
