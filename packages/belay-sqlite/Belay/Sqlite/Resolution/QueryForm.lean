import Belay.Sqlite.Declarations
import Belay.Sqlite.Operators

set_option doc.verso true

/-! The resolved form of a single-table query of ADR 0012, slice 1: what
{lit}`resolve` gives for a {lit}`SELECT` and what the Queries level evaluates.
Names are already table positions, and the affinity rules of a comparison are
already applied to its literal operands, so evaluation needs no catalog. -/

namespace Belay.Sqlite.Resolved

/-- A scalar expression over one row of the source table. Its value is a stored
value; the comparisons and logical operators give the integers 1 and 0, or NULL. -/
inductive Expr where
  /-- The value of the column at a table position. -/
  | column (position : Nat)
  /-- A literal value, after the affinity of a comparison is applied to it. -/
  | literal (value : Value)
  /-- A comparison of two operands. -/
  | compare (operator : Comparison) (left right : Expr)
  /-- {lit}`AND`, with SQLite's three-valued logic. -/
  | and (left right : Expr)
  /-- {lit}`OR`, with SQLite's three-valued logic. -/
  | or (left right : Expr)
  /-- {lit}`NOT`, with SQLite's three-valued logic. -/
  | not (operand : Expr)
  /-- {lit}`IS NULL`, or {lit}`IS NOT NULL` when {lit}`negated` is true. -/
  | isNull (operand : Expr) (negated : Bool)
  /-- An arithmetic operator between two operands. -/
  | arithmetic (operator : ArithmeticOperator) (left right : Expr)
  /-- {lit}`CAST` to the affinity of the written type name. -/
  | cast (affinity : Affinity) (operand : Expr)
  /-- {lit}`COALESCE`: the first operand when it is not NULL, else the second. -/
  | coalesce (first rest : Expr)
  deriving Repr, DecidableEq

/-- An aggregate function of slice 1, over the rows of one group. -/
inductive Aggregate where
  /-- {lit}`COUNT(*)`: the number of rows. -/
  | countRows
  /-- {lit}`COUNT(x)`: the number of rows where the operand is not NULL. -/
  | count (operand : Expr)
  /-- {lit}`MIN(x)`: the least operand value that is not NULL, or NULL. -/
  | min (operand : Expr)
  /-- {lit}`MAX(x)`: the greatest operand value that is not NULL, or NULL. -/
  | max (operand : Expr)
  /-- {lit}`SUM(x)`: the sum of the operand values that are not NULL, by
  {lit}`SumState.sumValue`; it fails on an integer overflow. -/
  | sum (operand : Expr)
  /-- {lit}`AVG(x)`: the average of the operand values that are not NULL, by
  {lit}`SumState.averageValue`. -/
  | avg (operand : Expr)
  deriving Repr, DecidableEq

/-- Whether an aggregate can fail while the statement runs: {lit}`SUM`, on an integer
overflow. -/
def Aggregate.canFail : Aggregate → Bool
  | .sum _ => true
  | .countRows | .count _ | .min _ | .max _ | .avg _ => false

/-- One result column: an expression over a row, or, in an aggregate query, an
aggregate over a group or an expression over the group's first row, which
{lit}`resolve` admits only when the expression uses only grouping terms. -/
inductive Output where
  /-- An expression over the row, or over the first row of a group. -/
  | scalar (expression : Expr)
  /-- An aggregate over the rows of a group. -/
  | aggregate (aggregate : Aggregate)
  deriving Repr, DecidableEq

/-- Whether a result column can fail while the statement runs: an aggregate that
{name}`Aggregate.canFail`. -/
def Output.canFail : Output → Bool
  | .aggregate function => function.canFail
  | .scalar _ => false

/-- The value that one {lit}`ORDER BY` term sorts by: an expression over the source
row (only in a query that is not an aggregate query), or a result column. -/
inductive SortKey where
  /-- An expression over the source row. -/
  | expression (expression : Expr)
  /-- The result column at a zero-based index. -/
  | output (index : Nat)
  deriving Repr, DecidableEq

/-- The kind of a resolved join: inner, or left, right or full outer. -/
inductive JoinKind where
  /-- An inner join: the rows of the product for which the condition is true. -/
  | inner
  /-- A left outer join: the inner join, and each left row that no right row matches,
  with NULL in every right column. -/
  | left
  /-- A right outer join: the inner join, and each right row that no row of the left
  input matches, with NULL in every column of the left input. -/
  | right
  /-- A full outer join: the inner join and the added rows of both a left and a right
  join. -/
  | full
  deriving Repr, DecidableEq

/-- One resolved join after the first table: its kind, the catalog position of the
joined table, and its {lit}`ON` condition over the joined row so far and the new table;
{lean}`(none : Option Expr)` for no condition. -/
structure Join where
  /-- The kind of the join. -/
  kind : JoinKind
  /-- The catalog position of the joined table. -/
  table : Nat
  /-- The {lit}`ON` condition, over the cells of the tables up to this one. -/
  condition : Option Expr
  deriving Repr, DecidableEq

/-- A resolved {lit}`SELECT`: the first table's catalog position and the joins after
it, the {lit}`WHERE` condition, whether it is an aggregate query with its grouping terms,
the result columns with their names, the {lit}`ORDER BY` terms with a flag for
{lit}`DESC`, and the window. Use {lean}`(none : Option Nat)` for no {lit}`LIMIT`. -/
structure Query where
  /-- The catalog position of the first source table, or
  {lean}`(none : Option Nat)` for a {lit}`SELECT` without {lit}`FROM`, whose source is one
  row with no columns. -/
  table : Option Nat
  /-- The joins after the first table, in order; empty for a query of one table. An
  expression names a cell by its position in the concatenated row of all tables. -/
  joins : List Join := []
  /-- The {lit}`WHERE` condition, or {lean}`(none : Option Expr)` for every row. -/
  filter : Option Expr
  /-- Whether the query is an aggregate query: it has {lit}`GROUP BY` or an aggregate. -/
  aggregate : Bool
  /-- The {lit}`GROUP BY` terms; empty for one group of all rows. -/
  groupBy : List Expr
  /-- The result columns, in order. -/
  columns : List Output
  /-- The name of each result column. -/
  names : List String
  /-- The {lit}`ORDER BY` terms, each with {lean}`true` for {lit}`DESC`. -/
  orderBy : List (SortKey × Bool)
  /-- The number of rows that {lit}`OFFSET` skips; zero without {lit}`OFFSET`. -/
  offset : Nat
  /-- The {lit}`LIMIT`, or {lean}`(none : Option Nat)` for no limit. -/
  limit : Option Nat
  deriving Repr, DecidableEq

end Belay.Sqlite.Resolved
