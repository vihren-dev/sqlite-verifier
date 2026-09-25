import SqliteVerifier.Model

/-! Sequential autocommit execution for the admitted schema-extension subset.
Errors below are modeled statement errors; resource/crash failures are excluded. -/

namespace SqliteVerifier

/-- Each constructor denotes one fully parsed, restricted SQLite statement. -/
inductive Statement where
  | createTable (name : String) (columns : List Column)
  | addColumn (table : String) (column : Column)
  | beginTransaction
  | commit
  | rollback
  | insert (table : String) (columns : List String) (values : List Value)
  | update (table column : String) (value : Value) (key : String) (equals : Int)
  deriving Repr, DecidableEq

/-- The legacy executable helper is limited to nullable schema extensions. -/
def Statement.isExtension : Statement → Bool
  | .createTable .. | .addColumn .. => true
  | _ => false

/-- Modeled errors retain the state committed before the offending statement. -/
inductive ExecutionError where
  | invalidDefinition
  | tableExists (name : String)
  | missingTable (name : String)
  | columnExists (table column : String)
  | tooManyColumns (table : String)
  | transactionAlreadyActive
  | noActiveTransaction
  | constraintViolation
  deriving Repr, DecidableEq

/-- Failure carries the zero-based statement position and resulting database. -/
inductive Outcome where
  | success (database : Database)
  | failure (position : Nat) (reason : ExecutionError) (database : Database)
  | pending (persisted visible : Database) (error : Option (Nat × ExecutionError))

/-- Every execution outcome exposes its actual resulting schema/data state. -/
def Outcome.database : Outcome → Database
  | .success database | .failure _ _ database => database
  | .pending _ visible _ => visible

/-- An open transaction exposes its committed snapshot separately from visible rows. -/
def Outcome.persistedDatabase : Outcome → Database
  | .pending persisted _ _ => persisted
  | outcome => outcome.database

/-- The primitive transition checks schema applicability without inspecting data. -/
def step (statement : Statement) (database : Database) (position : Nat := 0) : Outcome :=
  match statement with
  | .createTable name columns =>
    if !(supportedTableName name && supportedColumns columns && columns.all Column.plain) then
      .failure position .invalidDefinition database
    else match database name with
      | some _ => .failure position (.tableExists name) database
      | none => .success (database.set name { columns := columns, rows := [] })
  | .addColumn name column =>
    if !(supportedTableName name && supportedColumn column && column.plain) then
      .failure position .invalidDefinition database
    else match database name with
      | none => .failure position (.missingTable name) database
      | some table =>
        if table.columns.length ≥ maximumColumns then
          .failure position (.tooManyColumns name) database
        else if table.columns.any (fun old => old.name == column.name) then
          .failure position (.columnExists name column.name) database
        else .success (database.set name (table.appendColumns [column]))
  | _ => .failure position .invalidDefinition database

/-- Restricted extension helper; non-extension statements are outside this API.
The public verifier uses runSql, whose bridge requires every statement be an extension. -/
def runFrom (position : Nat) (script : List Statement) (database : Database) : Outcome :=
  match script with
  | [] => .success database
  | statement :: rest =>
    match step statement database position with
    | .failure index reason result => .failure index reason result
    | .success result => runFrom (position + 1) rest result
    | .pending persisted visible error => .pending persisted visible error

/-- Legacy extension computation starts at the first source statement. -/
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
  | pending (h : step statement database position = .pending persisted visible error) :
      Executes position (statement :: rest) database (.pending persisted visible error)

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
    | pending persisted visible error => exact .pending h

/-- The executable semantics and inductive relation have exactly the same outcomes. -/
theorem Executes.result (execution : Executes position script database outcome) :
    runFrom position script database = outcome := by
  induction execution with
  | done => rfl
  | failure h => simp [runFrom, h]
  | next h _ ih => simpa [runFrom, h] using ih
  | pending h => simp [runFrom, h]

/-- Appending statements resumes after a successful prefix and preserves its errors. -/
theorem runFrom_append (initial suffix : List Statement) (database : Database) (position : Nat) :
    runFrom position (initial ++ suffix) database =
      match runFrom position initial database with
      | .success result => runFrom (position + initial.length) suffix result
      | .failure index reason result => .failure index reason result
      | .pending persisted visible error => .pending persisted visible error := by
  induction initial generalizing database position with
  | nil => simp [runFrom]
  | cons statement rest ih =>
    simp only [List.cons_append, runFrom]
    cases outcome : step statement database position with
    | failure index reason result => rfl
    | pending persisted visible error => rfl
    | success result => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
        (ih result (position + 1))

end SqliteVerifier
