import Belay.Sqlite.Declarations

set_option doc.verso true

/-! Stored observations for the restricted ordinary-table backend. No coercions,
SQL expressions or native-engine correctness are assumed here. Existing schema
properties are retained exactly; Valid deliberately overapproximates native data. -/

namespace Belay.Sqlite

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

/-- Stored rows and their complete name-free metadata. Supply one shared shape
and use an empty row list for an empty table. The database key supplies its name. -/
structure Table where
  /-- Columns and retained properties, equal to the declared schema shape. -/
  shape : TableShape
  /-- Stored rows in observation order, including physical rowids. -/
  rows : List Row
  deriving Repr, DecidableEq

/-- One finite schema entry. Supply its decoded, normalized name and complete
name-free shape; stored rows belong to {name}`Table` instead. -/
structure TableSchema where
  /-- Table identifier, for example {lean}`"items"`. -/
  name : String
  /-- Complete declared columns and properties, shared with stored tables. -/
  shape : TableShape
  deriving Repr, DecidableEq

/-- Ordered finite {name}`TableSchema` entries for generated artifacts.
Valid schemas have unique names for lookup; {lean}`([] : Schema)` is empty. -/
abbrev Schema := List TableSchema
/-- A table lookup by name; {lean}`(fun _ => none : Database)` stores no tables. -/
abbrev Database := String → Option Table
/-- Copy SQLite's ASCII-only case folding, including decoded quoted identifiers.
Fold ASCII capitals to lowercase and leave every other character unchanged. -/
def normalizeIdentifier (name : String) : String :=
  name.map fun c => if 'A' ≤ c ∧ c ≤ 'Z' then Char.ofNat (c.toNat + 32) else c
/-- Admit a nonempty normalized name except {lit}`rowid`, {lit}`_rowid_` and
{lit}`oid`, with a spelling that satisfies {name}`declaredTypeMatches`.
The excluded names would hide physical rowid observations. -/
def supportedColumn (column : Column) : Bool :=
  column.name != "" && normalizeIdentifier column.name == column.name &&
    !(["rowid", "_rowid_", "oid"].contains column.name) && declaredTypeMatches column

/-- SQLite's default column limit, SQLITE_MAX_COLUMN; this profile fixes it at
{assert}`maximumColumns = 2000`. -/
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

/-- Build the typeless shapes of SQLite's engine-managed statistics tables.
Use the given names, BLOB affinity and the remaining {name}`Column` defaults. -/
def statisticsColumns (names : List String) : List Column :=
  names.map fun name => { name := name, affinity := .blob, declaredType := .untyped }

/-- Admit a {name}`supportedTableName`, or exactly the retained column shapes
of {lit}`sqlite_stat1` and {lit}`sqlite_stat4` with default properties.
Ordinary names impose no column or property check in this predicate. -/
def supportedExistingTable (entry : TableSchema) : Bool :=
  supportedTableName entry.name ||
    entry == { name := "sqlite_stat1", shape.columns := statisticsColumns ["tbl", "idx", "stat"] } ||
    entry == { name := "sqlite_stat4", shape.columns := statisticsColumns ["tbl", "idx", "neq", "nlt", "ndlt", "sample"] }

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
  supportedColumns table.shape.columns = true ∧
  (table.rows.map Row.rowid).Nodup ∧
  ∀ row ∈ table.rows, validRowid row.rowid ∧ row.values.length = table.shape.columns.length

/-- For the given schema, table names have no duplicates. For every entry:
* {name}`supportedExistingTable` accepts it.
* {name}`supportedColumns` and {name}`supportedProperties` accept its metadata.
* The combined table and index names across the entire schema have no duplicates.
For an empty schema, all entry requirements are vacuous. -/
def Schema.Valid (schema : Schema) : Prop :=
  (schema.map TableSchema.name).Nodup ∧
  ∀ entry ∈ schema, supportedExistingTable entry = true ∧
    supportedColumns entry.shape.columns = true ∧ supportedProperties entry.shape.columns entry.shape.properties = true ∧
    (schema.flatMap (fun table => table.name :: table.shape.properties.indexes.map IndexDefinition.name)).Nodup

/-- Return the first matching entry's complete shape, or
{lean}`(none : Option TableShape)`. This selects metadata rather than stored rows;
the empty schema has no shape for any name. -/
def Schema.lookupShape (schema : Schema) (name : String) : Option TableShape :=
  (schema.find? fun entry => entry.name == name).map TableSchema.shape

/-- Derive the first matching entry's columns from {name}`Schema.lookupShape`,
or {lean}`(none : Option (List Column))`. Use this convenience for column requirements. -/
def Schema.lookup (schema : Schema) (name : String) : Option (List Column) :=
  (schema.lookupShape name).map TableShape.columns

/-- Return the first matching entry's properties, or
{lean}`(none : Option TableProperties)`; absence is distinct from empty properties. -/
def Schema.lookupProperties (schema : Schema) (name : String) : Option TableProperties :=
  (schema.lookupShape name).map TableShape.properties

/-- For the given schema and database, require {name}`Schema.Valid`. For every name:
* Stored shape lookup equals {name}`Schema.lookupShape`, including absence.
* Every table stored there satisfies {name}`Table.Valid`.
For an absent table the second item is vacuous, but shape equality still requires
schema absence. Native representability and constraint truth are separate claims. -/
def Conforms (schema : Schema) (database : Database) : Prop :=
  schema.Valid ∧ ∀ name,
    (database name).map Table.shape = schema.lookupShape name ∧
    ∀ table, database name = some table → table.Valid

/-- Construct a finite empty database for executable schema calculations.
Use the first entry for each name; missing entries yield no table. Show
{name}`Conforms`, including schema and table validity, separately. -/
def Schema.emptyDatabase (schema : Schema) : Database :=
  fun name => (schema.find? fun entry => entry.name == name).map fun entry =>
    { shape := entry.shape, rows := [] }

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
    shape.columns := table.shape.columns ++ columns
    rows := table.rows.map (·.appendNulls columns.length) }

/-- For every row, retain its rowid and select cells in requested-name order.
Use the first matching column; return {name}`Option.none` when the column or
corresponding cell is absent. Repeated names repeat their selected cells. -/
def Table.project (table : Table) (names : List String) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, names.map fun name => do
    let index ← table.shape.columns.findIdx? (fun column => column.name == name)
    row.values[index]?)

end Belay.Sqlite
