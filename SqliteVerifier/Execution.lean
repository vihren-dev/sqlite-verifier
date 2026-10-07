import SqliteVerifier.Model

set_option doc.verso true

/-! Statement forms, errors and the primitive schema transition used by SQL execution.
Resource failures and crashes are outside this model. -/

namespace SqliteVerifier

/-- One parsed statement in the admitted syntax. Supply explicit transaction control
when needed; {lean}`Statement.beginTransaction` starts a transaction. -/
inductive Statement where
  /-- Create an absent ordinary table with the supplied columns. -/
  | createTable (name : String) (columns : List Column)
  /-- Append one nullable plain column to an existing table. -/
  | addColumn (table : String) (column : Column)
  /-- Record the current committed database as the transaction snapshot. -/
  | beginTransaction
  /-- Commit the current transaction's visible database. -/
  | commit
  /-- Restore the open transaction's original database. -/
  | rollback
  /-- Insert literal values into the supplied named columns. -/
  | insert (table : String) (columns : List String) (values : List Value)
  /-- Replace a named column where an integer key equals the supplied value. -/
  | update (table column : String) (value : Value) (key : String) (equals : Int)
  deriving Repr, DecidableEq

/-- A modeled statement error. For example, {lean}`ExecutionError.noActiveTransaction`
reports COMMIT or ROLLBACK without an open transaction. -/
inductive ExecutionError where
  /-- A definition is outside the primitive schema subset. -/
  | invalidDefinition
  /-- CREATE names an existing table. -/
  | tableExists (name : String)
  /-- The statement names an absent table. -/
  | missingTable (name : String)
  /-- ADD names an existing column. -/
  | columnExists (table column : String)
  /-- ADD reaches the configured column limit. -/
  | tooManyColumns (table : String)
  /-- BEGIN encounters an open transaction. -/
  | transactionAlreadyActive
  /-- COMMIT or ROLLBACK encounters no open transaction. -/
  | noActiveTransaction
  /-- A literal write violates a retained constraint. -/
  | constraintViolation
  deriving Repr, DecidableEq

/-- The final database and transaction status. Use {lean}`Outcome.success`
for successful execution outside a transaction. -/
inductive Outcome where
  /-- Successful computation with its resulting database. The SQL executor uses
  a pending outcome when a transaction remains open. -/
  | success (database : Database)
  /-- A stopped statement at its zero-based position, with the resulting database. -/
  | failure (position : Nat) (reason : ExecutionError) (database : Database)
  /-- An open transaction's original storage, visible database and optional error. -/
  | pending (persisted visible : Database) (error : Option (Nat × ExecutionError))

/-- Read the resulting visible database from every outcome, including an open
transaction. A separate accessor reads committed storage. -/
def Outcome.database : Outcome → Database
  | .success database | .failure _ _ database => database
  | .pending _ visible _ => visible

/-- Read the committed database: an open transaction exposes its original snapshot;
otherwise this is the visible {name}`Outcome.database`. -/
def Outcome.persistedDatabase : Outcome → Database
  | .pending persisted _ _ => persisted
  | outcome => outcome.database

/-- Check and perform CREATE TABLE or ADD COLUMN at the supplied position.
Other constructors return {lean}`ExecutionError.invalidDefinition`; SQL execution
handles their transaction or literal-data behavior separately. The default
position is zero. Successful ADD appends NULL to each existing row. -/
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

end SqliteVerifier
