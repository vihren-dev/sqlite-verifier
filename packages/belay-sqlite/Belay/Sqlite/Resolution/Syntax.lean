import Belay.Sqlite.Resolution.SyntaxExpr
import Belay.Sqlite.Resolution.ConflictAlgorithm

set_option doc.verso true

/-! Statements as written, before name resolution, over the expressions and clauses of
{lit}`SyntaxExpr`. Names are the decoded identifier text, with their case kept; omitted
parts are {lit}`none`. -/

namespace Belay.Sqlite.Syntax

/-- What an {lit}`ON CONFLICT` clause of INSERT does with a row that conflicts. -/
inductive ConflictAction where
  /-- {lit}`DO NOTHING`: skip the row. -/
  | nothing
  /-- {lit}`DO UPDATE SET assignments [WHERE filter]`: update the existing row. -/
  | update (assignments : List (String × Expr)) (filter : Option Expr)
  deriving Repr, DecidableEq

/-- One {lit}`ON CONFLICT [(target)] action` clause of INSERT. The target is a list of
column names as written, or {lean}`(none : Option (List String))` for a clause without
target. -/
structure ConflictClause where
  /-- The target column names, or none. -/
  target : Option (List String)
  /-- The action. -/
  action : ConflictAction
  deriving Repr, DecidableEq

/-- A write that can carry {lit}`RETURNING`: an {lit}`INSERT`, {lit}`UPDATE` or
{lit}`DELETE` with the fields of the statement of the same name. -/
inductive Write where
  /-- {lit}`INSERT [OR algorithm] INTO table [(columns)] VALUES rows [ON CONFLICT ...]`. -/
  | insert (table : String) (columns : Option (List String)) (rows : List (List Expr))
      (conflicts : List ConflictClause) (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`UPDATE table SET assignments [WHERE filter]`. -/
  | update (table : String) (assignments : List (String × Expr)) (filter : Option Expr)
  /-- {lit}`DELETE FROM table [WHERE filter]`. -/
  | delete (table : String) (filter : Option Expr)
  deriving Repr, DecidableEq

/-- One statement as written. For example, {lit}`COMMIT` is
{lean}`Statement.commit`. -/
inductive Statement where
  /-- {lit}`CREATE TABLE name (columns, constraints)`. -/
  | createTable (name : String) (columns : List ColumnDefinition)
      (constraints : List TableConstraint)
  /-- {lit}`CREATE [UNIQUE] INDEX name ON table (columns)`. -/
  | createIndex (name : String) (unique : Bool) (table : String) (columns : List String)
  /-- {lit}`ALTER TABLE table ADD COLUMN column`. -/
  | addColumn (table : String) (column : ColumnDefinition)
  /-- {lit}`BEGIN`. -/
  | begin
  /-- {lit}`COMMIT` or {lit}`END`. -/
  | commit
  /-- {lit}`ROLLBACK`. -/
  | rollback
  /-- {lit}`INSERT INTO table [(columns)] VALUES rows` and its {lit}`ON CONFLICT`
  clauses in written order; a missing column list is
  {lean}`(none : Option (List String))`, and an INSERT without clauses has
  {lean}`([] : List ConflictClause)`. The algorithm of {lit}`INSERT OR algorithm` or of
  {lit}`REPLACE INTO` is {lit}`algorithm`, {lean}`(none : Option ConflictAlgorithm)` without
  one. -/
  | insert (table : String) (columns : Option (List String)) (rows : List (List Expr))
      (conflicts : List ConflictClause) (algorithm : Option ConflictAlgorithm := none)
  /-- {lit}`UPDATE table SET assignments [WHERE filter]`. -/
  | update (table : String) (assignments : List (String × Expr)) (filter : Option Expr)
  /-- {lit}`DELETE FROM table [WHERE filter]`. -/
  | delete (table : String) (filter : Option Expr)
  /-- {lit}`SELECT columns FROM source joins [WHERE filter] [GROUP BY terms] [ORDER BY terms]
  [LIMIT limit [OFFSET offset]]`: the first table of {lit}`FROM` and the joins after it, in
  order; one table has no joins, and a {lit}`SELECT` without {lit}`FROM` has
  {lean}`(none : Option TableReference)` and no joins. An omitted clause is {lit}`none` or
  an empty list;
  {lit}`LIMIT offset, limit` gives both expressions. -/
  | select (columns : List ResultColumn) (source : Option TableReference) (joins : List Join) (filter : Option Expr)
      (groupBy : List Expr) (orderBy : List OrderTerm) (limit : Option Expr) (offset : Option Expr)
  /-- A write with {lit}`RETURNING columns`: an {lit}`INSERT`, {lit}`UPDATE` or
  {lit}`DELETE` and its result columns. A write without {lit}`RETURNING` is the statement
  alone, so its record does not change. -/
  | returning (write : Write) (columns : List ResultColumn)
  deriving Repr, DecidableEq

end Belay.Sqlite.Syntax
