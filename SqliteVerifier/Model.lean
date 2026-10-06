import SqliteVerifier.Declarations

set_option doc.verso true

/-! Stored observations for the restricted ordinary-table backend. No coercions,
SQL expressions or native-engine correctness are assumed here. Existing schema
properties are retained exactly; Valid deliberately overapproximates native data. -/

namespace SqliteVerifier

/-- Opaque stored values; preservation neither evaluates nor coerces them.
Use {lean}`Value.null` for NULL. Not every tagged value is representable by SQLite. -/
inductive Value where
  /-- A NULL cell, distinct from an empty text or BLOB cell. -/
  | null
  /-- An integer cell; native representability requires a separate range check. -/
  | integer (value : Int)
  /-- A REAL cell's exact IEEE bits, preserving distinctions such as signed zero. -/
  | real (bits : UInt64)
  /-- A text cell's bytes; no encoding conversion is performed here. -/
  | text (bytes : List UInt8)
  /-- A BLOB cell's bytes; {lean}`Value.blob []` is an empty BLOB. -/
  | blob (bytes : List UInt8)
  deriving Repr, DecidableEq

/-- A stored row with physical identity and ordered cells. Supply the SQLite
rowid rather than an application key; use an empty cell list only for zero width. -/
structure Row where
  /-- Physical rowid; the admitted signed 64-bit range is checked separately. -/
  rowid : Int
  /-- Cells in column order; the list retains NULLs and duplicate values. -/
  values : List Value
  deriving Repr, DecidableEq

/-- Stored columns, rows and properties. Use an empty row list for an empty
table and omit properties when there are no retained keys or indexes. -/
structure Table where
  /-- Column declarations in physical order. -/
  columns : List Column
  /-- Stored rows in observation order, including physical rowids. -/
  rows : List Row
  /-- Retained keys and indexes; the default has neither. -/
  properties : TableProperties := {}
  deriving Repr, DecidableEq

/-- One finite schema entry. Supply a decoded, normalized name and ordered
columns; omit properties when there are no retained keys or indexes. -/
structure TableSchema where
  /-- Table identifier, for example {lean}`"items"`. -/
  name : String
  /-- Column declarations in physical order. -/
  columns : List Column
  /-- Retained keys and indexes; the default has neither. -/
  properties : TableProperties := {}
  deriving Repr, DecidableEq

/-- Ordered finite {name}`TableSchema` entries; {lean}`([] : Schema)` is empty. -/
abbrev Schema := List TableSchema

/-- A table lookup by name; {lean}`(fun _ => none : Database)` stores no tables. -/
abbrev Database := String → Option Table

/-- Fold ASCII capitals to lowercase; leave every other character unchanged.
This also applies to decoded quoted identifiers. -/
def normalizeIdentifier (name : String) : String :=
  name.map fun c => if 'A' ≤ c ∧ c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c

/-- Admit a nonempty normalized name except {lit}`rowid`, {lit}`_rowid_` and
{lit}`oid`, with a spelling that satisfies {name}`declaredTypeMatches`.
The excluded names would hide physical rowid observations. -/
def supportedColumn (column : Column) : Bool :=
  column.name != "" && normalizeIdentifier column.name == column.name &&
    !(["rowid", "_rowid_", "oid"].contains column.name) && declaredTypeMatches column

/-- The current model's fixed column bound; {assert}`maximumColumns = 2000`. -/
def maximumColumns : Nat := 2000

/-- Require nonempty columns within {name}`maximumColumns`, each admitted by
{name}`supportedColumn`, and no duplicate column names. -/
def supportedColumns (columns : List Column) : Bool :=
  !columns.isEmpty && columns.length ≤ maximumColumns && columns.all supportedColumn &&
    -- ponytail: quadratic duplicate check is bounded at 2000; use a set if profiling warrants it.
    (columns.map Column.name).eraseDups.length == columns.length

/-- Require a nonempty normalized name without the {lit}`sqlite_` prefix.
Engine-managed objects need the separate existing-table check. -/
def supportedTableName (name : String) : Bool :=
  name != "" && normalizeIdentifier name == name && !name.startsWith "sqlite_"

/-- Require a nonempty list of distinct names, each present in the given
columns. This tests the declaration, not key values or NULL behavior. -/
def supportedKey (columns : List Column) (key : List String) : Bool :=
  !key.isEmpty && key.eraseDups.length == key.length &&
    key.all (fun name => columns.any (fun column => column.name == name))

/-- Admit an absent or supported primary key, except the single canonical
INTEGER key that aliases rowid. Require supported UNIQUE keys, and a supported
name and key for every index. This does not check stored constraint truth. -/
def supportedProperties (columns : List Column) (properties : TableProperties) : Bool :=
  (properties.primaryKey.isEmpty || supportedKey columns properties.primaryKey) &&
  !(properties.primaryKey.length == 1 && columns.any (fun column =>
    properties.primaryKey == [column.name] && column.declaredType == .canonical &&
      column.affinity == .integer)) &&
  properties.uniqueKeys.all (supportedKey columns) &&
  properties.indexes.all (fun index => supportedTableName index.name &&
    supportedKey columns index.columns)

