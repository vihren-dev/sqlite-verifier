import Belay.Sqlite.Model
import Belay.Sqlite.Resolution.ReadDefaults
import Belay.Sqlite.Resolution.Resolved
import Belay.Sqlite.QueryJoins

set_option doc.verso true

/-! Errors, outcomes and the definition steps of the execution semantics, which
runs resolved statements. Resource failures and crashes are outside this model. -/

namespace Belay.Sqlite

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
  /-- A literal write violates a NOT NULL or unique-key constraint. -/
  | constraintViolation
  /-- A query's {lit}`SUM` overflows the 64-bit integers: SQLite's {lit}`integer overflow`,
  reported while the statement runs. -/
  | integerOverflow
  /-- ADD COLUMN would give existing rows NULL in a NOT NULL column. SQLite reports
  this during execution with primary code 1; an empty table permits the addition. -/
  | nullColumnDefault
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

/-- Whether the model describes a definition of this column: no NOT NULL and no
default. This is a model restriction, not a SQLite rule: SQLite accepts such
columns, so the supported-subset check {lit}`statementReady` excludes them and
{lit}`step` never fails because of them. -/
def CatalogColumn.plain (column : CatalogColumn) : Bool := !column.notNull && column.defaultValue.isNone

/-- Whether the model describes a CREATE TABLE of this table: plain columns, no
keys and no rowid alias. This is a model restriction, which the supported-subset
check {lit}`statementReady` applies; {lit}`resolve` also refuses other tables in
statements that run. -/
def CatalogTable.plain (table : CatalogTable) : Bool :=
  table.columns.all CatalogColumn.plain && table.primaryKey.isEmpty && table.uniqueKeys.isEmpty &&
    table.rowidAlias.isNone

/-- Perform CREATE TABLE or ADD COLUMN at the supplied position, or fail with the
prepare error of a statement that SQLite refuses. CREATE TABLE stores an empty
table at its catalog position. ADD COLUMN reads the literal default and appends
its affinity-applied value to each existing row. A NOT NULL column with a NULL
default fails with {lean}`ExecutionError.nullColumnDefault` when rows exist;
an empty table succeeds. Unsupported default readback returns
{lean}`ExecutionError.unmodeled` and is excluded by the support check.
CREATE TABLE at an occupied position, ADD COLUMN at a position without a table,
and CREATE INDEX fail with {lean}`ExecutionError.unmodeled`: {lit}`resolve` gives
no such statement for a conforming database, and the supported-subset check
excludes CREATE INDEX. A query changes nothing; it fails with
{lean}`ExecutionError.integerOverflow` when {name}`Resolved.Query.fails` holds for its
source rows ({name}`Resolved.Query.source`), and otherwise succeeds. Its result rows are not part of the outcome. SQL execution handles transaction control and writes
separately. The default position is zero. -/
def step (statement : Resolved.Statement) (database : Database) (position : Nat := 0) : Outcome :=
  match statement with
  | .createTable at_ _ table => match database at_ with
    | some _ => .failure position .unmodeled database
    | none => .success (database.set at_ { shape := table, rows := [] })
  | .addColumn at_ column => match database at_ with
    | none => .failure position .unmodeled database
    | some table => match readDefaultValue column with
      | .error _ => .failure position .unmodeled database
      | .ok value =>
        if column.notNull && value == .null && !table.rows.isEmpty then
          .failure position .nullColumnDefault database
        else .success (database.set at_ (table.appendColumns [(column, value)]))
  | .prepareError error => .failure position (.prepare error) database
  | .query query => match query.source database with
    | some rows => if query.fails rows then .failure position .integerOverflow database else .success database
    | none => .success database
  | .createIndex .. | .begin | .commit | .rollback | .insert .. | .update .. | .delete .. =>
    .failure position .unmodeled database

end Belay.Sqlite
