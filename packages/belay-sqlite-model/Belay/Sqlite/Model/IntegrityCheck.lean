import Belay.Sqlite.Model.CheckFailures
import Belay.Sqlite.Model.QueryEval
import Belay.Sqlite.Model.TableBlocks

set_option doc.verso true

/-! The rows of {lit}`PRAGMA integrity_check` and {lit}`PRAGMA quick_check` (ADR 0019, D2), as
SQLite 3.51.0 gives them ({lit}`pragma.c`, the loop over the rows of each table). The checks
use the row predicates of the writes ({lit}`LiteralData`), so the laws in
{lit}`IntegrityCheckLaws` can show that no failure means the facts of a valid database. -/

namespace Belay.Sqlite.Model

/-- Whether a key term is a column with NOT NULL in the columns; an expression is not. -/
def termNotNull (columns : List CatalogColumn) : KeyTerm → Bool
  | .column position => columns[position]?.any (·.notNull)
  | .expression _ => false

/-- Whether the index entry of the row has a NULL that makes it unique for SQLite: a term
whose value is NULL, except a column with NOT NULL. -/
def entryHasNull (columns : List CatalogColumn) (key : UniqueKey) (row : Row) : Bool :=
  key.terms.any fun term => !termNotNull columns term.term && LiteralData.termValue row term.term == some .null

/-- Whether two key cells are equal in an index: both NULL, or neither NULL and equal under
the collation ({name}`Collation.compare`). -/
def entryCellsEqual (collation : Collation) (first second : Value) : Bool :=
  if first == .null || second == .null then first == .null && second == .null
  else collation.compare first second == .eq

/-- Whether the index entry of the first row conflicts with that of the second row for
{lit}`integrity_check`: the key applies to both ({name}`LiteralData.keyApplies`), the entry of
the first row has no NULL that makes it unique ({name}`entryHasNull`), and each term is equal
({name}`entryCellsEqual`). A missing cell is never equal. -/
def entryConflict (columns : List CatalogColumn) (key : UniqueKey) (first second : Row) : Bool :=
  LiteralData.keyApplies key first && LiteralData.keyApplies key second && !entryHasNull columns key first &&
    key.terms.all fun term => match LiteralData.termValue first term.term, LiteralData.termValue second term.term with
      | some a, some b => entryCellsEqual term.collation a b
      | _, _ => false

/-- Whether SQLite skips the order check of a row of a {lit}`WITHOUT ROWID` table with the key:
the key has no term, or the first key cell is NULL, which SQLite reads as the start of the scan. -/
def orderSkipped (key : UniqueKey) (row : Row) : Bool :=
  match key.terms with
  | [] => true
  | term :: _ => LiteralData.termValue row term.term == some .null

/-- The failure of one cell of a row of table {lit}`table`, if any: a NULL in a NOT NULL column
({name}`CheckFailure.null`), else a cell that does not fit the column's {lit}`STRICT` type
({name}`StrictType.fits`, {name}`CheckFailure.type`). -/
def columnFailure (table : Identifier) (column : CatalogColumn) (value : Value) : Option CheckFailure :=
  if column.notNull && value == .null then some (.null table column.name)
  else match column.strictType with
    | some type => if type.fits value then none else some (.type table column.name type)
    | none => none

/-- Whether integrity checking finds the later row {lit}`row` out of key order after the
earlier row {lit}`earlier`: without {lit}`quick`, in a {lit}`WITHOUT ROWID` table, unless
{name}`orderSkipped`, the primary keys conflict ({name}`entryConflict`). -/
def Table.orderConflict (quick : Bool) (table : Table) (earlier row : Row) : Bool :=
  let primary := UniqueKey.ofColumns table.shape.columns table.shape.primaryKey
  !quick && table.shape.withoutRowid && !orderSkipped primary row && entryConflict table.shape.columns primary earlier row

/-- The order failure of a row of table {lit}`name` after the rows {lit}`earlier`:
{name}`CheckFailure.order` when an earlier row has a primary key that conflicts
({name}`Table.orderConflict`). In key order the row before it is such a row. -/
def Table.orderFailures (quick : Bool) (name : Identifier) (table : Table) (earlier : List Row) (row : Row) :
    List CheckFailure :=
  if earlier.any (table.orderConflict quick · row) then [.order name] else []

/-- The failures of the cells of a row of table {lit}`name`: {name}`columnFailure` of each cell,
in column order, then {name}`CheckFailure.check` when a CHECK constraint is false
({name}`LiteralData.checksHold`). -/
def Table.cellFailures (name : Identifier) (table : Table) (row : Row) : List CheckFailure :=
  (table.shape.columns.zip row.values).filterMap (fun (column, value) => columnFailure name column value) ++
    if LiteralData.checksHold table.shape row then [] else [.check name]

/-- Whether integrity checking finds the entries of the two rows in the index with equal keys:
without {lit}`quick`, the entry of {lit}`row` conflicts with that of {lit}`other`
({name}`entryConflict`). -/
def Table.indexConflict (quick : Bool) (table : Table) (checked : CheckedIndex) (row other : Row) : Bool :=
  !quick && entryConflict table.shape.columns checked.key row other

