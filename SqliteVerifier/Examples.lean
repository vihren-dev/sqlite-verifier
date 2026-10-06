import SqliteVerifier.ContractProofs
import SqliteVerifier.Preservation

set_option doc.verso true

/-! Runnable engineering regressions, not claimed pilot migrations or evidence
that the native SQLite implementation refines these definitions. -/

namespace SqliteVerifier.Examples

/-- Duplicate application values still denote distinct physical rows. -/
def originalTable : Table :=
  { columns := [{ name := "amount", affinity := .integer }], rows := [⟨-4, [.integer 7]⟩, ⟨9, [.integer 7]⟩] }

/-- One ordinary table provides a concrete execution witness. -/
def initial : Database := fun name => if name = "invoices" then some originalTable else none

/-- A useful multi-statement addition over an existing table. -/
def additions : List Statement :=
  [.addColumn "invoices" { name := "note", affinity := .text },
   .createTable "audit" [{ name := "message", affinity := .text }]]

/-- Repeating a creation fails after the previous column addition committed. -/
def failedPrefix : List Statement :=
  [.addColumn "invoices" { name := "note", affinity := .text },
   .createTable "invoices" [{ name := "replacement", affinity := .text }],
   .createTable "unreached" [{ name := "value", affinity := .blob }]]

/-- Inspect the outcome without comparing database functions. -/
def failureInfo : Outcome → Option (Nat × ExecutionError)
  | .success _ => none
  | .failure position reason _ => some (position, reason)
  | .pending _ _ error => error

/-- The configured column limit is deterministic behavior, not a resource exclusion. -/
def maximalTable : Table :=
  { columns := (List.range maximumColumns).map (fun index => { name := s!"column{index}", affinity := .text }), rows := [] }

-- Physical bounds and identifier comparison are independent admission checks.
example : validRowid (-9223372036854775808) := by unfold validRowid; decide
example : validRowid 9223372036854775807 := by unfold validRowid; decide
example : ¬validRowid 9223372036854775808 := by unfold validRowid; decide
#guard normalizeIdentifier "ÄInvoices" = "Äinvoices"
#guard supportedColumns [{ name := "x", affinity := .text }, { name := "x", affinity := .integer }] = false
#guard supportedColumn { name := "rowid", affinity := .integer } = false
#guard supportedTableName "sqlite_sequence" = false

-- Every old row is retained, NULL is materialized, and the new table is empty.
#guard failureInfo (runSql additions initial) = none
#guard ((runSql additions initial).database "invoices").map Table.rows =
  some [⟨-4, [.integer 7, .null]⟩, ⟨9, [.integer 7, .null]⟩]
#guard ((runSql additions initial).database "audit").map Table.rows = some []
#guard ((runSql additions initial).database "invoices").map (·.project ["amount"]) =
  some [(-4, [some (.integer 7)]), (9, [some (.integer 7)])]

-- A file does not roll back its successfully committed prefix.
#guard failureInfo (runSql failedPrefix initial) = some (1, .tableExists "invoices")
#guard ((runSql failedPrefix initial).database "invoices").map Table.rows =
  some [⟨-4, [.integer 7, .null]⟩, ⟨9, [.integer 7, .null]⟩]
#guard ((runSql failedPrefix initial).database "unreached").isNone
#guard failureInfo (runSql [.addColumn "absent" { name := "x", affinity := .text }] initial) =
  some (0, .missingTable "absent")
#guard failureInfo (runSql [.addColumn "invoices" { name := "amount", affinity := .text }] initial) =
  some (0, .columnExists "invoices" "amount")
#guard supportedColumns (maximalTable.columns ++ [{ name := "extra", affinity := .text }]) = false
#guard failureInfo (runSql [.addColumn "full" { name := "extra", affinity := .text }]
  (Database.set (fun _ => none) "full" maximalTable)) = some (0, .tooManyColumns "full")
#guard failureInfo (runSql [.addColumn "full" { name := "column0", affinity := .text }]
  (Database.set (fun _ => none) "full" maximalTable)) = some (0, .tooManyColumns "full")

/-- For every profile, script and starting database, the computed SQL result
is a related execution, including errors and open transactions. -/
theorem all_scripts_execute (profile : ExecutionProfile) (script : List Statement) (database : Database) :
    ProfileExecutes profile script database (runSql script database) := .evaluated

/-- For every schema-only script and starting database, the computed SQL result
extends the original database, including failure prefixes. The guard excludes
literal writes and transaction control. -/
theorem all_scripts_preserve (script : List Statement) (guard : SchemaOnly script) (database : Database) :
    DatabaseExtends database (runSql script database).database := runSql_extends guard database

-- A literal INSERT changes the rows, so the schema-only preservation guard is necessary.
example : ¬ SchemaOnly [.insert "invoices" ["amount"] [.integer 8]] := by simp [SchemaOnly]
#guard ((runSql [.insert "invoices" ["amount"] [.integer 8]] initial).database
  "invoices").map (fun table => table.rows.length) = some 3

/-- No complete certificate exists when the approved starting condition is false:
its required admitted witness would satisfy False. This holds for every supplied
schema, script, contract and representations. -/
example {Logical : Type} (startSchema nextSchema : Schema) (script : List Statement)
    (contract : LogicalContract Logical) (before after : Interpretation Logical)
    (failures : FailureRepresentation Logical) :
    ¬ VerificationConditions startSchema nextSchema script (fun _ => False)
      contract before after failures := by
  intro alleged
  obtain ⟨_, _, impossible⟩ := alleged.nonempty
  exact impossible

#print axioms all_scripts_execute
#print axioms all_scripts_preserve

end SqliteVerifier.Examples
