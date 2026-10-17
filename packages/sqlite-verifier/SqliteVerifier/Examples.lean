import SqliteVerifier.ContractProofs
import Belay.Sqlite.Preservation

set_option doc.verso true

/-! Runnable engineering regressions, not claimed pilot migrations or evidence
that the native SQLite implementation refines these definitions. Statements are
resolved, so errors that resolution decides appear as prepare errors. -/

open Belay.Sqlite

namespace SqliteVerifier.Examples

/-- Duplicate application values still denote distinct physical rows. -/
def originalTable : Table :=
  { shape := { columns := [{ name := "amount", declaredType := some "INTEGER" }] },
    rows := [⟨-4, [.integer 7]⟩, ⟨9, [.integer 7]⟩] }

/-- One ordinary table at catalog position 0 provides a concrete execution witness. -/
def initial : Database := fun position => if position = 0 then some originalTable else none

/-- A useful multi-statement addition over an existing table. -/
def additions : List Resolved.Statement :=
  [.addColumn 0 { name := "note", declaredType := some "TEXT" },
   .createTable 1 "audit" { columns := [{ name := "message", declaredType := some "TEXT" }] }]

/-- Repeating a creation fails, as SQLite's prepare error, after the previous
column addition committed. -/
def failedPrefix : List Resolved.Statement :=
  [.addColumn 0 { name := "note", declaredType := some "TEXT" },
   .prepareError (.tableExists "invoices"),
   .createTable 1 "unreached" { columns := [{ name := "value", declaredType := none }] }]

/-- Inspect the outcome without comparing database functions. -/
def failureInfo : Outcome → Option (Nat × ExecutionError)
  | .success _ => none
  | .failure position reason _ => some (position, reason)
  | .pending _ _ error => error

/-- A table with three columns, valid under the documented limits. -/
def wide : CatalogTable :=
  { columns := ["a", "b", "c"].map fun name => { name, declaredType := some "TEXT" } }

/-- The documented limits with the column limit lowered to two. -/
def twoColumns : Limits := { Limits.documentedDefaults with columns := 2 }

-- Physical bounds and identifier comparison are independent admission checks.
example : validRowid (-9223372036854775808) := by unfold validRowid; decide
example : validRowid 9223372036854775807 := by unfold validRowid; decide
example : ¬validRowid 9223372036854775808 := by unfold validRowid; decide
#guard normalizeIdentifier "ÄInvoices" = "Äinvoices"

-- Validity uses the column limit of the profile, not a constant.
#guard wide.supported Limits.documentedDefaults
#guard wide.supported twoColumns == false
#guard ({ columns := [{ name := "rowid", declaredType := some "INTEGER" }] } : CatalogTable).supported
  Limits.documentedDefaults == false

-- Every old row is retained, NULL is materialized, and the new table is empty.
#guard failureInfo (runSql additions initial) = none
#guard ((runSql additions initial).database 0).map Table.rows =
  some [⟨-4, [.integer 7, .null]⟩, ⟨9, [.integer 7, .null]⟩]
#guard ((runSql additions initial).database 1).map Table.rows = some []
#guard ((runSql additions initial).database 0).map (·.project ["AMOUNT"]) =
  some [(-4, [some (.integer 7)]), (9, [some (.integer 7)])]

-- A file does not roll back its successfully committed prefix.
#guard failureInfo (runSql failedPrefix initial) = some (1, .prepare (.tableExists "invoices"))
#guard ((runSql failedPrefix initial).database 0).map Table.rows =
  some [⟨-4, [.integer 7, .null]⟩, ⟨9, [.integer 7, .null]⟩]
#guard ((runSql failedPrefix initial).database 1).isNone

-- Definitions outside the modeled subset are not run.
#guard failureInfo (runSql [.createIndex 1 "by_amount" { table := 0, columns := [0], unique := false }] initial) =
  some (0, .unmodeled)
#guard failureInfo (runSql [.addColumn 1 { name := "x", declaredType := none }] initial) = some (0, .unmodeled)

/-- For every profile, script, starting database and clock assignment, the computed SQL
result at the clock assignment is a related execution, including errors and open
transactions. -/
theorem all_scripts_execute (profile : Profile) (script : List Resolved.Statement) (database : Database)
    (clock : Clock) : ProfileExecutes profile script database (runSqlAt clock script database) := .evaluated clock

/-- For every schema-only script and starting database, the computed SQL result
extends the original database, including failure prefixes. The guard excludes
literal writes and transaction control. -/
theorem all_scripts_preserve (script : List Resolved.Statement) (guard : SchemaOnly script) (database : Database) :
    DatabaseExtends database (runSql script database).database := runSql_extends guard database

-- A literal INSERT changes the rows, so the schema-only preservation guard is necessary.
example : ¬ SchemaOnly [.insert 0 [[.integer 8]] [] []] := by simp [SchemaOnly]
#guard ((runSql [.insert 0 [[.integer 8]] [] []] initial).database 0).map (fun table => table.rows.length) = some 3

/-- No complete certificate exists when the approved starting condition is false:
its required admitted witness would satisfy False. This holds for every supplied
catalog, script, contract, representations and profile. -/
example {Logical : Type} (startCatalog nextCatalog : Catalog) (script : List Resolved.Statement)
    (contract : LogicalContract Logical) (before after : Interpretation Logical)
    (failures : FailureRepresentation Logical) (profile : Profile) :
    ¬ VerificationConditions startCatalog nextCatalog script (fun _ => False)
      contract before after failures profile := by
  intro alleged
  obtain ⟨_, _, impossible⟩ := alleged.nonempty
  exact impossible

#print axioms all_scripts_execute
#print axioms all_scripts_preserve

end SqliteVerifier.Examples
