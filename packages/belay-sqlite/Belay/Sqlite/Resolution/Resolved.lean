import Belay.Sqlite.Resolution.Catalog
import Belay.Sqlite.Resolution.ConflictForm
import Belay.Sqlite.Resolution.RestrictionText

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
  /-- {lit}`misuse of aggregate function %s()` (an aggregate in {lit}`WHERE`, or one
  aggregate inside another; {lit}`resolveSelectStep`). -/
  | misuseOfAggregate (function : String)
  /-- {lit}`aggregate functions are not allowed in the GROUP BY clause`. -/
  | aggregateInGroupBy
  /-- {lit}`%r ORDER BY term out of range - should be between 1 and %d`: the one-based
  term and the number of result columns ({lit}`resolveOrderGroupBy`). -/
  | orderByOutOfRange (term columns : Nat)
  /-- {lit}`%r GROUP BY term out of range - should be between 1 and %d`. -/
  | groupByOutOfRange (term columns : Nat)
  /-- {lit}`wrong number of arguments to function %s()`, with the function name as
  written ({lit}`resolveExprStep`). -/
  | wrongArgumentCount (function : String)
  /-- {lit}`ambiguous column name: %s`: an unqualified name that names a column of two or
  more sources of a join, as written. -/
  | ambiguousColumn (name : String)
  /-- {lit}`no such table: %s` for {lit}`source.*` with a name that names no source of
  the query, as written. Unlike {name}`PrepareError.noSuchTable`, it names no catalog
  object. -/
  | noSuchSource (name : String)
  /-- {lit}`at most 64 tables in a join`. -/
  | tooManyTables
  /-- {lit}`RETURNING may not use "TABLE.*" wildcards`: a {lit}`source.*` column in
  {lit}`RETURNING`, for every source name. -/
  | returningSourceStar
  /-- {lit}`cannot join using column %s - column not present in both tables`: a name of
  {lit}`USING` that is not a column of both the left input and the joined table, as
  written. -/
  | joinUsingColumn (name : String)
  /-- {lit}`a NATURAL join may not have an ON or USING clause`. -/
  | naturalJoinCondition
  /-- {lit}`ambiguous reference to %s in USING()`: in a {lit}`FROM` with a right or full
  join, a merged name of which a left table after the first has a column that its own
  join does not merge, as written. -/
  | ambiguousUsingReference (name : String)
  /-- {lit}`ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint`: a
  target whose columns are not the columns of one key of the table. -/
  | conflictTargetMismatch
  /-- {lit}`conflicting ON CONFLICT clauses specified`: two constraints of one index with
  different explicit {lit}`ON CONFLICT` algorithms. -/
  | conflictingAlgorithms
  deriving Repr, DecidableEq

/-- A model restriction: SQLite accepts the SQL, but the model does not describe
it, so the whole script is refused before any proof. The statement index and the
path of the node in the {name}`Syntax.Statement` locate the SQL for diagnostics. -/
structure Restriction where
  /-- The zero-based statement index. -/
  statement : Nat
  /-- Child positions from the statement to the refused node; empty for the statement. -/
  path : List Nat
  /-- Which restriction of the registry refuses the SQL. -/
  kind : RestrictionKind
  deriving Repr, DecidableEq

/-- The message of a restriction that users read: the message of its kind. -/
def Restriction.reason (restriction : Restriction) : String := restriction.kind.message

namespace Resolved

/-- One statement after name resolution. For example, an INSERT into the table at
catalog position 0 with one full row and no unique keys is
{lean}`Statement.insert 0 [[Value.null]] [] []`. -/
inductive Statement where
  /-- Create the named table at the catalog position, which is the end of the catalog. -/
  | createTable (position : Nat) (name : String) (table : CatalogTable)
  /-- Create the named index at the catalog position, which is the end of the catalog. -/
  | createIndex (position : Nat) (name : String) (index : CatalogIndex)
  /-- Append the column to the table at the catalog position. -/
  | addColumn (table : Nat) (column : CatalogColumn)
  /-- Start a transaction. -/
  | begin
  /-- Commit the transaction. -/
  | commit
  /-- Roll the transaction back. -/
  | rollback
  /-- Insert full rows, with one converted value for each column in table order.
  {name}`Statement.insert` also carries the column positions of each unique key of
  the table, which the statement must keep unique, and its {lit}`RETURNING` columns:
  an expression over the written row and its name each, none without
  {lit}`RETURNING`. The execution semantics does not read them. -/
  | insert (table : Nat) (rows : List (List Value)) (keys : List (List Nat)) (returning : List (Expr × String))
  /-- In every row where the optional filter condition is true (every row without a
  filter), set each column position to its expression, evaluated on the old row and
  stored with the column's affinity. A literal update of slice 3a is the special case
  of {lit}`.literal` values and the filter {lit}`column = integer`. The unique keys and
  the {lit}`RETURNING` columns are as for INSERT. -/
  | update (table : Nat) (assignments : List (Nat × Expr)) (filter : Option Expr)
      (keys : List (List Nat)) (returning : List (Expr × String))
  /-- INSERT with {lit}`ON CONFLICT` clauses or a conflict algorithm other than ABORT: the
  rows and the keys as for {name}`Statement.insert`, the clauses in written order, and the
  algorithm of each constraint. Each row is handled by the first clause whose target key
  has a conflicting row, or else by the algorithms of the constraints that it fails. -/
  | upsert (table : Nat) (rows : List (List Value)) (clauses : List ConflictClause)
      (keys : List (List Nat)) (returning : List (Expr × String)) (policy : ConflictPolicy)
  /-- Remove every row where the optional filter condition is true (every row without a
  filter). The {lit}`RETURNING` columns are evaluated on each removed row; the
  execution semantics does not read them. -/
  | delete (table : Nat) (filter : Option Expr) (returning : List (Expr × String))
  /-- SQLite refuses to prepare the statement with this error. -/
  | prepareError (error : PrepareError)
  /-- Run a query: it reads the database, changes nothing, and has result rows. -/
  | query (query : Query)
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
