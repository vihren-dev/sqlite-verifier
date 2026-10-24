import Belay.Sqlite.Model.Resolution.CatalogDrop
import Belay.Sqlite.Model.Resolution.ParentKeys
import Belay.Sqlite.Model.Resolution.Profile
import Belay.Sqlite.Model.StoreValue

set_option doc.verso true

/-! The database: a catalog and the stored rows of each catalog object. No coercions,
SQL expressions or native-engine correctness are assumed here. The catalog is the only
record of the schema; {lit}`Database.table` pairs a table's catalog entry with its rows.
The facts of an admitted and of a valid database are in {lit}`DatabaseFacts` and
{lit}`DatabaseConstraints`. -/

namespace Belay.Sqlite.Model

/-- A table as a database shows it: its catalog entry and its stored rows. The database
does not store this structure; {lit}`Database.table` builds it from the catalog. Use an
empty row list for an empty table. -/
structure Table where
  /-- Columns and keys: the catalog entry of the table. -/
  shape : CatalogTable
  /-- Stored rows in observation order, including physical rowids. -/
  rows : List Row
  deriving Repr, DecidableEq

/-- The schema and the stored rows. {lit}`rows` has one entry for each catalog object,
at the object's position; an index object has no rows. {lean}`({} : Database)` is the
empty database. -/
structure Database where
  /-- The schema: every table and index, in creation order. -/
  catalog : Catalog := []
  /-- The stored rows of the object at each catalog position, in observation order,
  including physical rowids. -/
  rows : List (List Row) := []
  deriving Repr, DecidableEq

/-- The table at a catalog position: its catalog entry with its stored rows, or
{lean}`(none : Option Table)` for a position that holds an index or is past the end. -/
def Database.table (database : Database) (position : Nat) : Option Table :=
  (database.catalog.tableAt position).map fun shape => { shape, rows := database.rows.getD position [] }

/-- A database with the named tables at positions 0, 1, … in order, each with its
entry and rows: {lean}`Database.ofTables [(name! "t", { shape := { columns := [] }, rows := [] })]`
has one empty table without columns. Use {lit}`Catalog.emptyDatabase` for a catalog with
indexes. -/
def Database.ofTables (tables : List (Identifier × Table)) : Database :=
  { catalog := tables.map fun (name, table) => { name, entry := .table table.shape },
    rows := tables.map (·.2.rows) }

/-- DROP INDEX or DROP TABLE in the database: the catalog without the objects at the
positions ({name}`Catalog.drop`), and the stored rows without the rows at those positions,
so each kept object keeps its rows at its new position. -/
def Database.drop (database : Database) (positions : List Nat) : Database :=
  { catalog := database.catalog.drop positions,
    rows := (database.rows.zipIdx.filter fun (_, position) => !positions.contains position).map Prod.fst }

/-- Store the rows at the position and keep the catalog and every other position. A
position past the end of {lit}`rows` is unchanged. -/
def Database.setRows (database : Database) (position : Nat) (rows : List Row) : Database :=
  { database with rows := database.rows.set position rows }

/-- Whether a key is nonempty and names only positions below the width. A key may name a
column twice, as SQLite accepts {lit}`PRIMARY KEY(a, a)`:
{assert}`supportedKey 2 [1, 0] = true`, {assert}`supportedKey 2 [1, 1] = true`. -/
def supportedKey (width : Nat) (key : List Nat) : Bool :=
  !key.isEmpty && key.all (· < width)

/-- Whether the rowid alias of a table is as the resolver makes it: a table without an alias
requires nothing. An alias is a position below the number of columns, whose column is not
generated and has INTEGER affinity, and it is the whole primary key, in a table that is not
{lit}`WITHOUT ROWID`. This is a rule of the model's catalog, not of SQLite: SQLite makes such an
alias only from an INTEGER PRIMARY KEY, and the resolver does too, but a table that a Lean user
builds can break the rule, and then the model does not describe the table. -/
def CatalogTable.aliasSupported (table : CatalogTable) : Bool :=
  match table.rowidAlias with
  | none => true
  | some position => table.primaryKey == [position] && !table.withoutRowid &&
      (table.columns[position]?.any fun column => column.generated.isNone && column.affinity == .integer)

/-- Whether every CHECK constraint of the table, of a column or of the table, reads only
columns below the number of columns of the table ({name}`Resolved.Expr.readsBelow`). This is a
rule of the model's catalog, not of SQLite: the resolver resolves each CHECK over the columns of
its table, but a table that a Lean user builds can have a CHECK that reads a missing column, which
reads NULL, and then the model does not describe the table. -/
def CatalogTable.checksReadBelow (table : CatalogTable) : Bool :=
  table.allChecks.all fun check => check.condition.readsBelow table.columns.length

