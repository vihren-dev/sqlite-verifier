import Belay.Sqlite.Model.Declarations
import Belay.Sqlite.Model.Resolution.Syntax
import Belay.Sqlite.Model.Resolution.ColumnDefault
import Belay.Sqlite.Model.Resolution.TypeAffinity
import Belay.Sqlite.Model.Resolution.Keys
import Belay.Sqlite.Model.Resolution.Checks
import Belay.Sqlite.Model.Resolution.ForeignKeys
import Belay.Sqlite.Model.Resolution.StrictTypes
import Belay.Sqlite.Model.Resolution.ReservedNames
import Belay.Sqlite.Model.Resolution.Triggers

set_option doc.verso true

/-! The objects of the catalog that name resolution reads and updates. Tables and indexes share
one namespace, as in {lit}`sqlite_schema`, and triggers have one of their own. Names keep their case as written;
lookup compares SQLite's ASCII-folded form ({name}`Belay.Sqlite.Model.Identifier.sameName`).
Columns keep their declared type text, and the affinity function
({lit}`affinityOf`, in {lit}`TypeAffinity.lean`) computes the affinity from it. -/

namespace Belay.Sqlite.Model

/-- One catalog column. Supply the name and declared type as written; omit the
constraint fields for a nullable column without a default. -/
structure CatalogColumn where
  /-- The column name as written, for example {lit}`Id`. -/
  name : Identifier
  /-- The declared type text, or {lean}`(none : Option String)` for no type. -/
  declaredType : Option String
  /-- Whether the column declares NOT NULL. -/
  notNull : Bool := false
  /-- The {lit}`ON CONFLICT` algorithm of the NOT NULL constraint; ABORT without one. -/
  notNullAlgorithm : ConflictAlgorithm := .abort
  /-- The resolved DEFAULT with its source spelling ({name}`ColumnDefault`); omit it for no
  default. -/
  defaultValue : Option ColumnDefault := none
  /-- The collation of the column ({lit}`COLLATE name`); {lit}`BINARY` without one (ADR 0014,
  D3). -/
  collation : Collation := .binary
  /-- The CHECK constraints of the column definition, in written order; omit them for none
  (ADR 0014, D2). -/
  checks : List CheckConstraint := []
  /-- The foreign keys of the column's {lit}`REFERENCES` constraints, in written order; omit
  them for none (ADR 0014, D2). -/
  foreignKeys : List ForeignKey := []
  /-- How the column is generated; omit it for a column that is not generated (ADR 0014,
  D5). -/
  generated : Option GeneratedColumn := none
  /-- The type of the column in a {lit}`STRICT` table; omit it for a column of another table
  (ADR 0014, D6). -/
  strictType : Option StrictType := none
  deriving Repr, DecidableEq

/-- One table entry. Keys are lists of column positions. Use
{lean}`(none : Option Nat)` for {name}`CatalogTable.rowidAlias` when no column is
an alias for the rowid. -/
structure CatalogTable where
  /-- The columns in table order. -/
  columns : List CatalogColumn
  /-- The primary-key column positions in key order; empty for no primary key. -/
  primaryKey : List Nat := []
  /-- The position of the column that is an alias for the rowid, if any. -/
  rowidAlias : Option Nat := none
  /-- Whether SQLite's implicit key index of the primary key is descending: the key is
  declared {lit}`PRIMARY KEY DESC` on its column and has no earlier UNIQUE constraint of
  the same column, whose ascending index SQLite keeps. Use {lean}`false` for any other key. -/
  primaryKeyDescending : Bool := false
  /-- The {lit}`ON CONFLICT` algorithm of the primary key, none without the clause. -/
  primaryKeyAlgorithm : Option ConflictAlgorithm := none
  /-- The column positions of each UNIQUE constraint, in written order. -/
  uniqueKeys : List (List Nat) := []
  /-- The number of keys of {name}`CatalogTable.uniqueKeys` whose index SQLite creates before
  the index of the primary key, which numbers the indexes {lit}`sqlite_autoindex_t_N` in that
  order: the UNIQUE constraints written before the PRIMARY KEY. Use {lean}`0` when the primary
  key comes first or has no index. -/
  uniqueBeforePrimary : Nat := 0
  /-- The {lit}`ON CONFLICT` algorithm of each UNIQUE constraint, in the order of
  {lit}`uniqueKeys`, none without the clause; a constraint without an entry has none. -/
  uniqueAlgorithms : List (Option ConflictAlgorithm) := []
  /-- Whether the table is {lit}`WITHOUT ROWID` (ADR 0014, D4): it has no rowid, its rows
  are in primary-key order, and its key columns are NOT NULL. -/
  withoutRowid : Bool := false
  /-- Whether the table is {lit}`STRICT` (ADR 0014, D6): each column has a
  {name}`CatalogColumn.strictType`. -/
  strict : Bool := false
  /-- The CHECK constraints of the table constraints, in written order; omit them for none
  (ADR 0014, D2). The CHECK constraints of a column are in {name}`CatalogColumn.checks`. -/
  checks : List CheckConstraint := []
  /-- The foreign keys of the {lit}`FOREIGN KEY` table constraints, in written order; omit them
  for none. Those of a column are in {name}`CatalogColumn.foreignKeys`. -/
  foreignKeys : List ForeignKey := []
  deriving Repr, DecidableEq

