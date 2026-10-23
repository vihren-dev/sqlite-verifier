import Belay.Sqlite.Model.Resolution.Catalog
import Belay.Sqlite.Model.Resolution.ConflictForm

set_option doc.verso true

/-! The resolved form of the cells of an INSERT row and of a trigger's program (ADR 0018, D5).
A program reads the trigger's {lit}`NEW` and {lit}`OLD` rows as cells, one for each column of the
trigger's table in each row that its event has: the {lit}`NEW` cells of INSERT and UPDATE, then
the {lit}`OLD` cells of UPDATE and DELETE. Its condition and the rows of
an INSERT of its body read them from position 0; an UPDATE or a DELETE of its body reads them
after the cells of its own table; and a SELECT reads them as the outer cells of a subquery,
before the cells of its own sources. Resolution refuses every name of a row that the event does
not have, such as {lit}`OLD` of an INSERT. -/

namespace Belay.Sqlite.Model.Resolved

/-- One cell of a resolved INSERT row: a value that resolution computed and stored with the
column's affinity, or an expression that reads the statement's clock, such as a
{lit}`VALUES` item {lit}`CURRENT_TIMESTAMP` or an omitted column with that default, which the
execution evaluates at the statement's clock value and stores with the column's affinity.
An expression cell of a statement reads no column; one of a trigger's body may read the
trigger's {lit}`NEW` and {lit}`OLD` cells. Use {lean}`Cell.value` for a known value. -/
inductive Cell where
  /-- A value, stored with the column's affinity. -/
  | value (value : Value)
  /-- An expression that reads the clock, or a trigger's cells, and no column of a table. -/
  | expression (expression : Expr)
  deriving Repr, DecidableEq

/-- The event of a trigger program: {lit}`INSERT`, {lit}`UPDATE` with the positions of the
columns of {lit}`UPDATE OF` (none for every {lit}`UPDATE`), or {lit}`DELETE`. A name of
{lit}`UPDATE OF` that names no column of the table has no position, so such a trigger runs for
no {lit}`UPDATE`, as in SQLite. -/
inductive TriggerEvent where
  /-- {lit}`INSERT`. -/
  | insert
  /-- {lit}`UPDATE [OF columns]`. -/
  | update (columns : Option (List Nat))
  /-- {lit}`DELETE`. -/
  | delete
  deriving Repr, DecidableEq

/-- Whether a trigger of the event fires for a write of the event: INSERT for INSERT, DELETE for
DELETE, and for an UPDATE whose {lit}`SET` columns are {lit}`columns` a trigger of every UPDATE,
or one of {lit}`UPDATE OF` a column among them, as SQLite's {lit}`checkColumnOverlap` decides. -/
def TriggerEvent.fires : TriggerEvent → TriggerEvent → Bool
  | .insert, .insert | .delete, .delete | .update none, .update _ => true
  | .update (some listed), .update set => (set.getD []).any listed.contains
  | .insert, .update _ | .insert, .delete | .update _, .insert | .update _, .delete | .delete, .insert
  | .delete, .update _ => false

/-- One statement of a trigger's body after resolution, over the trigger's cells as the module
docstring places them, with the subqueries that its expressions name by index:
- an INSERT of full rows of cells, with its {lit}`ON CONFLICT` clauses and its algorithm;
- an UPDATE and a DELETE, as the statements of the same name;
- a SELECT, whose rows nothing reads: only its errors matter;
- a SELECT without {lit}`FROM` whose one result column is {lit}`RAISE(...)` or a {lit}`CASE`
  with {lit}`RAISE(...)` results: for its row, when the filter holds, the kind of the first arm
  whose condition is true, or of {lit}`otherwise` when none is; an arm or an
  {lit}`otherwise` without a kind does not raise. -/
inductive Step where
  /-- INSERT of full rows into the table at the position. -/
  | insert (table : Nat) (rows : List (List Cell)) (clauses : List ConflictClause)
      (algorithm : Option ConflictAlgorithm) (subqueries : List Query)
  /-- UPDATE of the table at the position. -/
  | update (table : Nat) (assignments : List (Nat × Expr)) (filter : Option Expr) (subqueries : List Query)
  /-- DELETE from the table at the position. -/
  | delete (table : Nat) (filter : Option Expr) (subqueries : List Query)
  /-- A SELECT, run for its errors. -/
  | query (query : Query) (subqueries : List Query)
  /-- A SELECT whose result raises. -/
  | raise (filter : Option Expr) (arms : List (Expr × Option Syntax.RaiseKind)) (otherwise : Option Syntax.RaiseKind)
  deriving Repr, DecidableEq

/-- The program of one trigger: the catalog position of the trigger, which is its identity, the
position of its table, its time and event, the number of columns of its table, its
{lit}`WHEN` condition (none for every row) and the steps of its body in order. -/
structure Program where
  /-- The catalog position of the trigger. -/
  trigger : Nat
  /-- The catalog position of the trigger's table. -/
  table : Nat
  /-- {lit}`BEFORE` or {lit}`AFTER`. -/
  time : Syntax.TriggerTime
  /-- The event. -/
  event : TriggerEvent
  /-- The number of columns of the table: the number of {lit}`NEW` cells, and of {lit}`OLD` cells. -/
  width : Nat
  /-- The {lit}`WHEN` condition over the trigger's cells. -/
  condition : Option Expr
  /-- The steps of the body. -/
  body : List Step
  deriving Repr, DecidableEq

/-- What a write runs row by row besides its own rows (ADR 0018, D4 and D5): the connection's
trigger depth limit, which bounds the depth of the nested writes; whether it checks foreign
keys; whether recursive triggers are on; and the programs of every trigger that it, or a write
that it runs, may fire. A write without foreign keys to check and without triggers has none. -/
structure WriteRules where
  /-- The trigger depth limit. -/
  depth : Nat
  /-- Whether the write checks foreign keys. -/
  keys : Bool
  /-- Whether a trigger fires again while it runs, and the rows that REPLACE deletes fire the
  DELETE triggers ({lit}`PRAGMA recursive_triggers`); off by default, as in SQLite. -/
  recursive : Bool := false
  /-- The programs of the triggers that the write may fire, at any depth. -/
  programs : List Program := []
  deriving Repr, DecidableEq

end Belay.Sqlite.Model.Resolved
