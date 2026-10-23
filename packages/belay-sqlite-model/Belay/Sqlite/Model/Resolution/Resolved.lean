import Belay.Sqlite.Model.Resolution.TriggerProgram
import Belay.Sqlite.Model.Resolution.StatementPrepareError
import Belay.Sqlite.Model.Resolution.ConflictPolicy
import Belay.Sqlite.Model.Resolution.RestrictionText
import Belay.Sqlite.Model.Resolution.QueryForm

set_option doc.verso true

/-! The result of name resolution. A resolved statement refers to catalog
positions instead of names, an INSERT row has one value for each table column, and
literal values are converted. A SQLite prepare error takes the place of the
statement that SQLite refuses to prepare. A model restriction refuses the whole
script: SQLite accepts that SQL, but the model does not describe it. -/

namespace Belay.Sqlite.Model

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

/-- A model restriction inside one statement: the path of the refused node in the
{name}`Syntax.Statement` and the kind. It has no statement index, so the resolution of one
statement does not depend on where the statement is in the script; the resolution of the
script adds the index. For example,
{lean}`({ path := [1], kind := .rowidName } : NodeRestriction)` refuses child 1 of the statement. -/
structure NodeRestriction where
  /-- Child positions from the statement to the refused node; empty for the statement. -/
  path : List Nat
  /-- Which restriction of the registry refuses the SQL. -/
  kind : RestrictionKind
  deriving Repr, DecidableEq

/-- The message of a restriction inside a statement that users read: the message of its kind. -/
def NodeRestriction.reason (restriction : NodeRestriction) : String := restriction.kind.message

/-- The restriction inside a statement as a restriction of the script, at the zero-based
statement index. For example,
{assert}`(({ path := [1], kind := .rowidName } : NodeRestriction).at 2).statement = 2`. -/
def NodeRestriction.at (restriction : NodeRestriction) (statement : Nat) : Restriction :=
  { statement, path := restriction.path, kind := restriction.kind }

namespace Resolved

/-- One statement after name resolution. For example, an INSERT into the table at
catalog position 0 with one full row is {lean}`Statement.insert 0 [[Cell.value Value.null]] []`.
A write names its table by catalog position; execution reads the table's columns, keys
and conflict algorithms from the catalog of the database it runs on. -/
inductive Statement where
  /-- Create the named table at the catalog position, which is the end of the catalog. -/
  | createTable (position : Nat) (name : Identifier) (table : CatalogTable)
  /-- Create the named index at the catalog position, which is the end of the catalog. -/
  | createIndex (position : Nat) (name : Identifier) (index : CatalogIndex)
  /-- Create the named trigger at the catalog position, which is the end of the catalog
  (ADR 0018, D5). -/
  | createTrigger (position : Nat) (name : Identifier) (trigger : CatalogTrigger)
  /-- Append the column to the table at the catalog position. -/
  | addColumn (table : Nat) (column : CatalogColumn)
  /-- Remove the catalog objects at the positions, with their rows ({lit}`Catalog.drop`):
  DROP TABLE removes its table and the indexes on it, DROP INDEX one index, and a DROP
  with {lit}`IF EXISTS` of a missing object none. With {lit}`rules`, DROP TABLE of a table
  that foreign keys reference first deletes its rows with their foreign-key actions, as SQLite
  does (ADR 0018, D4), and the triggers that the actions fire run (D5). -/
  | drop (positions : List Nat) (rules : Option WriteRules := none)
  /-- Start a transaction. -/
  | begin
  /-- Commit the transaction. -/
  | commit
  /-- Roll the transaction back. -/
  | rollback
  /-- Insert full rows, with one cell for each column in table order ({name}`Cell`), and
  keep every unique key of the table ({name}`Catalog.uniqueKeys`) unique. The
  {lit}`RETURNING` columns are an expression over the written row and its name each,
  none without {lit}`RETURNING`; the execution semantics does not read them. The
  subqueries are those that the cells name by index (ADR 0018, D1), as for a query. With
  foreign keys on and a key that the write must check, or with a trigger that it may fire,
  {lit}`rules` are what it runs row by row ({name}`WriteRules`); they are none without either
  (ADR 0018, D4 and D5). -/
  | insert (table : Nat) (rows : List (List Cell)) (returning : List (Expr × String))
      (subqueries : List Query := []) (rules : Option WriteRules := none)
  /-- In every row where the optional filter condition is true (every row without a
  filter), set each column position to its expression, evaluated on the old row and
  stored with the column's affinity. A literal update of slice 3a is the special case
  of {lit}`.literal` values and the filter {lit}`column = integer`. The unique keys and
  the {lit}`RETURNING` columns, the subqueries and {lit}`rules` are as for INSERT. -/
  | update (table : Nat) (assignments : List (Nat × Expr)) (filter : Option Expr)
      (returning : List (Expr × String)) (subqueries : List Query := []) (rules : Option WriteRules := none)
  /-- INSERT with {lit}`ON CONFLICT` clauses or a conflict algorithm other than ABORT: the
  rows as for {name}`Statement.insert`, the clauses in written order, and the statement's
  {lit}`OR` algorithm, if any. The algorithm of each constraint is
  {name}`Catalog.writePolicy` of that algorithm. Each row is handled by the first clause
  whose target key has a conflicting row, or else by the algorithms of the constraints
  that it fails. The subqueries and {lit}`rules` are as for INSERT. -/
  | upsert (table : Nat) (rows : List (List Cell)) (clauses : List ConflictClause)
      (returning : List (Expr × String)) (algorithm : Option ConflictAlgorithm)
      (subqueries : List Query := []) (rules : Option WriteRules := none)
  /-- Remove every row where the optional filter condition is true (every row without a
  filter). The {lit}`RETURNING` columns are evaluated on each removed row; the
  execution semantics does not read them. The subqueries and {lit}`rules` are as for
  INSERT. -/
  | delete (table : Nat) (filter : Option Expr) (returning : List (Expr × String))
      (subqueries : List Query := []) (rules : Option WriteRules := none)
  /-- SQLite refuses to prepare the statement with this error. -/
  | prepareError (error : PrepareError)
  /-- Run a query: it reads the database, changes nothing, and has result rows. The
  subqueries are those that its expressions name by index (ADR 0018, D1); a subquery's
  expressions name only subqueries after it in the list. -/
  | query (query : Query) (subqueries : List Query)
  /-- {lit}`PRAGMA setting = value`, with the value of the setting after it. For
  {lit}`foreign_keys`, the value is the new value outside a transaction, and the value before
  it inside one, where SQLite ignores the pragma (ADR 0018, D4); {lit}`recursive_triggers`
  takes the new value also inside a transaction (ADR 0019, D2). It changes no table, gives no
  row and never fails; resolution follows the setting. -/
  | setting (setting : Syntax.PragmaSetting) (on : Bool)
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

end Belay.Sqlite.Model