/-- Every foreign key of the table in the order in which SQLite creates them: those of each
column in column order, then those of the table constraints. {lit}`PRAGMA foreign_key_list`
numbers them in the reverse order. -/
def CatalogTable.allForeignKeys (table : CatalogTable) : List ForeignKey :=
  table.columns.flatMap (·.foreignKeys) ++ table.foreignKeys

/-- Every CHECK constraint of the table: those of each column in column order, then those
of the table constraints. This is SQLite's order of the constraints in the text of
{lit}`CREATE TABLE`, which gives the column definitions before the table constraints; ADD
COLUMN writes its column after the last column definition, so its constraints come before
those of the table constraints too. When several CHECK constraints fail for a row, SQLite
names the first of this list (SQLite 3.51, measured with the {lit}`sqlite3` shell). -/
def CatalogTable.allChecks (table : CatalogTable) : List CheckConstraint :=
  table.columns.flatMap (·.checks) ++ table.checks

/-- The kind and content of one catalog object. -/
inductive CatalogEntry where
  /-- A table. -/
  | table (table : CatalogTable)
  /-- An index. -/
  | index (index : CatalogIndex)
  /-- A trigger (ADR 0018, D5). Triggers have a namespace of their own. -/
  | trigger (trigger : CatalogTrigger)
  deriving Repr, DecidableEq

/-- One named catalog object. The name is kept as written; lookup folds it. -/
structure CatalogObject where
  /-- The object name as written. -/
  name : Identifier
  /-- The object's kind and content. -/
  entry : CatalogEntry
  deriving Repr, DecidableEq

/-- The catalog: all objects in creation order. Positions are list indexes.
{lean}`([] : Catalog)` is the empty catalog. -/
abbrev Catalog := List CatalogObject

/-- The first position whose element satisfies the test, with the element. -/
def findPosition (test : α → Bool) : List α → Option (Nat × α)
  | [] => none
  | item :: rest => if test item then some (0, item) else
      (findPosition test rest).map fun (position, found) => (position + 1, found)

/-- Whether the entry is a trigger. -/
def CatalogEntry.isTrigger : CatalogEntry → Bool
  | .trigger _ => true
  | .table _ | .index _ => false

/-- Whether the object is a trigger, whose name is in a namespace of its own. -/
def CatalogObject.isTrigger (object : CatalogObject) : Bool := object.entry.isTrigger

/-- The first table or index of the catalog whose folded name equals the folded given name;
tables and indexes share one namespace, and triggers are not in it. -/
def Catalog.find (catalog : Catalog) (name : Identifier) : Option (Nat × CatalogObject) :=
  findPosition (fun object => object.name.sameName name && !object.isTrigger) catalog

/-- The first object with the folded name, when it is a table: its position and entry. -/
def Catalog.findTable (catalog : Catalog) (name : Identifier) : Option (Nat × CatalogTable) :=
  match catalog.find name with
  | some (position, { entry := .table table, .. }) => some (position, table)
  | some (_, { entry := .index _, .. }) | some (_, { entry := .trigger _, .. }) => none
  | none => none

/-- The columns of the table with the name in the catalog, in table order, or
{lean}`(none : Option (List CatalogColumn))` when no table has the name. Use it to
state catalog requirements. -/
def Catalog.columnsOf (catalog : Catalog) (name : Identifier) : Option (List CatalogColumn) :=
  (catalog.findTable name).map (·.2.columns)

/-- The position of the first column whose folded name equals the folded given name. -/
def columnPosition (columns : List CatalogColumn) (name : Identifier) : Option Nat :=
  (findPosition (fun column => column.name.sameName name) columns).map Prod.fst

end Belay.Sqlite.Model
