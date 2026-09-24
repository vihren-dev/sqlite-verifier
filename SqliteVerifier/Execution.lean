import SqliteVerifier.Model

/-! Sequential autocommit execution for the admitted schema-extension subset.
Errors below are modeled statement errors; resource/crash failures are excluded. -/

namespace SqliteVerifier

/-- Each constructor denotes one fully parsed, restricted SQLite statement. -/
inductive Statement where
  | createTable (name : String) (columns : List Column)
  | addColumn (table : String) (column : Column)
  deriving Repr, DecidableEq

/-- Modeled errors retain the state committed before the offending statement. -/
inductive ExecutionError where
  | invalidDefinition
  | tableExists (name : String)
  | missingTable (name : String)
  | columnExists (table column : String)
  | tooManyColumns (table : String)
  deriving Repr, DecidableEq

/-- Failure carries the zero-based statement position and resulting database. -/
inductive Outcome where
  | success (database : Database)
  | failure (position : Nat) (reason : ExecutionError) (database : Database)

/-- Every execution outcome exposes its actual resulting schema/data state. -/
def Outcome.database : Outcome → Database
  | .success database | .failure _ _ database => database

/-- The primitive transition checks schema applicability without inspecting data. -/
def step (statement : Statement) (database : Database) (position : Nat := 0) : Outcome :=
  match statement with
  | .createTable name columns =>
    if !(supportedTableName name && supportedColumns columns) then
      .failure position .invalidDefinition database
    else match database name with
      | some _ => .failure position (.tableExists name) database
      | none => .success (database.set name ⟨columns, []⟩)
  | .addColumn name column =>
    if !(supportedTableName name && supportedColumn column) then
      .failure position .invalidDefinition database
    else match database name with
      | none => .failure position (.missingTable name) database
      | some table =>
        if table.columns.any (fun old => old.name == column.name) then
          .failure position (.columnExists name column.name) database
        else if table.columns.length ≥ maximumColumns then
          .failure position (.tooManyColumns name) database
        else .success (database.set name (table.appendColumns [column]))

/-- The file is an ordered script, not an implicit transaction. -/
def runFrom (position : Nat) (script : List Statement) (database : Database) : Outcome :=
  match script with
  | [] => .success database
  | statement :: rest =>
    match step statement database position with
    | .failure index reason result => .failure index reason result
    | .success result => runFrom (position + 1) rest result

/-- Public script execution starts at the first source statement. -/
def run (script : List Statement) (database : Database) : Outcome :=
  runFrom 0 script database

/-- Inductive executions make order and all modeled outcomes explicit. -/
inductive Executes : Nat → List Statement → Database → Outcome → Prop where
  | done : Executes position [] database (.success database)
  | failure (h : step statement database position = .failure index reason result) :
      Executes position (statement :: rest) database (.failure index reason result)
  | next (h : step statement database position = .success intermediate)
      (tail : Executes (position + 1) rest intermediate outcome) :
      Executes position (statement :: rest) database outcome

/-- No admitted script lacks an execution merely because a rule was omitted. -/
theorem runFrom_executes (script : List Statement) (database : Database) (position : Nat) :
    Executes position script database (runFrom position script database) := by
  induction script generalizing database position with
  | nil => exact .done
  | cons statement rest ih =>
    simp only [runFrom]
    cases h : step statement database position with
    | success intermediate => exact .next h (ih intermediate (position + 1))
    | failure index reason result => exact .failure h

/-- The executable semantics and inductive relation have exactly the same outcomes. -/
theorem Executes.result (execution : Executes position script database outcome) :
    runFrom position script database = outcome := by
  induction execution with
  | done => rfl
  | failure h => simp [runFrom, h]
  | next h _ ih => simpa [runFrom, h] using ih

end SqliteVerifier
