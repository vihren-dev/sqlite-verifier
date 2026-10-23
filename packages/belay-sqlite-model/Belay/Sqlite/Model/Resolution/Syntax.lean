import Belay.Sqlite.Model.Resolution.SyntaxDefinitions
import Belay.Sqlite.Model.Resolution.ConflictAlgorithm
import Belay.Sqlite.Model.Resolution.SyntaxEquality

set_option doc.verso true

/-! Statements as written, before name resolution, over the expressions and clauses of
{lit}`SyntaxExpr`. Names are the decoded identifier text, with their case kept; omitted
parts are {lit}`none`. -/

namespace Belay.Sqlite.Model.Syntax

/-- What an {lit}`ON CONFLICT` clause of INSERT does with a row that conflicts. -/
inductive ConflictAction where
  /-- {lit}`DO NOTHING`: skip the row. -/
  | nothing
  /-- {lit}`DO UPDATE SET assignments [WHERE filter]`: update the existing row. -/
  | update (assignments : List (Identifier × Expr)) (filter : Option Expr)
  deriving Repr, BEq

/-- One {lit}`ON CONFLICT [(target)] action` clause of INSERT. The target is a list of
column names as written, or {lean}`(none : Option (List Identifier))` for a clause without
target. -/
structure ConflictClause where
  /-- The target column names, or none. -/
  target : Option (List Identifier)
  /-- The action. -/
  action : ConflictAction
  deriving Repr, BEq

/-- The table options of CREATE TABLE ({lit}`table_option_set`). Use {lean}`({} : TableOptions)`
for a table without options. -/
structure TableOptions where
  /-- {lit}`WITHOUT ROWID`. -/
  withoutRowid : Bool := false
  /-- {lit}`STRICT` (ADR 0014, slice 6). -/
  strict : Bool := false
  deriving Repr, BEq

deriving instance DecidableEq for ResultColumn, OrderTerm, TableReference, Join, Subquery
deriving instance DecidableEq for ConflictAction, ConflictClause

/-- When a trigger runs, relative to the write of its row (ADR 0018, D5). -/
inductive TriggerTime where
  /-- {lit}`BEFORE`, also without a time. -/
  | before
  /-- {lit}`AFTER`. -/
  | after
  deriving Repr, DecidableEq

/-- The event of a trigger: {lit}`INSERT`, {lit}`UPDATE` with the columns of {lit}`UPDATE OF`
(empty for every {lit}`UPDATE`), or {lit}`DELETE`. -/
inductive TriggerEvent where
  /-- {lit}`INSERT`. -/
  | insert
  /-- {lit}`UPDATE [OF columns]`, with the column names as written; empty without
  {lit}`OF`. -/
  | update (columns : List Identifier)
  /-- {lit}`DELETE`. -/
  | delete
  deriving Repr, DecidableEq

/-- One statement of a trigger's body as written: an INSERT with {lit}`VALUES` rows, an UPDATE,
a DELETE or a SELECT, each as the statement of the same name, without {lit}`RETURNING`, which
a trigger's body cannot have (ADR 0018, D5). -/
inductive BodyStatement where
  /-- An INSERT, as {lit}`Statement.insert`. -/
  | insert (table : Identifier) (columns : Option (List Identifier)) (rows : List (List Expr))
      (conflicts : List ConflictClause) (algorithm : Option ConflictAlgorithm := none)
      (subqueries : List Subquery := [])
  /-- An UPDATE, as {lit}`Statement.update`. -/
  | update (table : Identifier) (assignments : List (Identifier × Expr)) (filter : Option Expr)
      (subqueries : List Subquery := [])
  /-- A DELETE, as {lit}`Statement.delete`. -/
  | delete (table : Identifier) (filter : Option Expr) (subqueries : List Subquery := [])
  /-- A SELECT, as {lit}`Statement.select`. -/
  | select (columns : List ResultColumn) (source : Option TableReference) (joins : List Join) (filter : Option Expr)
      (groupBy : List Expr) (orderBy : List OrderTerm) (limit : Option Expr) (offset : Option Expr)
      (subqueries : List Subquery := []) (having : Option Expr := none) (distinct : Bool := false)
  deriving Repr, BEq, DecidableEq

