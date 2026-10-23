import Belay.Sqlite.Model.Database
import Belay.Sqlite.Model.LiteralData
import Belay.Sqlite.Model.Resolution.ReadDefaults
import Belay.Sqlite.Model.Resolution.Resolved
import Belay.Sqlite.Model.QueryFunctions
import Belay.Sqlite.Model.QueryRun
import Belay.Sqlite.Model.Subqueries

set_option doc.verso true

/-! Errors, outcomes and the definition steps of the execution semantics, which
runs resolved statements. Resource failures and crashes are outside this model. -/

namespace Belay.Sqlite.Model

/-- A modeled statement error. For example, {lean}`ExecutionError.noActiveTransaction`
reports COMMIT or ROLLBACK without an open transaction. -/
inductive ExecutionError where
  /-- The execution semantics does not model this statement against this database:
  a definition outside the modeled subset, or a write to a position without a
  table. {lit}`resolve` gives no such statement for a conforming database. -/
  | unmodeled
  /-- SQLite refused to prepare the statement; resolution decided the error. -/
  | prepare (error : PrepareError)
  /-- BEGIN encounters an open transaction. -/
  | transactionAlreadyActive
  /-- COMMIT or ROLLBACK encounters no open transaction. -/
  | noActiveTransaction
  /-- A literal write violates a NOT NULL or unique-key constraint, with ABORT: the
  statement's changes are undone. -/
  | constraintViolation
  /-- A row of INSERT violates a NOT NULL or unique-key constraint with FAIL: the
  statement stops and keeps the changes of its earlier rows. -/
  | constraintFail
  /-- A row of INSERT violates a NOT NULL or unique-key constraint with ROLLBACK: the
  statement fails and the open transaction is rolled back. -/
  | constraintRollback
  /-- A query's {lit}`SUM` overflows the 64-bit integers: SQLite's {lit}`integer overflow`,
  reported while the statement runs. -/
  | integerOverflow
  /-- A value for a rowid alias that is not an integer after INTEGER affinity, a NULL
  assigned to it by UPDATE, or a value bound to {lit}`LIMIT ?` or {lit}`OFFSET ?` of a query that
  is not an integer ({lit}`Query.bindWindow`): SQLite's {lit}`datatype mismatch`
  ({lit}`SQLITE_MISMATCH`), reported while the statement runs. -/
  | datatypeMismatch
  /-- A JSON function of a query fails: SQLite's {lit}`malformed JSON` or
  {lit}`bad JSON path`, reported while the statement runs. -/
  | functionError
  /-- ADD COLUMN would give existing rows NULL in a NOT NULL column. SQLite reports
  this during execution with primary code 1; an empty table permits the addition. -/
  | nullColumnDefault
  /-- ADD COLUMN with a time default ({lit}`CatalogColumn.clockDefault`) on a table with
  rows: SQLite's {lit}`Cannot add a column with non-constant default`, reported while the
  statement runs with primary code 1; an empty table permits the addition. -/
  | nonConstantColumnDefault
  /-- ADD COLUMN whose CHECK constraint an existing row with the new column's default
  fails: SQLite's {lit}`CHECK constraint failed`, reported while the statement runs with
  primary code 1, not as a constraint error; an empty table permits the addition (ADR 0014,
  slice 4). -/
  | checkColumnDefault
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

/-- What one statement does to the database, without its position (ADR 0006): the
database after it, or the error with the database that the statement reached, which
the script decides to keep or not ({lit}`SqlState.publish`). For example, a FAIL failure
of an INSERT reaches the database with its earlier rows. -/
abbrev Effect := Except (ExecutionError × Database) Database

/-- The database of an effect: the database after it, or the database that its error
reached. -/
def effectDatabase : Effect → Database
  | .ok database => database
  | .error (_, database) => database

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

/-- A query over a database at a clock value, with the values bound to the parameters and the
subqueries of its statement: its source rows ({name}`Resolved.Query.source`) and its run over them ({name}`Resolved.Query.run`),
both in the statement's context ({name}`Resolved.statementContext`); none when a table is
missing. -/
def Resolved.Query.runOn (query : Resolved.Query) (clock : Int) (parameters : List Value) (database : Database)
    (subqueries : List Resolved.Query) : Option (Resolved.SourceRows × Resolved.QueryRun) :=
  let context := Resolved.statementContext clock parameters database subqueries
  (query.source context database).map fun source => (source, query.run context source.rows)

/-- The effect of a query with its run ({name}`Resolved.Query.runOn`): it changes nothing; it
fails with {lean}`ExecutionError.datatypeMismatch` when a value of its window is not an integer
({name}`Resolved.QueryRun.mismatch`), else with {lean}`ExecutionError.integerOverflow` when it
overflows, else with
{lean}`ExecutionError.functionError` when its fault is {lean}`Resolved.Fault.must`, and
otherwise succeeds, also without a run. -/
def queryEffect (database : Database) : Option (Resolved.SourceRows × Resolved.QueryRun) → Effect
  | some (_, run) =>
    if run.mismatch then .error (.datatypeMismatch, database)
    else if run.overflow then .error (.integerOverflow, database)
    else if run.fault == .must then .error (.functionError, database)
    else .ok database
  | none => .ok database

