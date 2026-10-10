import Belay.Sqlite.Catalog

set_option doc.verso true

/-! The result of name resolution. A resolved statement refers to catalog
positions instead of names, an INSERT row has one value for each table column, and
literal values are converted. A SQLite prepare error takes the place of the
statement that SQLite refuses to prepare. A model restriction refuses the whole
script: SQLite accepts that SQL, but the model does not describe it. -/

namespace Belay.Sqlite

/-- An error that {lit}`sqlite3_prepare_v2` reports for a statement in the first
scope. Each constructor names the SQLite message format it corresponds to. This
is a SQLite rule, not a model restriction: SQLite runs the earlier statements and
then stops at this one. -/
inductive PrepareError where
  /-- {lit}`object name reserved for internal use: %s` ({lit}`sqlite3CheckObjectName`). -/
  | reservedName (name : String)
  /-- {lit}`table %T already exists` ({lit}`sqlite3StartTable`). -/
  | tableExists (name : String)
  /-- {lit}`there is already an index named %s` ({lit}`sqlite3StartTable`). -/
  | indexNameUsed (name : String)
  /-- {lit}`there is already a table named %s` ({lit}`sqlite3CreateIndex`). -/
  | tableNameUsed (name : String)
  /-- {lit}`index %s already exists` ({lit}`sqlite3CreateIndex`). -/
  | indexExists (name : String)
  /-- {lit}`too many columns on %s` ({lit}`sqlite3AddColumn`). -/
  | tooManyColumns (table : String)
  /-- {lit}`duplicate column name: %s` ({lit}`sqlite3AddColumn`). -/
  | duplicateColumn (column : String)
  /-- {lit}`table "%s" has more than one primary key` ({lit}`sqlite3AddPrimaryKey`). -/
  | multiplePrimaryKeys (table : String)
  /-- {lit}`default value of column [%s] is not constant` ({lit}`sqlite3AddDefaultValue`). -/
  | defaultNotConstant (column : String)
  /-- {lit}`no such table: %s` ({lit}`sqlite3LocateTable`). -/
  | noSuchTable (name : String)
  /-- {lit}`no such column: %s` (name resolution of an expression or key). -/
  | noSuchColumn (name : String)
  /-- {lit}`table %S has no column named %s` (INSERT column list). -/
  | tableHasNoColumn (table column : String)
  /-- {lit}`table %S has %d columns but %d values were supplied` (INSERT). -/
  | valueCount (table : String) (columns values : Nat)
  /-- {lit}`%d values for %d columns` (INSERT with a column list). -/
  | valuesForColumns (values columns : Nat)
  /-- {lit}`all VALUES must have the same number of terms` ({lit}`sqlite3MultiValues`). -/
  | valuesDiffer
  /-- {lit}`table %s may not be altered` ({lit}`isAlterableTable`). -/
  | tableMayNotBeAltered (name : String)
  /-- {lit}`table %s may not be indexed` ({lit}`sqlite3CreateIndex`). -/
  | tableMayNotBeIndexed (name : String)
  /-- {lit}`Cannot add a PRIMARY KEY column` ({lit}`sqlite3AlterFinishAddColumn`). -/
  | cannotAddPrimaryKey
  /-- {lit}`Cannot add a UNIQUE column` ({lit}`sqlite3AlterFinishAddColumn`). -/
  | cannotAddUnique
  /-- {lit}`hex literal too big: %s` (a hexadecimal literal with more than 16 digits). -/
  | hexLiteralTooBig (text : String)
  deriving Repr, DecidableEq

/-- A model restriction: SQLite accepts the SQL, but the model does not describe
it, so the whole script is refused before any proof. The statement index and the
path of the node in the {name}`Syntax.Statement` locate the SQL for diagnostics. -/
structure Restriction where
  /-- The zero-based statement index. -/
  statement : Nat
  /-- Child positions from the statement to the refused node; empty for the statement. -/
  path : List Nat
  /-- Why the model does not describe the SQL. -/
  reason : String
  deriving Repr, DecidableEq

namespace Resolved

/-- One statement after name resolution. For example, an INSERT into the table at
catalog position 0 with one full row is {lean}`Statement.insert 0 [[Value.null]]`. -/
inductive Statement where
  /-- Create the named table; its catalog position is the end of the catalog. -/
  | createTable (name : String) (table : CatalogTable)
  /-- Create the named index; its catalog position is the end of the catalog. -/
  | createIndex (name : String) (index : CatalogIndex)
  /-- Append the column to the table at the catalog position. -/
  | addColumn (table : Nat) (column : CatalogColumn)
  /-- Start a transaction. -/
  | begin
  /-- Commit the transaction. -/
  | commit
  /-- Roll the transaction back. -/
  | rollback
  /-- Insert full rows, with one converted value for each column in table order. -/
  | insert (table : Nat) (rows : List (List Value))
  /-- Set each column position to its value in the rows where the optional filter
  column equals the filter value; with no filter, in every row. -/
  | update (table : Nat) (assignments : List (Nat × Value)) (filter : Option (Nat × Value))
  /-- SQLite refuses to prepare the statement with this error. -/
  | prepareError (error : PrepareError)
  deriving Repr, DecidableEq

end Resolved

/-- The result of resolving a script: the resolved statements and the catalog after
all of them succeed, or a model restriction. -/
inductive ResolveResult where
  /-- Every statement resolved; a statement that SQLite refuses is a prepare error. -/
  | resolved (statements : List Resolved.Statement) (catalog : Catalog)
  /-- The model does not describe the script. -/
  | restricted (restriction : Restriction)
  deriving Repr, DecidableEq

end Belay.Sqlite
