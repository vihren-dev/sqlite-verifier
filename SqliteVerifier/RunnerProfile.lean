import SqliteVerifier.Execution

/-! Sealed runner configuration. The SQLx constructor fixes SQLite 3.46.0 source
96c92aba..., SQLx 0.9.0/libsqlite3-sys 0.30.1, WAL/NORMAL, foreign_keys=1,
legacy_alter_table=writable_schema=ignore_check_constraints=recursive_triggers=0,
trusted_schema=1, 2000 columns, 1e9 length/SQL length, expression depth 1000,
busy/acquire timeout 5s, 4MiB journal limit, 4096 pages, WAL autocheckpoint 1000,
regexp enabled and optimize-on-close enabled. Migrator defaults retain transactions,
locking and _sqlx_migrations, reject missing catalog entries, and hash all SQL bytes;
the source -- no-transaction prefix is outside this mode. No concurrent application writer,
external schema mutation, corruption or crash behavior is inferred from the model.
The corresponding native capture records all remaining compile/config identities. -/

namespace SqliteVerifier

/-- Applied metadata is matched by the exact version and original-SQL SHA-384 bytes. -/
structure MigrationIdentity where
  version : Int
  checksum : List UInt8
  deriving Repr, DecidableEq

/-- The pending final migration binds the runner's actual insertion parameters. -/
structure SqlxMigration where
  version : Int
  description : List UInt8
  checksum : List UInt8
  deriving Repr, DecidableEq

/-- This supported invocation has exactly one pending final catalog entry. -/
structure SqlxConfig where
  migration : SqlxMigration
  previous : List MigrationIdentity
  deriving Repr, DecidableEq

/-- Fixed configurations are distinct; an older proof cannot silently select a new runner. -/
inductive ExecutionProfile where
  | sqlite351Autocommit
  | sqlite346Sqlx (config : SqlxConfig)
  deriving Repr, DecidableEq

/-- SQLx stores these declarations exactly, including a non-rowid BIGINT primary key. -/
def sqlxMetadataColumns : List Column := [
  { name := "version", affinity := .integer, declaredType := .bigInt },
  { name := "description", affinity := .text, notNull := true },
  { name := "installed_on", affinity := .numeric, declaredType := .timestamp,
    notNull := true, defaultValue := some .currentTimestamp },
  { name := "success", affinity := .numeric, declaredType := .boolean, notNull := true },
  { name := "checksum", affinity := .blob, notNull := true },
  { name := "execution_time", affinity := .integer, declaredType := .bigInt, notNull := true }]

/-- A nullable BIGINT key has its ordinary unique index, never physical-rowid aliasing. -/
def sqlxMetadataProperties : TableProperties := { primaryKey := ["version"] }

/-- The finite catalog excludes duplicates, future-applied entries and malformed hashes. -/
def SqlxConfig.Valid (config : SqlxConfig) : Prop :=
  validRowid config.migration.version ∧ config.migration.checksum.length = 48 ∧
  (config.previous.map MigrationIdentity.version).Pairwise (· < ·) ∧
  ∀ identity ∈ config.previous, validRowid identity.version ∧
    identity.version < config.migration.version ∧ identity.checksum.length = 48

/-- Decode only fields read by the runner; unrelated existing metadata remains opaque. -/
def sqlxAppliedIdentity (row : Row) : Option MigrationIdentity :=
  match row.values with
  | [.integer version, _, _, .integer 1, .blob checksum, _] => some ⟨version, checksum⟩
  | _ => none

/-- This mode executes plain ADD statements and never writes bookkeeping through user SQL. -/
def sqlxPayloadSupported : Statement → Bool
  | .addColumn name column => supportedTableName name && name != "_sqlx_migrations" &&
      supportedColumn column && column.plain
  | .createTable _ _ => false

/-- The persisted profile contains both engine-defined statistics tables already. -/
def StatisticsPresent (database : Database) : Prop :=
  ∀ name fields, (name, fields) ∈ [("sqlite_stat1", ["tbl", "idx", "stat"]),
      ("sqlite_stat4", ["tbl", "idx", "neq", "nlt", "ndlt", "sample"])] →
    ∃ table, database name = some table ∧ table.columns = statisticsColumns fields ∧
      table.properties = {}

/-- Pending-target readiness is an obligation derived from approved admission, not
an assumed premise. The exact prior catalog leaves no already-applied success case. -/
def SqlxReady (config : SqlxConfig) (script : List Statement) (database : Database) : Prop :=
  config.Valid ∧ script.all sqlxPayloadSupported = true ∧ StatisticsPresent database ∧
  ∃ table, database "_sqlx_migrations" = some table ∧
    table.columns = sqlxMetadataColumns ∧ table.properties = sqlxMetadataProperties ∧
    (table.rows.map sqlxAppliedIdentity).Perm (config.previous.map some)

/-- The legacy profile adds no readiness assumptions to its existing general model. -/
def ExecutionProfile.ready (profile : ExecutionProfile) (script : List Statement)
    (database : Database) : Prop :=
  match profile with
  | .sqlite351Autocommit => True
  | .sqlite346Sqlx config => SqlxReady config script database

/-- Metadata readiness distinguishes successfully applied entries from dirty rows. -/
example : sqlxAppliedIdentity ⟨7, [.integer 4, .null, .null, .integer 0, .blob [], .null]⟩ = none := rfl

/-- The user payload cannot modify the table that the runner itself must maintain. -/
example : sqlxPayloadSupported (.addColumn "_sqlx_migrations"
    { name := "extra", affinity := .text }) = false := by decide +kernel

/-- The supported transaction profile cannot inherit CREATE/index collision gaps. -/
example : sqlxPayloadSupported (.createTable "history" [{ name := "id", affinity := .text }]) = false := rfl

end SqliteVerifier
