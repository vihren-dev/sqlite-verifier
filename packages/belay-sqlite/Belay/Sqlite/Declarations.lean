set_option doc.verso true

/-! Structural declarations retained by the ordinary-table backend. Constraint
truth is preserved through unchanged projections, not a fabricated SQL comparator. -/

namespace Belay.Sqlite

/-- SQLite column affinities. Supply the affinity of the declared column type;
{lean}`Affinity.integer` describes INTEGER affinity. -/
inductive Affinity where
  /-- INTEGER affinity, for example an INTEGER declaration. -/
  | integer
  /-- REAL affinity, for example a REAL declaration. -/
  | real
  /-- TEXT affinity, for example a TEXT declaration. -/
  | text
  /-- BLOB affinity, including a column with no declared type. -/
  | blob
  /-- NUMERIC affinity, for example a NUMERIC declaration. -/
  | numeric
  deriving Repr, DecidableEq

/-- Type spelling retained separately from {name}`Affinity`. Use
{lean}`DeclaredType.canonical` for the canonical spelling of an affinity.
The spelling determines whether a primary-key column can alias the physical
rowid: INTEGER can do so, while BIGINT cannot. -/
inductive DeclaredType where
  /-- Canonical spelling selected by the column's affinity. -/
  | canonical
  /-- BIGINT spelling, whose admitted affinity is INTEGER. -/
  | bigInt
  /-- TIMESTAMP spelling, whose admitted affinity is NUMERIC. -/
  | timestamp
  /-- BOOLEAN spelling, whose admitted affinity is NUMERIC. -/
  | boolean
  /-- No declared type, whose admitted affinity is BLOB. -/
  | untyped
  deriving Repr, DecidableEq

/-- Default syntax retained on existing columns. The model records
{lean}`ColumnDefault.currentTimestamp` without evaluating it. -/
inductive ColumnDefault where
  /-- The existing column has a {lit}`CURRENT_TIMESTAMP` default. -/
  | currentTimestamp
  deriving Repr, DecidableEq

/-- A column's identifier, affinity, type spelling and constraints. For a plain
column, supply its name and affinity; the remaining fields have plain defaults. -/
structure Column where
  /-- Decoded identifier, for example {lean}`"id"`. -/
  name : String
  /-- Declared affinity, for example {lean}`Affinity.integer`. -/
  affinity : Affinity
  /-- Retained type spelling; omit it to use {lean}`DeclaredType.canonical`. -/
  declaredType : DeclaredType := .canonical
  /-- Whether the column declares NOT NULL; omit it for a nullable column. -/
  notNull : Bool := false
  /-- Retained default syntax; omit it when the column has no default. -/
  defaultValue : Option ColumnDefault := none
  deriving Repr, DecidableEq

/-- An explicit index on named columns in key order. Supply a name and column
list; omit {name}`IndexDefinition.unique` for a nonunique index. -/
structure IndexDefinition where
  /-- Decoded index identifier, for example {lean}`"by_id"`. -/
  name : String
  /-- Column identifiers in index order, for example {lean}`["id"]`. -/
  columns : List String
  /-- Whether the index requires unique keys; the default is nonunique. -/
  unique : Bool := false
  deriving Repr, DecidableEq

/-- Retained keys and explicit indexes of one table. Use {lean}`TableProperties.mk [] [] []`
when the table has no such properties. -/
structure TableProperties where
  /-- Primary-key columns in order; {lean}`([] : List String)` means no primary key. -/
  primaryKey : List String := []
  /-- Ordered column lists of UNIQUE constraints; omit it when there are none. -/
  uniqueKeys : List (List String) := []
  /-- Explicit index declarations; omit it when there are none. -/
  indexes : List IndexDefinition := []
  deriving Repr, DecidableEq

/-- Collect primary-key columns when nonempty, all UNIQUE constraints and the
columns of unique indexes, in that order. Nonunique indexes contribute no key;
{lean}`TableProperties.keys {}` is the empty list. -/
def TableProperties.keys (properties : TableProperties) : List (List String) :=
  (if properties.primaryKey.isEmpty then [] else [properties.primaryKey]) ++
    properties.uniqueKeys ++
    (properties.indexes.filter IndexDefinition.unique).map IndexDefinition.columns

/-- Check the retained spelling against its admitted affinity. Canonical spelling
accepts every affinity; BIGINT requires INTEGER, TIMESTAMP and BOOLEAN require
NUMERIC, and an untyped column requires BLOB. -/
def declaredTypeMatches (column : Column) : Bool :=
  match column.declaredType with
  | .canonical => true
  | .bigInt => column.affinity == .integer
  | .timestamp | .boolean => column.affinity == .numeric
  | .untyped => column.affinity == .blob

/-- Test only whether the spelling is canonical, NOT NULL is absent and no
default is present. This does not validate the name or affinity. A column that
uses the optional field defaults is plain. The restricted CREATE TABLE and
ADD COLUMN operations require plain columns, so they need no new NOT NULL,
default-expression or alias-spelling semantics. -/
def Column.plain (column : Column) : Bool :=
  column.declaredType == .canonical && !column.notNull && column.defaultValue.isNone

/-!
A plain integer column uses the field defaults:
{lean}`({ name := "id", affinity := .integer } : Column)`.
{assert}`Column.plain { name := "id", affinity := .integer } = true`.

An existing BIGINT declaration retains its spelling:
{lean}`({ name := "id", affinity := .integer, declaredType := .bigInt } : Column)`.
{assert}`declaredTypeMatches { name := "id", affinity := .integer, declaredType := .bigInt } = true`.
{assert}`Column.plain { name := "id", affinity := .integer, declaredType := .bigInt } = false`.
-/

end Belay.Sqlite
