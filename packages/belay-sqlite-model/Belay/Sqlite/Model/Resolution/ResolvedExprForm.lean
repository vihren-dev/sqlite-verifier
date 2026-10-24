import Belay.Sqlite.Model.Declarations
import Belay.Sqlite.Model.Operators
import Belay.Sqlite.Model.Comparison
import Belay.Sqlite.Model.Resolution.JsonFunction
import Belay.Sqlite.Model.Resolution.DateFunction
import Belay.Sqlite.Model.Resolution.ScalarFunction
import Belay.Sqlite.Model.ClockText
import Belay.Sqlite.Model.Counters

set_option doc.verso true

/-! The resolved forms of the values of a query (ADR 0012, slice 1): scalar expressions,
aggregates, result columns and {lit}`ORDER BY` terms. Names are already column positions,
and each comparison, sort term and aggregate keeps its affinity and collation, so
evaluation needs no catalog. {lit}`QueryForm.lean` builds the query from them. -/

namespace Belay.Sqlite.Model.Resolved

mutual
/-- A scalar expression over one row of the source table. Its value is a stored
value; the comparisons and logical operators give the integers 1 and 0, or NULL. -/
inductive Expr where
  /-- The value of the column at a table position. -/
  | column (position : Nat)
  /-- A literal value, after the affinity of a comparison is applied to it. -/
  | literal (value : Value)
  /-- A comparison of two operands, with the affinity that SQLite applies to them
  ({lit}`comparisonAffinity`; none applies no conversion) and the collation that resolution
  chose for it (ADR 0014, D3), {lit}`BINARY` when none is written. -/
  | compare (operator : Comparison) (affinity : Option Affinity) (left right : Expr)
      (collation : Collation := .binary)
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
  /-- A call of a JSON function with its arguments in written order. -/
  | json (function : JsonFunction) (arguments : Arguments)
  /-- {lit}`CURRENT_TIME`, {lit}`CURRENT_DATE` or {lit}`CURRENT_TIMESTAMP`: the statement's clock
  value as text, which evaluation computes from the clock value it is given. -/
  | now (keyword : TimeKeyword)
  /-- Parameter {lit}`number` of the statement (ADR 0019, D1): item {lit}`number` of the values
  that evaluation is given, from 1, or NULL when there is no such item. -/
  | parameter (number : Nat)
  /-- A call of {lit}`changes()`, {lit}`total_changes()` or {lit}`last_insert_rowid()` (ADR 0024,
  D2): the counter of the connection before the statement, as an integer. -/
  | counter (kind : CounterKind)
  /-- A call of a date and time function with its arguments in written order; {lit}`now`
  and a call without a time value read the clock value that evaluation is given. -/
  | date (function : DateFunction) (arguments : Arguments)
  /-- A call of a scalar function of ADR 0015 with its arguments in written order. -/
  | scalar (function : ScalarFunction) (arguments : Arguments)
  /-- {lit}`EXISTS (q)` (ADR 0018, D1): whether subquery {lit}`index` of the statement gives a
  row for the expression's row. {lit}`NOT EXISTS (q)` is {lit}`NOT` of it, as SQLite parses it. -/
  | exists (index : Nat)
  /-- {lit}`operand IN (q)`, or {lit}`NOT IN` when {lit}`negated`: whether the value of the
  operand is among the values of subquery {lit}`index`, compared under the affinity and the
  collation that resolution chose, as {lit}`=` compares them. -/
  | inQuery (operand : Expr) (index : Nat) (affinity : Option Affinity) (collation : Collation) (negated : Bool)
  /-- A scalar subquery {lit}`(q)`: the first value of the first row of subquery {lit}`index`,
  or NULL when it gives no row. -/
  | subquery (index : Nat)
  /-- {lit}`operand IN (values)`, or {lit}`NOT IN` when {lit}`negated` (ADR 0018, D2): whether the
  value of the operand is among the values, compared under the affinity and the collation of
  the operand, as SQLite compares a list. -/
  | inList (operand : Expr) (values : Arguments) (affinity : Option Affinity) (collation : Collation) (negated : Bool)
  /-- The value of aggregate {lit}`index` of the query's aggregates over the current group
  (ADR 0018, D3), as an aggregate inside an expression, such as {lit}`count(*) + 1`. -/
  | aggregateValue (index : Nat)
  deriving Repr, DecidableEq