/-- The comparison of the primary keys of two rows in ascending order under the collations of
the key columns ({name}`Resolved.compareSort` of {name}`Belay.Sqlite.Model.Table.keyCells`). -/
def Table.ascendingKeyOrder (table : Table) (row other : Row) : Ordering :=
  let directions := table.shape.primaryKey.map fun position =>
    (false, (table.shape.columns[position]?.map (·.collation)).getD .binary)
  Resolved.compareSort directions (table.keyCells row) (table.keyCells other)

/-- Whether, among entries with equal keys in the index, the entry of the row {lit}`other` comes
after the entry of the row {lit}`row`; {lit}`otherLater` tells whether {lit}`other` comes later
in the scan. With {name}`CheckedIndex.ascendingTies`, it does when its primary key is greater in
ascending order ({name}`Table.ascendingKeyOrder`), or equal and later in the scan. Otherwise the
entries are in scan order. -/
def Table.entryFollows (table : Table) (checked : CheckedIndex) (row other : Row) (otherLater : Bool) : Bool :=
  if checked.ascendingTies then
    match table.ascendingKeyOrder row other with
    | .lt => true
    | .eq => otherLater
    | .gt => false
  else otherLater

/-- Whether integrity checking finds the entry of the row in the index followed by an entry
with an equal key, of the row {lit}`other`: the entry of {lit}`other` comes after it
({name}`Table.entryFollows`) and the entries conflict ({name}`Table.indexConflict`). -/
def Table.entryDuplicated (quick : Bool) (table : Table) (checked : CheckedIndex) (row other : Row)
    (otherLater : Bool) : Bool :=
  table.entryFollows checked row other otherLater && table.indexConflict quick checked row other

/-- The index failures of a row after the rows {lit}`earlier` and before the rows {lit}`later`
in the scan: {name}`CheckFailure.unique` for each index in order in which the entry of the row
is followed by an entry with an equal key ({name}`Table.entryDuplicated`). -/
def Table.uniqueFailures (quick : Bool) (indexes : List CheckedIndex) (table : Table) (earlier : List Row)
    (row : Row) (later : List Row) : List CheckFailure :=
  (indexes.filter fun checked => earlier.any (table.entryDuplicated quick checked row · false) ||
    later.any (table.entryDuplicated quick checked row · true)).map (.unique ·.name)

/-- The failures of the rows {lit}`rows` in scan order after the rows {lit}`earlier`, in
SQLite's order: for each row, {name}`Table.orderFailures`, {name}`Table.cellFailures` and
{name}`Table.uniqueFailures`. -/
def Table.failuresFrom (quick : Bool) (name : Identifier) (indexes : List CheckedIndex) (table : Table) :
    List Row → List Row → List CheckFailure
  | _, [] => []
  | earlier, row :: later =>
    table.orderFailures quick name earlier row ++ table.cellFailures name row ++
      table.uniqueFailures quick indexes earlier row later ++ table.failuresFrom quick name indexes (row :: earlier) later

/-- The failures of the table with the name and its checked indexes, row by row in scan order
({name}`Table.scanRows`, {name}`Table.failuresFrom`). -/
def Table.checkFailures (quick : Bool) (name : Identifier) (indexes : List CheckedIndex) (table : Table) :
    List CheckFailure :=
  table.failuresFrom quick name indexes [] table.scanRows

/-- The failures of the table at the catalog position, with its name and the indexes of
{name}`Catalog.checkedIndexes`. -/
def Database.tableFailures (database : Database) (quick : Bool) (position : Nat) (table : Table) : List CheckFailure :=
  let name := (database.catalog[position]?.map (·.name)).getD default
  table.checkFailures quick name (database.catalog.checkedIndexes position name table.shape)

/-- The row limit of a check pragma: 100 for 0, as SQLite reads a limit of 0 or none. -/
def checkLimit (limit : Nat) : Nat := if limit == 0 then 100 else limit

/-- The rows of a check pragma over the database for the tables of
{name}`Database.checkPositions`, with the failures of each failing table ({name}`Database.blocks`
of {name}`Database.tableFailures`):

* the one row {lit}`ok` ({name}`checkOk`) when no table fails;
* the text of each failure of the one table that fails, at most {name}`checkLimit` of them;
* {lean}`(none : Option (List (List Value)))` when two or more tables fail, because SQLite
  checks the tables in the order of its schema hash table, which the model does not
  describe. -/
def Database.checkRows (database : Database) (quick : Bool) (limit : Nat) (table : Option Nat) :
    Option (List (List Value)) :=
  match database.blocks (database.checkPositions table) (database.tableFailures quick) with
  | [] => some [[.text checkOk]]
  | [failures] => some ((failures.take (checkLimit limit)).map fun failure => [.text failure.text])
  | _ :: _ :: _ => none

end Belay.Sqlite.Model
