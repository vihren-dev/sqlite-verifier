import VerifierConformance.Trace

/-! Native SQLite observations of tables and their catalog metadata, and their
comparison with the model's catalog and tables. The frontend reads the metadata
from {lit}`sqlite_schema`, {lit}`PRAGMA table_xinfo`, {lit}`PRAGMA index_list` and
{lit}`PRAGMA index_xinfo`; this comparison is how the conformance suite checks the
catalog that resolution computes. -/

namespace Belay.Sqlite.Conformance

/-- One column as {lit}`PRAGMA table_xinfo` reports it: the name and declared type
as written ({lit}`""` for no type), NOT NULL, and the default's text or none. -/
structure NativeColumn where
  name : String
  declaredType : String
  notNull : Bool
  defaultValue : Option String
  deriving Repr, DecidableEq

/-- One explicit index ({lit}`index_list` origin {lit}`c`): its name, key column positions and uniqueness. -/
structure NativeIndex where
  name : String
  columns : List Nat
  unique : Bool
  deriving Repr, DecidableEq

/-- One native table: its name in {lit}`sqlite_schema`, its columns, the primary-key
positions in key order, the key positions of each UNIQUE constraint index (origin
{lit}`u`), its explicit indexes, and its rows. -/
structure NativeTable where
  name : String
  columns : List NativeColumn
  primaryKey : List Nat
  uniqueKeys : List (List Nat)
  indexes : List NativeIndex
  rows : List Row
  deriving Repr, DecidableEq

/-- Where SQLite reported a statement's error: in {lit}`sqlite3_prepare_v2`, where
resolution decides it, or in {lit}`sqlite3_step`, where the execution semantics
decides it. -/
inductive ErrorPhase where
  /-- {lit}`sqlite3_prepare_v2` failed. -/
  | prepare
  /-- {lit}`sqlite3_step` failed. -/
  | step
  deriving Repr, DecidableEq

/-- Native truth after one statement. Extended codes are retained for diagnostics;
the model compares primary codes. {lit}`phase` is the phase of an error when the
recorder observed it; it is {name}`Option.none` without an error, and for records
from a recorder that did not observe phases. -/
structure NativeObservation where
  visible : List NativeTable
  persisted : List NativeTable
  transactionOpen : Bool
  primaryCode : Nat
  extendedCode : Nat
  phase : Option ErrorPhase := none
  deriving Repr, DecidableEq

/-- Insert a key into lexicographic order, with structural recursion the kernel reduces. -/
def insertKey (key : List Nat) : List (List Nat) → List (List Nat)
  | [] => [key]
  | head :: rest => if decide (key ≤ head) then key :: head :: rest else head :: insertKey key rest

/-- Keys in lexicographic order, so declaration order does not affect a comparison. -/
def sortKeys (keys : List (List Nat)) : List (List Nat) := keys.foldr insertKey []

/-- Keyword defaults whose spelling ignores ASCII case. SQLite treats each as a
keyword; quoted literals retain their delimiters and compare exactly instead. -/
def defaultKeywords : List String :=
  ["null", "true", "false", "current_timestamp", "current_time", "current_date"]

/-- Whether a catalog column matches its native metadata: the same name, the same
declared type text, NOT NULL, and the same default spelling. Keyword defaults
ignore ASCII case; all other defaults keep their exact source spelling. -/
def columnMatches (column : CatalogColumn) (native : NativeColumn) : Bool :=
  column.name == native.name && column.declaredType.getD "" == native.declaredType &&
  column.notNull == native.notNull &&
  match column.defaultValue, native.defaultValue with
  | none, none => true
  | some written, some text =>
    if defaultKeywords.contains (normalizeIdentifier written.sourceText) then
      normalizeIdentifier written.sourceText == normalizeIdentifier text
    else written.sourceText == text
  | _, _ => false

/-- The explicit indexes of the table at a catalog position, as native metadata,
in folded-name order of the catalog. -/
def catalogIndexes (catalog : Catalog) (position : Nat) : List NativeIndex :=
  catalog.filterMap fun object => match object.entry with
    | .index index => if index.table == position then
        some { name := object.name, columns := index.columns, unique := index.unique } else none
    | .table _ => none

/-- Whether two index lists hold the same indexes, in any order. -/
def sameIndexes (model native : List NativeIndex) : Bool :=
  model.length == native.length && model.all (native.contains ·)

/-- Whether the catalog table at a position, its object name and the model's stored
table match a native table: name, columns, keys, indexes and rows. -/
def tableMatches (catalog : Catalog) (position : Nat) (name : String) (table : CatalogTable)
    (stored : Option Table) (native : NativeTable) : Bool :=
  name == native.name && table.columns.length == native.columns.length &&
  (table.columns.zip native.columns).all (fun (column, observed) => columnMatches column observed) &&
  table.primaryKey == native.primaryKey && sortKeys table.uniqueKeys == sortKeys native.uniqueKeys &&
  sameIndexes (catalogIndexes catalog position) native.indexes &&
  match stored with
  | some model => model.shape == table && sortRows model.rows == sortRows native.rows
  | none => false

/-- Whether the model's tables under a catalog match the native tables: every
catalog table has exactly one native table with its folded name that matches it,
no native table is outside the catalog, and the model stores a table exactly at
the catalog's table positions. -/
def tablesMatch (catalog : Catalog) (model : Tables) (natives : List NativeTable) : Bool :=
  let tables := catalog.zipIdx.filterMap fun (object, position) => match object.entry with
    | .table table => some (position, object.name, table)
    | .index _ => none
  natives.length == tables.length &&
  tables.all (fun (position, name, table) =>
    match natives.filter (fun native => normalizeIdentifier native.name == normalizeIdentifier name) with
    | [native] => tableMatches catalog position name table (model[position]?.join) native
    | _ => false) &&
  model.zipIdx.all (fun (stored, position) => stored.isSome == (catalog.tableAt position).isSome)

end Belay.Sqlite.Conformance
