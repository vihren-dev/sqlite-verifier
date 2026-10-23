import Belay.Sqlite.Model.SqlExecution
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of enforced foreign keys (ADR 0018, D4), each checked by the kernel: the setting
and {lit}`PRAGMA foreign_keys`, a child without a parent, the actions of a parent's DELETE and
UPDATE, a table that references itself, DROP TABLE, the prepare errors and the restriction of
a deferred key, and the fuel of the prepare check. The authored corpus of the slice checks the same rules against native SQLite. -/

namespace Belay.Sqlite.Model.ForeignKeyExamples

open Belay.Sqlite.Model Syntax Resolution.Examples

/-- The documented profile with foreign keys on. -/
def keysOn : Profile := { defaults with foreignKeys := true }

/-- A column without a type, with the constraints. -/
def plain (text : String) (constraints : List ColumnConstraint := []) : ColumnDefinition :=
  { name := Identifier.ofString text, declaredType := none, constraints }

/-- A name as written, without quotes. -/
def name (text : String) : Expr := .identifier (Identifier.ofString text) .none

/-- {lit}`CREATE TABLE p(id PRIMARY KEY)` and a child {lit}`c(x REFERENCES p ...)` with the
actions, and the rows 1 and 2 of {lit}`p` and 1 of {lit}`c`. -/
def schema (onDelete onUpdate : ForeignKeyAction) (deferral : List ColumnConstraint := []) : List Syntax.Statement :=
  [.createTable (name! "p") [plain "id" [.primaryKey false]] [],
   .createTable (name! "c") [plain "x" ([.references (name! "p") [] onDelete onUpdate] ++ deferral)] [],
   .insert (name! "p") none [[.numeric "1"], [.numeric "2"]] [], .insert (name! "c") none [[.numeric "1"]] []]

/-- {lit}`DELETE FROM p WHERE id = 1`. -/
def deleteOne : Syntax.Statement := .delete (name! "p") (some (.compare .eq (name "id") (.numeric "1"))) []

/-- {lit}`UPDATE p SET id = 3 WHERE id = 1`. -/
def updateOne : Syntax.Statement :=
  .update (name! "p") [(name! "id", .numeric "3")] (some (.compare .eq (name "id") (.numeric "1"))) []

/-- {lit}`INSERT INTO c VALUES(value)`. -/
def child (value : Expr) : Syntax.Statement := .insert (name! "c") none [[value]] []

/-- The outcome of the script from the empty catalog under the profile, and the rows of the
table at the position after it. -/
def run (script : List Syntax.Statement) (position : Nat) (profile : Profile := keysOn) :
    Option (List (List Value)) × Bool :=
  let outcome := runSql (bindValues (statements (migration [] script profile)) []) {}
  let failed := match outcome with
    | .success _ => false
    | .failure .. => true
    | .pending _ _ error => error.isSome
  (some ((outcome.database.rows.getD position []).map (·.values)), failed)

-- With foreign keys on, a child without a parent fails and keeps nothing; NULL needs none.
example : run (schema .noAction .noAction ++ [child (.numeric "9")]) 1 = (some [[.integer 1]], true) := by
  decide +kernel
example : run (schema .noAction .noAction ++ [child .null]) 1 = (some [[.integer 1], [.null]], false) := by
  decide +kernel
-- With them off, the same write succeeds; PRAGMA foreign_keys = ON turns them on.
example : run (schema .noAction .noAction ++ [child (.numeric "9")]) 1 defaults =
    (some [[.integer 1], [.integer 9]], false) := by decide +kernel
example : run (.pragma (.setting .foreignKeys (some true)) :: schema .noAction .noAction ++ [child (.numeric "9")]) 1 defaults =
    (some [[.integer 1]], true) := by decide +kernel
-- Inside a transaction the pragma does nothing: the keys stay on.
example : run (schema .noAction .noAction ++ [.begin, .pragma (.setting .foreignKeys (some false)), child (.numeric "9")]) 1 =
    (some [[.integer 1]], true) := by decide +kernel
-- PRAGMA foreign_keys is one row with the column foreign_keys.
#guard (statements (migration [] [.pragma (.setting .foreignKeys none)] keysOn)).map (fun
  | .query query _ => query.names
  | _ => []) == [["foreign_keys"]]

-- DELETE of a parent: NO ACTION fails, CASCADE deletes the child, SET NULL and SET DEFAULT write it.
example : run (schema .noAction .noAction ++ [deleteOne]) 0 = (some [[.integer 1], [.integer 2]], true) := by
  decide +kernel
example : run (schema .cascade .noAction ++ [deleteOne]) 1 = (some [], false) := by decide +kernel
example : run (schema .setNull .noAction ++ [deleteOne]) 1 = (some [[.null]], false) := by decide +kernel
-- RESTRICT fails as soon as the parent row goes.
example : run (schema .restrict .noAction ++ [deleteOne]) 0 = (some [[.integer 1], [.integer 2]], true) := by
  decide +kernel
-- UPDATE of a parent key: CASCADE writes the new key into the child.
example : run (schema .noAction .cascade ++ [updateOne]) 1 = (some [[.integer 3]], false) := by decide +kernel
example : run (schema .noAction .noAction ++ [updateOne]) 0 = (some [[.integer 1], [.integer 2]], true) := by
  decide +kernel

-- DROP TABLE of the parent deletes its rows first, with their actions: CASCADE empties the child.
example : run (schema .cascade .noAction ++ [.dropTable (name! "p") false]) 0 = (some [], false) := by decide +kernel

-- A table that references itself: deleting the root cascades down the chain.
example : run [.createTable (name! "t") [{ name := name! "id", declaredType := some "INTEGER", constraints := [.primaryKey false] },
      plain "up" [.references (name! "t") [] .cascade .noAction]] [],
    .insert (name! "t") none [[.numeric "1", .null], [.numeric "2", .numeric "1"], [.numeric "3", .numeric "2"]] [],
    .delete (name! "t") (some (.compare .eq (name "id") (.numeric "1"))) []] 0 = (some [], false) := by decide +kernel

-- A parent column without a unique index is a mismatch; a missing parent table is no such table.
#guard (statements (migration [] [.createTable (name! "p") [plain "a"] [],
    .createTable (name! "c") [plain "x" [.references (name! "p") [name! "a"] .noAction .noAction]] [],
    child (.numeric "1")] keysOn)).getLast? == some (.prepareError (.foreignKeyMismatch (name! "c") (name! "p")))
#guard (PrepareError.foreignKeyMismatch (name! "c") (name! "p")).message == "foreign key mismatch - \"c\" referencing \"p\""
#guard (statements (migration [] [.createTable (name! "c") [plain "x" [.references (name! "q") [] .noAction .noAction]] [],
    .delete (name! "c") none []] keysOn)).getLast? == some (.prepareError (.noSuchReferencedTable (name! "q")))
#guard (PrepareError.noSuchReferencedTable (name! "q")).message == "no such table: main.q"

-- A deferred key is a restriction when a write checks it; with foreign keys off it is not.
#guard restricted (migration [] (schema .noAction .noAction [.deferral true]) keysOn)
#guard !restricted (migration [] (schema .noAction .noAction [.deferral true]) defaults)

-- Work left past the fuel of the prepare check keeps the write a restriction; no work leaves none.
example : (foreignKeyIssues [] [] 0 [] [(0, .delete, false)]).toOption = some true := by decide +kernel
example : (foreignKeyIssues [] [] 0 [] []).toOption = some false := by decide +kernel

end Belay.Sqlite.Model.ForeignKeyExamples