/-- Construct columns with the given names, BLOB affinity and no declared type.
The remaining fields use {name}`Column` defaults. -/
def statisticsColumns (names : List String) : List Column :=
  names.map fun name => { name := name, affinity := .blob, declaredType := .untyped }

/-- Admit a {name}`supportedTableName`, or exactly the retained column shapes
of {lit}`sqlite_stat1` and {lit}`sqlite_stat4` with default properties.
Ordinary names impose no column or property check in this predicate. -/
def supportedExistingTable (entry : TableSchema) : Bool :=
  supportedTableName entry.name ||
    entry == { name := "sqlite_stat1", columns := statisticsColumns ["tbl", "idx", "stat"] } ||
    entry == { name := "sqlite_stat4", columns := statisticsColumns ["tbl", "idx", "neq", "nlt", "ndlt", "sample"] }

/-- For the given rowid, require both signed 64-bit bounds:
* It is at least negative two to the power 63.
* It is less than two to the power 63. -/
def validRowid (rowid : Int) : Prop := -(2 ^ 63 : Int) ≤ rowid ∧ rowid < 2 ^ 63

/-- For the given table, require all three conditions:
* {name}`supportedColumns` accepts its columns.
* Its physical rowids have no duplicates.
* Every stored row satisfies {name}`validRowid` and has one cell per column.
With no rows, the last two conditions impose nothing; column support remains. -/
def Table.Valid (table : Table) : Prop :=
  supportedColumns table.columns = true ∧
  (table.rows.map Row.rowid).Nodup ∧
  ∀ row ∈ table.rows, validRowid row.rowid ∧ row.values.length = table.columns.length

/-- For the given schema, table names have no duplicates. For every entry:
* {name}`supportedExistingTable` accepts it.
* {name}`supportedColumns` and {name}`supportedProperties` accept its metadata.
* The combined table and index names across the entire schema have no duplicates.
For an empty schema, all entry requirements are vacuous. -/
def Schema.Valid (schema : Schema) : Prop :=
  (schema.map TableSchema.name).Nodup ∧
  ∀ entry ∈ schema, supportedExistingTable entry = true ∧
    supportedColumns entry.columns = true ∧ supportedProperties entry.columns entry.properties = true ∧
    (schema.flatMap (fun table => table.name :: table.properties.indexes.map IndexDefinition.name)).Nodup

/-- Return the first matching entry's columns, or {lean}`(none : Option (List Column))`.
This derives a lookup without selecting stored data. -/
def Schema.lookup (schema : Schema) (name : String) : Option (List Column) :=
  (schema.find? fun entry => entry.name == name).map TableSchema.columns

/-- Return the first matching entry's properties, or
{lean}`(none : Option TableProperties)`; absence is distinct from empty properties. -/
def Schema.lookupProperties (schema : Schema) (name : String) : Option TableProperties :=
  (schema.find? fun entry => entry.name == name).map TableSchema.properties

/-- For the given schema and database, require {name}`Schema.Valid`. For every name:
* Stored column lookup equals {name}`Schema.lookup`, including absence.
* Every table stored there satisfies {name}`Table.Valid`, and
  {name}`Schema.lookupProperties` returns {name}`Option.some` of its properties.
If no table is stored there, the second item is vacuous. Native representability
is a separate claim. -/
def Conforms (schema : Schema) (database : Database) : Prop :=
  schema.Valid ∧ ∀ name,
    (database name).map Table.columns = schema.lookup name ∧
    ∀ table, database name = some table → table.Valid ∧
      schema.lookupProperties name = some table.properties

/-- Use the first schema entry for each name to construct a table with no rows.
Missing entries yield no table. Validity remains a separate proof obligation. -/
def Schema.emptyDatabase (schema : Schema) : Database :=
  fun name => (schema.find? fun entry => entry.name == name).map fun entry =>
    { columns := entry.columns, rows := [], properties := entry.properties }

/-- Store the given table at exactly the given name; retain every other lookup. -/
def Database.set (database : Database) (name : String) (table : Table) : Database :=
  fun other => if other = name then some table else database other

/-- Append the given number of {name}`Value.null` cells; preserve the physical rowid.
A count of zero leaves the row unchanged. -/
def Row.appendNulls (row : Row) (count : Nat) : Row :=
  { row with values := row.values ++ List.replicate count .null }

/-- Append the given columns and one NULL per new column to every row.
Preserve existing cells, rowids, row order and table properties. -/
def Table.appendColumns (table : Table) (columns : List Column) : Table :=
  { table with
    columns := table.columns ++ columns
    rows := table.rows.map (·.appendNulls columns.length) }

/-- For every row, retain its rowid and select cells in requested-name order.
Use the first matching column; return {name}`Option.none` when the column or
corresponding cell is absent. Repeated names repeat their selected cells. -/
def Table.project (table : Table) (names : List String) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, names.map fun name => do
    let index ← table.columns.findIdx? (fun column => column.name == name)
    row.values[index]?)

end SqliteVerifier
