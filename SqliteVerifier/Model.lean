import Std

/-! Stored observations for the restricted ordinary-table backend. No coercions,
SQL expressions, constraints, or native-engine correctness are assumed here. -/

namespace SqliteVerifier

/-- Supported declarations; the frontend accepts exactly these type names. -/
inductive Affinity where
  | integer | real | text | blob | numeric
  deriving Repr, DecidableEq

/-- Tagged stored values preserve bytes and real bits without re-evaluating SQL. -/
inductive Value where
  | null
  | integer (value : Int)
  | real (bits : UInt64)
  | text (bytes : List UInt8)
  | blob (bytes : List UInt8)
  deriving Repr, DecidableEq

/-- A column in this subset is nullable and has no constraint or explicit default. -/
structure Column where
  name : String
  affinity : Affinity
  deriving Repr, DecidableEq

/-- Row identity is the actual SQLite rowid, independently of application keys. -/
structure Row where
  rowid : Int
  values : List Value
  deriving Repr, DecidableEq

/-- Logical reads materialize implicit trailing NULL values after ADD COLUMN. -/
structure Table where
  columns : List Column
  rows : List Row
  deriving Repr, DecidableEq

/-- Finite input schema entry; names arrive decoded and ASCII-normalized. -/
structure TableSchema where
  name : String
  columns : List Column
  deriving Repr, DecidableEq

/-- Schema order is retained for generated artifacts; lookup uses unique names. -/
abbrev Schema := List TableSchema

/-- Conformance to a finite Schema excludes hidden or additional tables. -/
abbrev Database := String → Option Table

/-- SQLite identifier comparison folds ASCII only, including quoted identifiers. -/
def normalizeIdentifier (name : String) : String :=
  name.map fun c => if 'A' ≤ c ∧ c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

/-- This subset excludes aliases that would hide its rowid observations. -/
def supportedColumn (column : Column) : Bool :=
  column.name != "" && normalizeIdentifier column.name == column.name &&
    !(["rowid", "_rowid_", "oid"].contains column.name)

/-- Empty, duplicate, and hidden-rowid column definitions are not admitted. -/
def supportedColumns (columns : List Column) : Bool :=
  !columns.isEmpty && columns.all supportedColumn &&
    (columns.map Column.name).eraseDups.length == columns.length

/-- Internal SQLite objects and empty names are outside this backend subset. -/
def supportedTableName (name : String) : Bool :=
  name != "" && normalizeIdentifier name == name && !name.startsWith "sqlite_"

/-- SQLite rowids are signed 64-bit integers, not proof-only synthetic keys. -/
def validRowid (rowid : Int) : Prop := -(2 ^ 63 : Int) ≤ rowid ∧ rowid < 2 ^ 63

/-- Width and unique physical rowids connect the model to ordinary stored rows. -/
def Table.Valid (table : Table) : Prop :=
  supportedColumns table.columns = true ∧
  (table.rows.map Row.rowid).Nodup ∧
  ∀ row ∈ table.rows, validRowid row.rowid ∧ row.values.length = table.columns.length

/-- Exact schemas have no duplicate or unsupported table definitions. -/
def Schema.Valid (schema : Schema) : Prop :=
  (schema.map TableSchema.name).Nodup ∧
  ∀ entry ∈ schema, supportedTableName entry.name = true ∧
    supportedColumns entry.columns = true

/-- Public lookup supports schema requirements without selecting a canonical DB. -/
def Schema.lookup (schema : Schema) (name : String) : Option (List Column) :=
  (schema.find? fun entry => entry.name == name).map TableSchema.columns

/-- Starting data are arbitrary valid rows with exactly the supplied schema. -/
def Conforms (schema : Schema) (database : Database) : Prop :=
  schema.Valid ∧ ∀ name,
    (database name).map Table.columns = schema.lookup name ∧
    ∀ table, database name = some table → table.Valid

/-- A finite empty representative is useful for executable schema calculations. -/
def Schema.emptyDatabase (schema : Schema) : Database :=
  fun name => (schema.lookup name).map fun columns => ⟨columns, []⟩

/-- Replace one named table; untouched names retain their exact stored data. -/
def Database.set (database : Database) (name : String) (table : Table) : Database :=
  fun other => if other = name then some table else database other

/-- Row extension materializes the NULL values exposed by the added columns. -/
def Row.appendNulls (row : Row) (count : Nat) : Row :=
  { row with values := row.values ++ List.replicate count .null }

/-- Add columns without altering any existing cell or physical row identity. -/
def Table.appendColumns (table : Table) (columns : List Column) : Table :=
  ⟨table.columns ++ columns, table.rows.map (·.appendNulls columns.length)⟩

/-- Exact reads return none for absent columns, never invented cell values. -/
def Table.project (table : Table) (names : List String) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, names.map fun name => do
    let index ← table.columns.findIdx? (fun column => column.name == name)
    row.values[index]?)

end SqliteVerifier
