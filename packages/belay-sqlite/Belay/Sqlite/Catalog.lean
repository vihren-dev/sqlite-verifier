import Belay.Sqlite.Model
import Belay.Sqlite.Syntax

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
  /-- The column positions of each UNIQUE constraint, in written order. -/
  uniqueKeys : List (List Nat) := []
  deriving Repr, DecidableEq

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
    let upper := text.toUpper
    if containsText upper "INT" then .integer
    else if ["CHAR", "CLOB", "TEXT"].any (containsText upper) then .text
    else if containsText upper "BLOB" then .blob
    else if ["REAL", "FLOA", "DOUB"].any (containsText upper) then .real
    else .numeric

/-- The affinity of a catalog column, from its declared type text. -/
def CatalogColumn.affinity (column : CatalogColumn) : Affinity := affinityOf column.declaredType

/-- Whether a declared type makes a single-column primary key an alias for the
rowid: the text equals {lit}`INTEGER` with ASCII case ignored ({lit}`lang_createtable.html`,
R-56094-57830). {lit}`INT` and {lit}`BIGINT` do not. -/
def aliasesRowid (declaredType : Option String) : Bool :=
  declaredType.map String.toUpper == some "INTEGER"

/-- The folded names of all catalog objects, in catalog order. -/
def Catalog.foldedNames (catalog : Catalog) : List String :=
  catalog.map fun object => normalizeIdentifier object.name

/-- No two catalog objects have the same folded name. The empty catalog has
unique names. -/
def Catalog.NamesUnique (catalog : Catalog) : Prop := catalog.foldedNames.Nodup

end Belay.Sqlite
