import Belay.Sqlite.Resolution.Catalog
import Belay.Sqlite.Resolution.Profile
import Belay.Sqlite.StoreValueLaws

set_option doc.verso true

/-! Stored tables and the database, keyed by catalog position. No coercions, SQL
expressions or native-engine correctness are assumed here. The catalog keeps the
names; {lit}`Conforms` relates a database to a catalog and the
limits of a profile, and deliberately overapproximates native data. -/

namespace Belay.Sqlite

/-- Stored rows and the catalog entry of their table. Use an empty row list for an
empty table; the catalog position that keys the database supplies the name. -/
structure Table where
  /-- Columns and keys, equal to the catalog entry of the table. -/
  shape : CatalogTable
  /-- Stored rows in observation order, including physical rowids. -/
  rows : List Row
  deriving Repr, DecidableEq

/-- Tables by catalog position; {lean}`(fun _ => none : Database)` stores no tables.
A position that holds an index or no object holds no table. -/
abbrev Database := Nat → Option Table

/-- The table at a catalog position, or {lean}`(none : Option CatalogTable)` for a
position that holds an index or is past the end. -/
def Catalog.tableAt (catalog : Catalog) (position : Nat) : Option CatalogTable :=
  match catalog[position]? with
  | some { entry := .table table, .. } => some table
  | some { entry := .index _, .. } => none
  | none => none

/-- Whether a key is nonempty, names no column twice and names only positions below
the width: {assert}`supportedKey 2 [1, 0] = true`. -/
def supportedKey (width : Nat) (key : List Nat) : Bool :=
  !key.isEmpty && key.eraseDups.length == key.length && key.all (· < width)

/-- The column names of SQLite's statistics tables, which a schema may contain. -/
def statisticsColumns : String → Option (List String)
  | "sqlite_stat1" => some ["tbl", "idx", "stat"]
  | "sqlite_stat4" => some ["tbl", "idx", "neq", "nlt", "ndlt", "sample"]
  | _ => none

/-- Admit a table entry under the limits: at least one column and at most the
column limit, no two columns with one folded name, no rowid column name, no rowid
alias, and keys that satisfy {name}`supportedKey`. -/
def CatalogTable.supported (limits : Limits) (table : CatalogTable) : Bool :=
  !table.columns.isEmpty && table.columns.length ≤ limits.columns &&
    (table.columns.map (normalizeIdentifier ·.name)).eraseDups.length == table.columns.length &&
    !table.columns.any (rowidName ·.name) && table.rowidAlias.isNone &&
    (table.primaryKey.isEmpty || supportedKey table.columns.length table.primaryKey) &&
    table.uniqueKeys.all (supportedKey table.columns.length)

/-- Admit one catalog object. A table satisfies {lit}`CatalogTable.supported`, and
a reserved name is allowed only for a statistics table with exactly its typeless
columns and no keys. An index names a table position of the catalog, a supported
key of that table and a name that is not reserved. -/
def CatalogObject.supported (limits : Limits) (catalog : Catalog) (object : CatalogObject) : Bool :=
  match object.entry with
  | .table table => table.supported limits && (!reservedName object.name ||
      (statisticsColumns (normalizeIdentifier object.name)).any fun names =>
        table == { columns := names.map fun name => { name, declaredType := none } })
  | .index index => !reservedName object.name &&
      (catalog.tableAt index.table).any fun table => supportedKey table.columns.length index.columns

/-- Admit a catalog: unique folded object names and every object supported. -/
def Catalog.supported (limits : Limits) (catalog : Catalog) : Bool :=
  catalog.foldedNames.eraseDups.length == catalog.length && catalog.all (·.supported limits catalog)

/-- For the given limits, the catalog satisfies {name}`Catalog.supported`. The
empty catalog is valid under every limit. -/
def Catalog.Valid (limits : Limits) (catalog : Catalog) : Prop := catalog.supported limits = true

