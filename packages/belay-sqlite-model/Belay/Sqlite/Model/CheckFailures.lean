import Belay.Sqlite.Model.LiteralData
import Belay.Sqlite.Model.Resolution.ConflictPolicy

set_option doc.verso true

/-! The failures that {lit}`PRAGMA integrity_check` and {lit}`PRAGMA quick_check` report (ADR
0019, D2), with SQLite's text of each ({lit}`pragma.c` of SQLite 3.51.0), and the unique
indexes of a table that {lit}`integrity_check` checks, in SQLite's order. The rows of the
pragmas are in {lit}`IntegrityCheck`. -/

namespace Belay.Sqlite.Model

/-- One failure that a check pragma reports, with the names as declared. For example, a NULL
in the NOT NULL column {lit}`a` of table {lit}`t` is
{lean}`CheckFailure.null (name! "t") (name! "a")`. -/
inductive CheckFailure where
  /-- A row of a {lit}`WITHOUT ROWID` table whose primary key equals that of an earlier row:
  {lit}`row not in PRIMARY KEY order for t`. -/
  | order (table : Identifier)
  /-- A NULL in a NOT NULL column: {lit}`NULL value in t.a`. -/
  | null (table column : Identifier)
  /-- A cell that does not fit the type of its {lit}`STRICT` column:
  {lit}`non-INTEGER value in t.a`. -/
  | type (table column : Identifier) (type : StrictType)
  /-- A row for which a CHECK constraint is false: {lit}`CHECK constraint failed in t`. -/
  | check (table : Identifier)
  /-- A row whose entry in a unique index has an equal key to the next entry of the index:
  {lit}`non-unique entry in index i`. -/
  | unique (index : Identifier)
  deriving Repr, DecidableEq

/-- SQLite's text of the failure, as the bytes of the row that the pragma gives. For example
the text of {lean}`CheckFailure.check (name! "t")` is {lit}`CHECK constraint failed in t`. -/
def CheckFailure.text : CheckFailure → List UInt8
  | .order table => bytes! "row not in PRIMARY KEY order for " ++ table.bytes
  | .null table column => bytes! "NULL value in " ++ table.bytes ++ [46] ++ column.bytes
  | .type table column strict =>
    bytes! "non-" ++ strict.name.toUTF8.toList ++ bytes! " value in " ++ table.bytes ++ [46] ++ column.bytes
  | .check table => bytes! "CHECK constraint failed in " ++ table.bytes
  | .unique index => bytes! "non-unique entry in index " ++ index.bytes

/-- The text of the row of a check pragma without failures. -/
def checkOk : List UInt8 := bytes! "ok"

/-- For every failure, its text is not the text {lit}`ok` ({name}`checkOk`), so the row
{lit}`ok` means that no check failed. Proof sketch: each text starts with a byte other than
{lit}`o`. -/
theorem CheckFailure.text_ne_ok (failure : CheckFailure) : failure.text ≠ checkOk := by
  cases failure <;> simp [CheckFailure.text, checkOk]

/-- A unique index of a table as {lit}`integrity_check` checks it: its name as declared, its
key, whether it is a {lit}`REPLACE` index, which SQLite keeps at the end of its list, and the
order of its entries with equal keys. -/
structure CheckedIndex where
  /-- The name of the index; {lit}`sqlite_autoindex_t_N` for the index of a constraint. -/
  name : Identifier
  /-- The key of the index. -/
  key : UniqueKey
  /-- Whether the index is the index of a constraint with {lit}`ON CONFLICT REPLACE`. -/
  replace : Bool
  /-- Whether SQLite orders the entries with equal keys by the primary key in ascending order,
  against the scan order of the table: the index of a constraint of a {lit}`WITHOUT ROWID`
  table with {lit}`PRIMARY KEY DESC` ({lit}`bAscKeyBug` in {lit}`build.c`). When it is false,
  the entries with equal keys are in scan order. -/
  ascendingTies : Bool
  deriving Repr, DecidableEq

