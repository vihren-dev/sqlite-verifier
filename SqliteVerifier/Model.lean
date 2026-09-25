import SqliteVerifier.Declarations

/-! Stored observations for the restricted ordinary-table backend. No coercions,
SQL expressions or native-engine correctness are assumed here. Existing schema
properties are retained exactly; Valid deliberately overapproximates native data. -/

namespace SqliteVerifier

/-- An opaque superset of stored values; preservation never evaluates/coerces them.
Native conformance supplies an embedding, not a claim that every tag is native data. -/
inductive Value where
  | null
  | integer (value : Int)
  | real (bits : UInt64)
  | text (bytes : List UInt8)
  | blob (bytes : List UInt8)
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
  properties : TableProperties := {}
  deriving Repr, DecidableEq

/-- Finite input schema entry; names arrive decoded and ASCII-normalized. -/
structure TableSchema where
  name : String
  columns : List Column
  properties : TableProperties := {}
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
    !(["rowid", "_rowid_", "oid"].contains column.name) && declaredTypeMatches column

/-- The profile fixes SQLite's ordinary-table column limit at its default value. -/
def maximumColumns : Nat := 2000

/-- Empty, duplicate, over-limit, and hidden-rowid columns are not admitted. -/
def supportedColumns (columns : List Column) : Bool :=
  !columns.isEmpty && columns.length ≤ maximumColumns && columns.all supportedColumn &&
    -- ponytail: quadratic duplicate check is bounded at 2000; use a set if profiling warrants it.
    (columns.map Column.name).eraseDups.length == columns.length

/-- Internal SQLite objects and empty names are outside this backend subset. -/
def supportedTableName (name : String) : Bool :=
  name != "" && normalizeIdentifier name == name && !name.startsWith "sqlite_"

/-- Keys use existing, distinct named columns; NULL behavior is not rewritten. -/
def supportedKey (columns : List Column) (key : List String) : Bool :=
  !key.isEmpty && key.eraseDups.length == key.length &&
    key.all (fun name => columns.any (fun column => column.name == name))

/-- Ordinary rowid tables exclude the special single INTEGER PRIMARY KEY alias. -/
def supportedProperties (columns : List Column) (properties : TableProperties) : Bool :=
  (properties.primaryKey.isEmpty || supportedKey columns properties.primaryKey) &&
  !(properties.primaryKey.length == 1 && columns.any (fun column =>
    properties.primaryKey == [column.name] && column.declaredType == .canonical &&
      column.affinity == .integer)) &&
  properties.uniqueKeys.all (supportedKey columns) &&
  properties.indexes.all (fun index => supportedTableName index.name &&
    supportedKey columns index.columns)

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
    supportedColumns entry.columns = true ∧ supportedProperties entry.columns entry.properties = true ∧
    (schema.flatMap (fun table => table.name :: table.properties.indexes.map IndexDefinition.name)).Nodup

/-- Public lookup supports schema requirements without selecting a canonical DB. -/
def Schema.lookup (schema : Schema) (name : String) : Option (List Column) :=
  (schema.find? fun entry => entry.name == name).map TableSchema.columns

/-- Metadata lookup is separate from the legacy column-only convenience lookup. -/
def Schema.lookupProperties (schema : Schema) (name : String) : Option TableProperties :=
  (schema.find? fun entry => entry.name == name).map TableSchema.properties

/-- Model-schema conformance; native representability is a separate embedding claim. -/
def Conforms (schema : Schema) (database : Database) : Prop :=
  schema.Valid ∧ ∀ name,
    (database name).map Table.columns = schema.lookup name ∧
    ∀ table, database name = some table → table.Valid ∧
      schema.lookupProperties name = some table.properties

/-- A finite empty representative is useful for executable schema calculations. -/
def Schema.emptyDatabase (schema : Schema) : Database :=
  fun name => (schema.find? fun entry => entry.name == name).map fun entry =>
    { columns := entry.columns, rows := [], properties := entry.properties }

/-- Replace one named table; untouched names retain their exact stored data. -/
def Database.set (database : Database) (name : String) (table : Table) : Database :=
  fun other => if other = name then some table else database other

/-- Row extension materializes the NULL values exposed by the added columns. -/
def Row.appendNulls (row : Row) (count : Nat) : Row :=
  { row with values := row.values ++ List.replicate count .null }

/-- Add columns without altering any existing cell or physical row identity. -/
def Table.appendColumns (table : Table) (columns : List Column) : Table :=
  { table with
    columns := table.columns ++ columns
    rows := table.rows.map (·.appendNulls columns.length) }

/-- Exact reads return none for absent columns, never invented cell values. -/
def Table.project (table : Table) (names : List String) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, names.map fun name => do
    let index ← table.columns.findIdx? (fun column => column.name == name)
    row.values[index]?)

end SqliteVerifier
