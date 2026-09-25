import SqliteVerifier.Contract

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
#guard failureInfo (run additions initial) = none
#guard ((run additions initial).database "invoices").map Table.rows =
  some [⟨-4, [.integer 7, .null]⟩, ⟨9, [.integer 7, .null]⟩]
#guard ((run additions initial).database "audit").map Table.rows = some []
#guard ((run additions initial).database "invoices").map (·.project ["amount"]) =
  some [(-4, [some (.integer 7)]), (9, [some (.integer 7)])]

-- A file does not roll back its successfully committed prefix.
#guard failureInfo (run failedPrefix initial) = some (1, .tableExists "invoices")
#guard ((run failedPrefix initial).database "invoices").map Table.rows =
  some [⟨-4, [.integer 7, .null]⟩, ⟨9, [.integer 7, .null]⟩]
#guard ((run failedPrefix initial).database "unreached").isNone
#guard failureInfo (run [.addColumn "absent" { name := "x", affinity := .text }] initial) =
  some (0, .missingTable "absent")
#guard failureInfo (run [.addColumn "invoices" { name := "amount", affinity := .text }] initial) =
  some (0, .columnExists "invoices" "amount")
#guard supportedColumns (maximalTable.columns ++ [{ name := "extra", affinity := .text }]) = false
#guard failureInfo (run [.addColumn "full" { name := "extra", affinity := .text }]
  (Database.set (fun _ => none) "full" maximalTable)) = some (0, .tooManyColumns "full")
#guard failureInfo (run [.addColumn "full" { name := "column0", affinity := .text }]
  (Database.set (fun _ => none) "full" maximalTable)) = some (0, .tooManyColumns "full")

/-- Fixture-independent execution exists for every script and starting state. -/
theorem all_scripts_execute (script : List Statement) (database : Database) :
    Executes 0 script database (run script database) := runFrom_executes script database 0

/-- Fixture-independent preservation also covers every failure prefix. -/
theorem all_scripts_preserve (script : List Statement) (database : Database) :
    DatabaseExtends database (run script database).database := run_extends script database

/-- Contradictory approved conditions cannot make the expected theorem vacuous. -/
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