/-- The name that SQLite gives to the index number {lit}`number` of a constraint of table
{lit}`table`: {lit}`sqlite_autoindex_t_1` for the first one. -/
def autoindexName (table : Identifier) (number : Nat) : Identifier :=
  ⟨bytes! "sqlite_autoindex_" ++ table.bytes ++ [95] ++ (toString number).toUTF8.toList⟩

/-- Whether SQLite keeps an index for the primary key of the table: the table has a primary
key that is not its rowid alias. -/
def CatalogTable.primaryIndexed (table : CatalogTable) : Bool :=
  !table.primaryKey.isEmpty && !(table.rowidAlias.isSome && table.primaryKey == table.rowidAlias.toList)

/-- The keys of the indexes of the constraints of the table in the order in which SQLite
creates them, each with whether it is a {lit}`REPLACE` index and whether it is the primary
key: the UNIQUE keys, with the primary key after the first
{name}`CatalogTable.uniqueBeforePrimary` of them when it has an index
({name}`CatalogTable.primaryIndexed`). -/
def CatalogTable.constraintKeys (table : CatalogTable) : List (List Nat × Bool × Bool) :=
  let uniques := table.uniqueKeys.zipIdx.map fun (positions, index) =>
    (positions, table.uniqueAlgorithm index == some .replace, false)
  if table.primaryIndexed then
    uniques.take table.uniqueBeforePrimary ++ [(table.primaryKey, table.primaryKeyAlgorithm == some .replace, true)] ++
      uniques.drop table.uniqueBeforePrimary
  else uniques

/-- The indexes of the constraints of the table with the name, in the order of
{name}`CatalogTable.constraintKeys`, numbered from 1 ({name}`autoindexName`). The primary key of a
{lit}`WITHOUT ROWID` table is not among them: {lit}`integrity_check` checks the order of its rows
instead. In a {lit}`WITHOUT ROWID` table with {lit}`PRIMARY KEY DESC`, SQLite appends the primary
key to these indexes in ascending order ({name}`CheckedIndex.ascendingTies`). -/
def CatalogTable.constraintIndexes (name : Identifier) (table : CatalogTable) : List CheckedIndex :=
  table.constraintKeys.zipIdx.filterMap fun ((positions, replace, primary), number) =>
    if primary && table.withoutRowid then none
    else some { name := autoindexName name (number + 1), key := UniqueKey.ofColumns table.columns positions,
                replace := replace, ascendingTies := table.withoutRowid && table.primaryKeyDescending }

/-- The unique indexes of {lit}`CREATE UNIQUE INDEX` on the table at the catalog position, in
catalog order, with their names. SQLite appends the primary key of a {lit}`WITHOUT ROWID` table
to them in the order of the table, so their entries with equal keys are in scan order. -/
def Catalog.declaredIndexes (catalog : Catalog) (position : Nat) : List CheckedIndex :=
  catalog.filterMap fun object => match object.entry with
    | .index index =>
      if index.table == position && index.unique then
        some { name := object.name, key := index.uniqueKey, replace := false, ascendingTies := false }
      else none
    | .table _ | .trigger _ => none

/-- The unique indexes that {lit}`integrity_check` checks for the table at the catalog position
with the name, in SQLite's order ({lit}`pTab->pIndex`): newest first, so the indexes of
{lit}`CREATE UNIQUE INDEX` ({name}`Catalog.declaredIndexes`) in reverse catalog order before the
indexes of the constraints ({name}`CatalogTable.constraintIndexes`) in reverse order, and then
the {lit}`REPLACE` indexes moved to the end. -/
def Catalog.checkedIndexes (catalog : Catalog) (position : Nat) (name : Identifier) (table : CatalogTable) :
    List CheckedIndex :=
  let newest := (table.constraintIndexes name ++ catalog.declaredIndexes position).reverse
  newest.filter (!·.replace) ++ newest.filter (·.replace)

end Belay.Sqlite.Model