/-- The arguments of a call in written order, as a list that is mutual with
{lit}`Expr`, so equality stays derivable and recursion stays structural. -/
inductive Arguments where
  /-- No more arguments. -/
  | nil
  /-- An argument and the arguments after it. -/
  | cons (head : Expr) (tail : Arguments)
  deriving Repr, DecidableEq
end

/-- An aggregate function of slice 1, over the rows of one group. -/
inductive Aggregate where
  /-- {lit}`COUNT(*)`: the number of rows. -/
  | countRows
  /-- {lit}`COUNT(x)`: the number of rows where the operand is not NULL. -/
  | count (operand : Expr)
  /-- {lit}`MIN(x)`: the least operand value that is not NULL under the operand's collation,
  or NULL. -/
  | min (operand : Expr) (collation : Collation := .binary)
  /-- {lit}`MAX(x)`: the greatest operand value that is not NULL under the operand's
  collation, or NULL. -/
  | max (operand : Expr) (collation : Collation := .binary)
  /-- {lit}`SUM(x)`: the sum of the operand values that are not NULL, by
  {lit}`SumState.sumValue`; it fails on an integer overflow. -/
  | sum (operand : Expr)
  /-- {lit}`AVG(x)`: the average of the operand values that are not NULL, by
  {lit}`SumState.averageValue`. -/
  | avg (operand : Expr)
  /-- {lit}`json_group_array(x)`: the JSON array of the operand values of the group in order,
  each written as {lit}`json_array` writes it, NULL as {lit}`null`; {lit}`[]` for an empty group.
  With {lit}`binary`, {lit}`jsonb_group_array`: the same array as JSONB. -/
  | jsonGroupArray (operand : Expr) (binary : Bool := false)
  /-- {lit}`json_group_object(label, value)`: the JSON object of the members of the group in
  order, the label as text up to its first NUL byte and the value as {lit}`json_object` writes
  it; a row with a NULL label adds no member; {lit}`{}` for an empty group. With {lit}`binary`,
  {lit}`jsonb_group_object`: the same object as JSONB. -/
  | jsonGroupObject (label value : Expr) (binary : Bool := false)
  /-- {lit}`group_concat(x [, separator])` and {lit}`string_agg(x, separator)`: the text of the
  operand values that are not NULL, in the order of the group's rows, each after the first
  preceded by the separator of its own row ({lit}`,` without a separator, nothing for a NULL
  one); NULL when every value is NULL. -/
  | groupConcat (operand : Expr) (separator : Option Expr)
  /-- {lit}`total(x)`: the sum of the operand values that are not NULL as a REAL, by
  {lit}`SumState.totalValue`; {lit}`0.0` for an empty group, and it never fails. -/
  | total (operand : Expr)
  deriving Repr, DecidableEq

/-- Whether an aggregate can fail while the statement runs: {lit}`SUM`, on an integer
overflow. -/
def Aggregate.canFail : Aggregate → Bool
  | .sum _ => true
  | .countRows | .count _ | .min .. | .max .. | .avg _ | .jsonGroupArray .. | .jsonGroupObject .. | .groupConcat .. | .total _ => false

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

/-- One {lit}`ORDER BY` term: the value it sorts by, whether it is {lit}`DESC`, and the
collation of its expression ({lit}`BINARY` when none applies). -/
structure SortTerm where
  /-- The value the term sorts by. -/
  key : SortKey
  /-- Whether the term is {lit}`DESC`. -/
  descending : Bool := false
  /-- The collation of the term's expression. -/
  collation : Collation := .binary
  deriving Repr, DecidableEq

end Belay.Sqlite.Model.Resolved