/-- The effect of CREATE TABLE, ADD COLUMN, DROP, a query or a prepare error, without a position
(ADR 0006): the database after it, or the error with the database that it keeps, the
input database for every error here. SQLite refuses a statement with its prepare
error. CREATE TABLE adds the table to the catalog ({name}`Catalog.createTable`) with no
rows. ADD COLUMN reads the literal default and appends
its affinity-applied value to each existing row. A NOT NULL column with a NULL
default fails with {lean}`ExecutionError.nullColumnDefault` when rows exist, one with
a time default with {lean}`ExecutionError.nonConstantColumnDefault`, and one whose CHECK
constraint an existing row with the default fails with
{lean}`ExecutionError.checkColumnDefault`; an empty table succeeds. Unsupported default readback returns
{lean}`ExecutionError.unmodeled` and is excluded by the support check.
CREATE INDEX builds the index over the table's rows (ADR 0014, D1): a unique index whose
key has two conflicting rows ({lit}`LiteralData.uniqueRows`) fails with
{lean}`ExecutionError.constraintViolation` and keeps the catalog. CREATE TRIGGER adds the trigger
to the catalog ({name}`Catalog.createTrigger`) with no rows.
DROP removes the objects at its positions with their rows ({name}`Database.drop`) and does
not fail; the DELETE that DROP TABLE runs first when foreign keys reference the table is part of
the statement's run ({lit}`runStatement`). A setting pragma ({lit}`PRAGMA setting = value`) changes nothing.
CREATE TABLE or CREATE INDEX at a position other than the end of the catalog (or over
rows that do not match the catalog), CREATE INDEX of a position without a table, and ADD
COLUMN at a position without a table fail with {lean}`ExecutionError.unmodeled`:
{lit}`resolve` gives no such statement for a conforming database. A query changes nothing: its run over its source rows
({name}`Resolved.Query.run`, {name}`Resolved.Query.source`) fails with
{lean}`ExecutionError.datatypeMismatch` when a value of its window is not an integer, else with
{lean}`ExecutionError.integerOverflow` when it overflows, else with
{lean}`ExecutionError.functionError` when its fault is {lean}`Resolved.Fault.must`, and
otherwise succeeds. Its result rows are not part of the outcome. SQL execution handles transaction control and writes
separately. {lit}`clock` is the statement's clock value and {lit}`parameters` are the values
bound to its parameters, which a query's expressions may read; use {lean}`([] : List Value)` for a statement
that binds none. -/
def step (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (database : Database) : Effect :=
  match statement with
  | .createTable target name table =>
    if target == database.catalog.length && database.rows.length == database.catalog.length then
      .ok { catalog := database.catalog.createTable name table, rows := database.rows ++ [[]] }
    else .error (.unmodeled, database)
  | .addColumn target column => match database.table target with
    | none => .error (.unmodeled, database)
    | some table =>
      if column.clockDefault then
        if table.rows.isEmpty then .ok (database.addColumn target column .null)
        else .error (.nonConstantColumnDefault, database)
      else match readDefaultValue column with
      | .error _ => .error (.unmodeled, database)
      | .ok value =>
        if column.notNull && value == .null && !table.rows.isEmpty then
          .error (.nullColumnDefault, database)
        else if !table.rows.all (fun row => column.checks.all
            (LiteralData.checkHolds { row with values := row.values ++ [value] })) then
          .error (.checkColumnDefault, database)
        else .ok (database.addColumn target column value)
  | .createIndex target name index =>
    if target == database.catalog.length && database.rows.length == database.catalog.length then
      match database.table index.table with
      | none => .error (.unmodeled, database)
      | some table =>
        if index.unique && !LiteralData.uniqueRows index.uniqueKey table.rows then
          .error (.constraintViolation, database)
        else .ok { catalog := database.catalog.createIndex name index, rows := database.rows ++ [[]] }
    else .error (.unmodeled, database)
  | .createTrigger target name trigger =>
    if target == database.catalog.length && database.rows.length == database.catalog.length then
      .ok { catalog := database.catalog.createTrigger name trigger, rows := database.rows ++ [[]] }
    else .error (.unmodeled, database)
  | .drop positions _ => .ok (database.drop positions)
  | .setting .. => .ok database
  | .prepareError error => .error (.prepare error, database)
  | .query query subqueries => queryEffect database (query.runOn clock parameters database subqueries)
  | .begin | .commit | .rollback | .insert .. | .upsert .. | .update .. | .delete .. =>
    .error (.unmodeled, database)

end Belay.Sqlite.Model
