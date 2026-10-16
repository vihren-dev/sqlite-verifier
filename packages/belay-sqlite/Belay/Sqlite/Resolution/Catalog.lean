import Belay.Sqlite.Declarations
import Belay.Sqlite.Resolution.Syntax

set_option doc.verso true

/-! The catalog that name resolution reads and updates. Tables and indexes share
one namespace, as in {lit}`sqlite_schema`. Names keep their case as written;
lookup compares SQLite's ASCII-folded form ({name}`Belay.Sqlite.normalizeIdentifier`).
Columns keep their declared type text, and the affinity function computes the
affinity from it. -/

namespace Belay.Sqlite

/-- One catalog column. Supply the name and declared type as written; omit the
constraint fields for a nullable column without a default. -/
structure CatalogColumn where
  /-- The column name as written, for example {lit}`Id`. -/
  name : String
  /-- The declared type text, or {lean}`(none : Option String)` for no type. -/
  declaredType : Option String
  /-- Whether the column declares NOT NULL. -/
  notNull : Bool := false
  /-- The {lit}`ON CONFLICT` algorithm of the NOT NULL constraint; ABORT without one. -/
  notNullAlgorithm : ConflictAlgorithm := .abort
  /-- The DEFAULT expression as written; omit it for no default. -/
  defaultValue : Option Syntax.Expr := none
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
  /-- The {lit}`ON CONFLICT` algorithm of each UNIQUE constraint, in the order of
  {lit}`uniqueKeys`, none without the clause; a constraint without an entry has none. -/
  uniqueAlgorithms : List (Option ConflictAlgorithm) := []
  deriving Repr, DecidableEq

/-- The {lit}`ON CONFLICT` algorithm of the UNIQUE constraint at the position, none for a
constraint without the clause or without an entry. -/
def CatalogTable.uniqueAlgorithm (table : CatalogTable) (index : Nat) : Option ConflictAlgorithm :=
  table.uniqueAlgorithms.getD index none

/-- The algorithms of the UNIQUE constraints, one for each key of
{name}`CatalogTable.uniqueKeys`. -/
def CatalogTable.keyedUniqueAlgorithms (table : CatalogTable) : List (Option ConflictAlgorithm) :=
  table.uniqueKeys.mapIdx fun index _ => table.uniqueAlgorithm index

/-- One index entry: the catalog position of its table and its key columns. -/
structure CatalogIndex where
  /-- The catalog position of the indexed table. -/
  table : Nat
  /-- The key column positions in key order. -/
  columns : List Nat
  /-- Whether the index requires unique keys. -/
  unique : Bool
  deriving Repr, DecidableEq

/-- The kind and content of one catalog object. -/
inductive CatalogEntry where
  /-- A table. -/
  | table (table : CatalogTable)
  /-- An index. -/
  | index (index : CatalogIndex)
  deriving Repr, DecidableEq

/-- One named catalog object. The name is kept as written; lookup folds it. -/
structure CatalogObject where
  /-- The object name as written. -/
  name : String
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

/-- The first catalog object whose folded name equals the folded given name. -/
def Catalog.find (catalog : Catalog) (name : String) : Option (Nat × CatalogObject) :=
  findPosition (fun object => normalizeIdentifier object.name == normalizeIdentifier name) catalog

/-- The first object with the folded name, when it is a table: its position and entry. -/
def Catalog.findTable (catalog : Catalog) (name : String) : Option (Nat × CatalogTable) :=
  match catalog.find name with
  | some (position, { entry := .table table, .. }) => some (position, table)
  | some (_, { entry := .index _, .. }) => none
  | none => none

/-- The columns of the table with the name in the catalog, in table order, or
{lean}`(none : Option (List CatalogColumn))` when no table has the name. Use it to
state catalog requirements. -/
def Catalog.columnsOf (catalog : Catalog) (name : String) : Option (List CatalogColumn) :=
  (catalog.findTable name).map (·.2.columns)

/-- The position of the first column whose folded name equals the folded given name. -/
def columnPosition (columns : List CatalogColumn) (name : String) : Option Nat :=
  (findPosition (fun column => normalizeIdentifier column.name == normalizeIdentifier name)
    columns).map Prod.fst

/-- Whether the characters of {lit}`needle` occur contiguously in {lit}`haystack`. -/
def containsChars (needle : List Char) : List Char → Bool
  | [] => needle.isEmpty
  | first :: rest => needle.isPrefixOf (first :: rest) || containsChars needle rest