/-- Admit a table entry under the limits: at least one column and at most the
column limit, no two columns with one folded name, no rowid column name, keys that
satisfy {name}`supportedKey`, a rowid alias as {name}`CatalogTable.aliasSupported` says, and
CHECK constraints that read only columns of the table ({name}`CatalogTable.checksReadBelow`). -/
def CatalogTable.supported (limits : Limits) (table : CatalogTable) : Bool :=
  !table.columns.isEmpty && table.columns.length ≤ limits.columns &&
    (table.columns.map (·.name.folded)).eraseDups.length == table.columns.length &&
    !table.columns.any (rowidName ·.name) &&
    (table.primaryKey.isEmpty || supportedKey table.columns.length table.primaryKey) &&
    table.uniqueKeys.all (supportedKey table.columns.length) &&
    table.aliasSupported && table.checksReadBelow

/-- Admit one catalog object. A table satisfies {lit}`CatalogTable.supported`, and
a reserved name is allowed only for a statistics table with exactly its typeless
columns and no keys. An index names a table position of the catalog, a supported
key of that table and a name that is not reserved. A trigger has a name that is not reserved
and names a table of the catalog. -/
def CatalogObject.supported (limits : Limits) (catalog : Catalog) (object : CatalogObject) : Bool :=
  match object.entry with
  | .table table => table.supported limits && (!reservedName object.name ||
      (statisticsColumns object.name.folded).any fun names =>
        table == { columns := names.map fun name => { name, declaredType := none } })
  | .index index => !reservedName object.name &&
      (catalog.tableAt index.table).any fun table => index.supported table.columns.length
  | .trigger trigger => !reservedName object.name && (catalog.findTable trigger.table).isSome

/-- Admit a catalog: unique folded names of its tables and indexes, and every object
supported. -/
def Catalog.supported (limits : Limits) (catalog : Catalog) : Bool :=
  catalog.foldedNames.eraseDups.length == (catalog.filter (!·.isTrigger)).length &&
    catalog.all (·.supported limits catalog)

/-- For the given limits, the catalog satisfies {name}`Catalog.supported`. The
empty catalog is valid under every limit. -/
def Catalog.Valid (limits : Limits) (catalog : Catalog) : Prop := catalog.supported limits = true

/-- Decide {name}`Catalog.Valid` by computing {name}`Catalog.supported`, so a literal
catalog's validity can be proved with {lit}`decide`. -/
instance Catalog.decidableValid (limits : Limits) (catalog : Catalog) : Decidable (catalog.Valid limits) :=
  inferInstanceAs (Decidable (catalog.supported limits = true))

/-- A database with the catalog and no rows at any position. Show its admission
({lit}`Catalog.emptyDatabase_conforms`), including catalog validity, separately. -/
def Catalog.emptyDatabase (catalog : Catalog) : Database :=
  { catalog, rows := catalog.map fun _ => [] }

/-- Append the supplied cells and preserve the physical rowid. An empty list
leaves the row unchanged. This primitive applies no affinity or width checks. -/
def Row.appendValues (row : Row) (values : List Value) : Row :=
  { row with values := row.values ++ values }

/-- Append each column and its supplied value to every row of the table view. Apply each
new column's affinity to its value; preserve existing cells, rowids, row order and keys.
Supply {lean}`Value.null` for a column without a default. An empty list leaves the table
unchanged. {lit}`Database.addColumn` does this to a stored table. -/
def Table.appendColumns (table : Table) (columns : List (CatalogColumn × Value)) : Table :=
  { table with
    shape.columns := table.shape.columns ++ columns.map Prod.fst
    rows := table.rows.map (·.appendValues (columns.map fun (column, value) => Value.store column.affinity value)) }

/-- ADD COLUMN in the database: append the column to the table at the position
({name}`Catalog.addColumn`) and the value, with the column's affinity applied, to each of
its rows. Rowids, row order, the other cells and every other position are unchanged.
Supply {lean}`Value.null` for a column without a default. -/
def Database.addColumn (database : Database) (position : Nat) (column : CatalogColumn) (value : Value) :
    Database :=
  { catalog := database.catalog.addColumn position column,
    rows := database.rows.modify position (·.map (·.appendValues [Value.store column.affinity value])) }

/-- For every row, retain its rowid and select cells in requested-name order. A
name selects the first column with the same folded name, as SQLite's name lookup
does; return {name}`Option.none` when the column or cell is absent. Repeated
names repeat their selected cells. -/
def Table.project (table : Table) (names : List Identifier) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, names.map fun name => do
    let index ← columnPosition table.shape.columns name
    row.values[index]?)

end Belay.Sqlite.Model
