import Belay.Sqlite.Model.ResolveStatementValid
import Belay.Sqlite.Model.AddColumnFromValid
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the schema resolver facts of the Admitted atoms (ADR 0022, slice 4, part 1), each
checked by the kernel: CREATE INDEX, CREATE TRIGGER, ADD COLUMN and DROP give a valid catalog, a
prepare error leaves the catalog as it was, and the theorems of the facts apply to a concrete script. -/

namespace Belay.Sqlite.Model.AdmittedAtomsSchemaExamples

open Belay.Sqlite.Model Resolution.Examples Syntax

/-- The context of a script that runs. -/
def execution : ResolveContext := { profile := defaults, mode := .execution }

/-- The catalog after the script, or none when the resolver restricts the script. -/
def catalogAfter (script : List Statement) : Option Catalog :=
  match resolve execution [] script with
  | .resolved _ catalog => some catalog
  | .restricted _ => none

/-- Whether the catalog after the script is supported under the limits of the profile. -/
def validAfter (script : List Statement) : Bool :=
  (catalogAfter script).any (·.supported defaults.limits)

/-- The number of objects in the catalog after the script, or 99 when the script is restricted. -/
def sizeAfter (script : List Statement) : Nat := ((catalogAfter script).map List.length).getD 99

/-- CREATE TABLE {lit}`t(a INTEGER, b TEXT)`. -/
def createT : Statement := .createTable (name! "t") [column (name! "a") (some "INTEGER"), column (name! "b")] [] {}

/-- A key term: the column of the name. -/
def term (name : Identifier) : OrderTerm := { expression := .identifier name .none, descending := false }

/-- CREATE INDEX {lit}`ia ON t(a, a)` with a column twice, as SQLite allows. -/
def indexTwice : Statement := .createIndex (name! "ia") false (name! "t") [term (name! "a"), term (name! "a")] none

/-- CREATE TRIGGER {lit}`tr AFTER INSERT ON t` with an empty body. -/
def triggerOnT : Statement := .createTrigger (name! "tr") false .after .insert (name! "t") none []

/-- ALTER TABLE {lit}`t ADD COLUMN c TEXT`. -/
def addC : Statement := .addColumn (name! "t") (column (name! "c"))

/-- The script of the first examples: a table, an index, a trigger and a column. -/
def schema : List Statement := [createT, indexTwice, triggerOnT, addC]

-- Each statement of the script gives a valid catalog; the script has four objects.
example : validAfter [createT, indexTwice] = true := by decide +kernel
example : validAfter [createT, indexTwice, triggerOnT] = true := by decide +kernel
example : validAfter schema = true ∧ sizeAfter schema = 3 := by decide +kernel
-- DROP INDEX, DROP TRIGGER and DROP TABLE (with its index and trigger) give a valid catalog.
example : validAfter (schema ++ [.dropIndex (name! "ia") false]) = true ∧
    sizeAfter (schema ++ [.dropIndex (name! "ia") false]) = 2 := by decide +kernel
example : validAfter (schema ++ [.dropTrigger (name! "tr") false]) = true ∧
    sizeAfter (schema ++ [.dropTrigger (name! "tr") false]) = 2 := by decide +kernel
example : validAfter (schema ++ [.dropTable (name! "t") false]) = true ∧
    sizeAfter (schema ++ [.dropTable (name! "t") false]) = 0 := by decide +kernel
-- A prepare error leaves the catalog as it was: an index with no terms, a trigger on a SQLite
-- table, a column with the name of a column, and an index on a table that does not exist.
example : sizeAfter [createT, .createIndex (name! "ia") false (name! "t") [] none] = 1 := by decide +kernel
example : sizeAfter [createT, .createTrigger (name! "tr") false .after .insert (name! "sqlite_master") none []] = 1 := by
  decide +kernel
example : sizeAfter [createT, .addColumn (name! "t") (column (name! "a"))] = 1 := by decide +kernel
example : sizeAfter [createT, .createIndex (name! "ia") false (name! "u") [term (name! "a")] none] = 1 := by
  decide +kernel