/-- Whether {lit}`needle` occurs as a contiguous part of {lit}`haystack`. -/
def containsText (haystack needle : String) : Bool :=
  containsChars needle.toList haystack.toList

/-- SQLite's column affinity of a declared type ({lit}`datatype3.html`, section 3.1),
with ASCII case ignored, in the documented order (R-14349-34154):
1. The text contains {lit}`INT`: INTEGER (R-07051-38416).
2. Else it contains {lit}`CHAR`, {lit}`CLOB` or {lit}`TEXT`: TEXT (R-00243-07929).
3. Else it contains {lit}`BLOB`, or there is no type: BLOB (R-63063-00748).
4. Else it contains {lit}`REAL`, {lit}`FLOA` or {lit}`DOUB`: REAL (R-59153-45869).
5. Otherwise: NUMERIC. -/
def affinityOf : Option String → Affinity
  | none => .blob
  | some text =>
    let upper := String.ofList (text.toList.map Char.toUpper)
    if containsText upper "INT" then .integer
    else if ["CHAR", "CLOB", "TEXT"].any (containsText upper) then .text
    else if containsText upper "BLOB" then .blob
    else if ["REAL", "FLOA", "DOUB"].any (containsText upper) then .real
    else .numeric

/-- The affinity of a catalog column, from its declared type text. -/
def CatalogColumn.affinity (column : CatalogColumn) : Affinity := affinityOf column.declaredType

/-- The standard type names that SQLite recognizes in a declared type, in capitals
({lit}`sqlite3StdType`). -/
def standardTypeNames : List String := ["ANY", "BLOB", "INT", "INTEGER", "REAL", "TEXT"]

/-- A declared type as SQLite keeps and reports it: a type that is exactly one of
{name}`standardTypeNames`, with ASCII case ignored, becomes that name in capitals
({lit}`sqlite3AddColumn`); any other type text stays as written, so {lit}`int` is
{lit}`INT` and {lit}`VarChar(10)` keeps its case. -/
def reportedType : Option String → Option String
  | none => none
  | some text => some ((standardTypeNames.find? fun standard =>
      normalizeIdentifier standard == normalizeIdentifier text).getD text)

/-- Whether a declared type makes a single-column primary key an alias for the
rowid: the text equals {lit}`INTEGER` with ASCII case ignored ({lit}`lang_createtable.html`,
R-56094-57830). {lit}`INT` and {lit}`BIGINT` do not. -/
def aliasesRowid (declaredType : Option String) : Bool :=
  declaredType.map String.toUpper == some "INTEGER"

/-- The column positions of each unique key of the table at a catalog position, in
this order: the primary key when there is one, the UNIQUE constraints, and the
unique indexes on the table in catalog order. SQLite keeps each of them as an
index, and a write that makes two rows equal on one of them fails. -/
def Catalog.uniqueKeys (catalog : Catalog) (position : Nat) (table : CatalogTable) : List (List Nat) :=
  (if table.primaryKey.isEmpty then [] else [table.primaryKey]) ++ table.uniqueKeys ++
    catalog.filterMap fun object => match object.entry with
      | .index index => if index.table == position && index.unique then some index.columns else none
      | .table _ => none

/-- Whether the folded name starts with {lit}`sqlite_`, which SQLite reserves. -/
def reservedName (name : String) : Bool := (normalizeIdentifier name).startsWith "sqlite_"

/-- Whether a column name is one of SQLite's rowid names, which the model keeps
for the physical rowid. -/
def rowidName (name : String) : Bool :=
  ["rowid", "_rowid_", "oid"].contains (normalizeIdentifier name)

/-- The folded names of all catalog objects, in catalog order. -/
def Catalog.foldedNames (catalog : Catalog) : List String :=
  catalog.map fun object => normalizeIdentifier object.name

/-- No two catalog objects have the same folded name. The empty catalog has
unique names. -/
def Catalog.NamesUnique (catalog : Catalog) : Prop := catalog.foldedNames.Nodup

/-- The affinity of the column at a position, or BLOB for a position outside the list. -/
def columnAffinity (columns : List CatalogColumn) (position : Nat) : Affinity :=
  (columns[position]?.map CatalogColumn.affinity).getD .blob

end Belay.Sqlite