/-- Decide {name}`Catalog.Valid` by computing {name}`Catalog.supported`, so a literal
catalog's validity can be proved with {lit}`decide`. -/
instance Catalog.decidableValid (limits : Limits) (catalog : Catalog) : Decidable (catalog.Valid limits) :=
  inferInstanceAs (Decidable (catalog.supported limits = true))

/-- For the given rowid, require both signed 64-bit bounds:
* It is at least negative two to the power 63.
* It is less than two to the power 63. -/
def validRowid (rowid : Int) : Prop := -(2 ^ 63 : Int) ≤ rowid ∧ rowid < 2 ^ 63

/-- For the given columns and row: for every position at which both a column and a
cell exist, the cell equals {name}`storeValue` of itself with the column's affinity.
Positions without a column or without a cell impose nothing. SQLite stores every
value that it writes in this form, so every database that SQLite reaches meets it
(ADR 0012, amendment 1, question 5). -/
def Row.Stored (columns : List CatalogColumn) (row : Row) : Prop :=
  ∀ (position : Nat) (column : CatalogColumn) (value : Value),
    columns[position]? = some column → row.values[position]? = some value →
    storeValue column.affinity value = value

/-- For the given table, require both conditions:
* Its physical rowids have no duplicates.
* Every stored row satisfies {name}`validRowid`, has one cell per column, and is
  {name}`Row.Stored` for the table's columns.
With no rows, both conditions impose nothing; column support is a catalog check. -/
def Table.Valid (table : Table) : Prop :=
  (table.rows.map Row.rowid).Nodup ∧
  ∀ row ∈ table.rows, validRowid row.rowid ∧ row.values.length = table.shape.columns.length ∧
    row.Stored table.shape.columns

/-- For the given profile, catalog and database, require {name}`Catalog.Valid` under
the profile's limits. For every catalog position:
* The stored table's shape equals {name}`Catalog.tableAt`, including absence.
* Every table stored there satisfies {name}`Table.Valid`.
For a position without a table the second item is vacuous, but the first still
requires that no table is stored. Native representability and constraint truth
are separate claims. -/
def Conforms (profile : Profile) (catalog : Catalog) (database : Database) : Prop :=
  catalog.Valid profile.limits ∧ ∀ position,
    (database position).map Table.shape = catalog.tableAt position ∧
    ∀ table, database position = some table → table.Valid

/-- A database with an empty table at each table position of the catalog. Show
{name}`Conforms`, including catalog validity, separately. -/
def Catalog.emptyDatabase (catalog : Catalog) : Database :=
  fun position => (catalog.tableAt position).map fun shape => { shape, rows := [] }

/-- Store the given table at exactly the given position; retain every other lookup. -/
def Database.set (database : Database) (position : Nat) (table : Table) : Database :=
  fun other => if other = position then some table else database other

/-- Append the supplied cells and preserve the physical rowid. An empty list
leaves the row unchanged. This primitive applies no affinity or width checks. -/
def Row.appendValues (row : Row) (values : List Value) : Row :=
  { row with values := row.values ++ values }

/-- Append each column and its supplied value to every row. Apply each new
column's affinity to its value; preserve existing cells, rowids, row order and
keys. Supply {lean}`Value.null` for a column without a default. An empty list
leaves the table unchanged. -/
def Table.appendColumns (table : Table) (columns : List (CatalogColumn × Value)) : Table :=
  { table with
    shape.columns := table.shape.columns ++ columns.map Prod.fst
    rows := table.rows.map (·.appendValues (columns.map fun (column, value) => storeValue column.affinity value)) }

/-- For every row, retain its rowid and select cells in requested-name order. A
name selects the first column with the same folded name, as SQLite's name lookup
does; return {name}`Option.none` when the column or cell is absent. Repeated
names repeat their selected cells. -/
def Table.project (table : Table) (names : List String) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, names.map fun name => do
    let index ← columnPosition table.shape.columns name
    row.values[index]?)

end Belay.Sqlite