/-- The catalog with the table {lit}`t(a INTEGER)`. -/
def oneTable : Catalog :=
  [{ name := name! "t", entry := .table { columns := [{ name := name! "a", declaredType := some "INTEGER" }] } }]

/-- The column that ADD COLUMN {lit}`c TEXT` appends: it has the name of the definition. -/
def columnC : CatalogColumn := { name := name! "c", declaredType := some "TEXT" }

-- The statement that ADD COLUMN resolves to adds the column at position 0. Its default fits.
example : (match resolveAddColumn execution oneTable (name! "t") (column (name! "c")) with
    | .ok (statement, _) => decide (statement = .addColumn 0 columnC) | .error _ => false) = true := by decide +kernel
example : strictDefaultFits columnC = true := by decide +kernel

/-- The catalog after {name}`schema`: the table {lit}`t`, the index {lit}`ia` and the trigger {lit}`tr`. -/
def schemaCatalog : Catalog := (catalogAfter schema).getD []

-- DROP TABLE of `t` drops all three positions; the index and the trigger are found by their names.
example : schemaCatalog.tableObjects 0 = [0, 1, 2] := by decide +kernel
example : schemaCatalog.findIndex (name! "ia") = some 1 ∧ (schemaCatalog.findTrigger (name! "tr")).map (·.1) = some 2 := by
  decide +kernel
-- The catalog is valid, and the positions of the drop of the table meet the condition of DROP.
example : schemaCatalog.Valid defaults.limits := by decide +kernel
example : schemaCatalog.DropClosed (schemaCatalog.tableObjects 0) :=
  Catalog.DropClosed.table (by decide +kernel : schemaCatalog.Valid defaults.limits)
    (name := name! "t") (table := ((schemaCatalog.findTable (name! "t")).map (·.2)).getD { columns := [] })
    (by decide +kernel : schemaCatalog.findTable (name! "t") =
      some (0, ((schemaCatalog.findTable (name! "t")).map (·.2)).getD { columns := [] }))
-- Each DROP of the catalog meets the condition of DROP, and the condition gives the one of slice 2.
example (after : Catalog) (ok : resolveDropTable schemaCatalog (name! "t") false = .ok (.drop [0, 1, 2], after)) :
    schemaCatalog.DropCondition [0, 1, 2] :=
  (resolveDropTable_closed defaults.limits _ _ _ _ _ (by decide +kernel) ok).dropCondition
example (after : Catalog) (ok : resolveDropIndex schemaCatalog (name! "ia") false = .ok (.drop [1], after)) :
    schemaCatalog.DropClosed [1] := resolveDropIndex_closed defaults.limits _ _ _ _ _ (by decide +kernel) ok
example (after : Catalog) (ok : resolveDropTrigger schemaCatalog (name! "tr") false = .ok (.drop [2], after)) :
    schemaCatalog.DropClosed [2] := resolveDropTrigger_closed defaults.limits _ _ _ _ _ (by decide +kernel) ok
-- The names of SQLite's schema tables are reserved.
example : schemaTableName? (name! "SQLITE_SCHEMA") = some (name! "sqlite_master") ∧
    reservedName (name! "SQLITE_SCHEMA") = true := by decide +kernel
-- The state at the start of a script is valid when the catalog is: no catalog is saved.
example : (ResolveState.initial defaults []).Valid defaults.limits :=
  ⟨by decide +kernel, by simp [ResolveState.initial]⟩

/-- Use of the theorem for scripts: the empty catalog is valid, so the catalog after the script is. -/
example (statements : List Resolved.Statement) (after : Catalog)
    (ok : resolve execution [] schema = .resolved statements after) : after.Valid defaults.limits :=
  resolve_valid execution [] after schema statements (by decide +kernel) (by decide +kernel) ok

end Belay.Sqlite.Model.AdmittedAtomsSchemaExamples