/-- One statement as written. For example, {lit}`COMMIT` is
{lean}`Statement.commit`. -/
inductive Statement where
  /-- {lit}`CREATE TABLE name (columns, constraints) options`. -/
  | createTable (name : Identifier) (columns : List ColumnDefinition)
      (constraints : List TableConstraint) (options : TableOptions := {})
  /-- {lit}`CREATE [UNIQUE] INDEX name ON table (terms) [WHERE filter]`: each key term is an
  expression with its sort order, and the filter is none for an index of every row. -/
  | createIndex (name : Identifier) (unique : Bool) (table : Identifier) (terms : List OrderTerm)
      (filter : Option Expr)
  /-- {lit}`ALTER TABLE table ADD COLUMN column`. -/
  | addColumn (table : Identifier) (column : ColumnDefinition)
  /-- {lit}`DROP TABLE [IF EXISTS] name` (ADR 0014, slice 7); {lit}`ifExists` is true with
  {lit}`IF EXISTS`. -/
  | dropTable (name : Identifier) (ifExists : Bool)
  /-- {lit}`DROP INDEX [IF EXISTS] name` (ADR 0014, slice 7); {lit}`ifExists` is true with
  {lit}`IF EXISTS`. -/
  | dropIndex (name : Identifier) (ifExists : Bool)
  /-- {lit}`BEGIN`. -/
  | begin
  /-- {lit}`COMMIT` or {lit}`END`. -/
  | commit
  /-- {lit}`ROLLBACK`. -/
  | rollback
  /-- {lit}`INSERT INTO table [(columns)] VALUES rows` and its {lit}`ON CONFLICT`
  clauses in written order; a missing column list is
  {lean}`(none : Option (List Identifier))`, and an INSERT without clauses has
  {lean}`([] : List ConflictClause)`. The algorithm of {lit}`INSERT OR algorithm` or of
  {lit}`REPLACE INTO` is {lit}`algorithm`, {lean}`(none : Option ConflictAlgorithm)` without
  one. The {lit}`RETURNING` columns are {lit}`returning`, empty without the clause. The
  subqueries of the statement are {lit}`subqueries`, as for {lit}`SELECT`. -/
  | insert (table : Identifier) (columns : Option (List Identifier)) (rows : List (List Expr))
      (conflicts : List ConflictClause) (algorithm : Option ConflictAlgorithm := none)
      (returning : List ResultColumn := []) (subqueries : List Subquery := [])
  /-- {lit}`UPDATE table SET assignments [WHERE filter] [RETURNING columns]`, with the
  subqueries of the statement, as for {lit}`SELECT`. -/
  | update (table : Identifier) (assignments : List (Identifier × Expr)) (filter : Option Expr)
      (returning : List ResultColumn := []) (subqueries : List Subquery := [])
  /-- {lit}`DELETE FROM table [WHERE filter] [RETURNING columns]`, with the subqueries of the
  statement, as for {lit}`SELECT`. -/
  | delete (table : Identifier) (filter : Option Expr) (returning : List ResultColumn := [])
      (subqueries : List Subquery := [])
  /-- {lit}`SELECT columns FROM source joins [WHERE filter] [GROUP BY terms] [ORDER BY terms]
  [LIMIT limit [OFFSET offset]]`: the first table of {lit}`FROM` and the joins after it, in
  order; one table has no joins, and a {lit}`SELECT` without {lit}`FROM` has
  {lean}`(none : Option TableReference)` and no joins. An omitted clause is {lit}`none` or
  an empty list;
  {lit}`LIMIT offset, limit` gives both expressions. The subqueries of the statement are
  {lit}`subqueries`, in the order of their text ({name}`Subquery`); empty without one. The
  {lit}`HAVING` condition is {lit}`having` and {lit}`SELECT DISTINCT` has {lit}`distinct`
  (ADR 0018, D3). A compound {lit}`SELECT` (ADR 0019, D3) has no columns and no {lit}`FROM`,
  and {lit}`compound` names its terms among the subqueries ({name}`Compound`), each with the
  statement's query as its parent; its {lit}`ORDER BY`, {lit}`LIMIT` and {lit}`OFFSET` are
  those of the compound. Use {lean}`(none : Option Compound)` for one {lit}`SELECT`. -/
  | select (columns : List ResultColumn) (source : Option TableReference) (joins : List Join) (filter : Option Expr)
      (groupBy : List Expr) (orderBy : List OrderTerm) (limit : Option Expr) (offset : Option Expr)
      (subqueries : List Subquery := []) (having : Option Expr := none) (distinct : Bool := false)
      (compound : Option Compound := none)
  /-- {lit}`PRAGMA foreign_keys = value`, with the value as {lit}`sqlite3GetBoolean` reads it,
  or the query {lit}`PRAGMA foreign_keys` with {lean}`(none : Option Bool)` (ADR 0018, D4). -/
  | pragmaForeignKeys (value : Option Bool)
  /-- {lit}`CREATE TRIGGER [IF NOT EXISTS] name time event ON table [FOR EACH ROW] [WHEN
  condition] BEGIN body END` (ADR 0018, D5), with the statements of the body in order;
  {lit}`ifNotExists` is true with {lit}`IF NOT EXISTS`. -/
  | createTrigger (name : Identifier) (ifNotExists : Bool) (time : TriggerTime) (event : TriggerEvent)
      (table : Identifier) (condition : Option Expr) (body : List BodyStatement)
  /-- {lit}`DROP TRIGGER [IF EXISTS] name` (ADR 0018, D5). -/
  | dropTrigger (name : Identifier) (ifExists : Bool)
  deriving Repr, BEq

/-- The statement of the same form as a body statement, without {lit}`RETURNING`, which
resolution reads as any other statement. -/
def BodyStatement.statement : BodyStatement → Statement
  | .insert table columns rows conflicts algorithm subqueries =>
    .insert table columns rows conflicts algorithm [] subqueries
  | .update table assignments filter subqueries => .update table assignments filter [] subqueries
  | .delete table filter subqueries => .delete table filter [] subqueries
  | .select columns source joins filter groupBy orderBy limit offset subqueries having distinct =>
    .select columns source joins filter groupBy orderBy limit offset subqueries having distinct

end Belay.Sqlite.Model.Syntax
