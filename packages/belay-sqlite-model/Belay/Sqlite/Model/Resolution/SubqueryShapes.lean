import Belay.Sqlite.Model.Resolution.Collations
import Belay.Sqlite.Model.Resolution.QueryAffinity
import Belay.Sqlite.Model.Resolution.SyntaxEquality
import Belay.Sqlite.Model.Resolution.Values

set_option doc.verso true

/-! What resolution knows of the subqueries of a statement while it resolves the query around
them (ADR 0018, D1). Resolution handles a subquery before the query around it, because the
query needs the affinity and the collation of the subquery's result column. -/

namespace Belay.Sqlite.Model

/-- A resolved subquery as the query around it sees it: the query around it, its number of
result columns, the affinity, the explicit collation and the column collation of its first
result column, the lowest cell position that it or a subquery inside it reads, which is
below its own cells when it reads a cell of a query around it, and whether {lit}`IN` and a scalar
subquery would read the column of a derived table. For a compound {lit}`SELECT` the first
column is that of its right-most term (ADR 0019, D3). -/
structure SubqueryShape where
  /-- The index of the subquery around it, or none for the statement's query. -/
  parent : Option Nat
  /-- The number of result columns. -/
  columns : Nat
  /-- The affinity of the first result column: a scalar subquery has it
  ({lit}`sqlite3ExprAffinity`). -/
  affinity : Option Affinity
  /-- The explicit collation of the first result column. -/
  explicitCollation : Option Collation
  /-- The column collation of the first result column. -/
  columnCollation : Option Collation
  /-- The lowest cell position that the subquery or a subquery inside it reads, if any. -/
  lowest : Option Nat
  /-- Whether SQLite sorts the subquery, a compound, as {lit}`SELECT * FROM (compound)`, so that
  {lit}`IN` and a scalar subquery read the column of that derived table; false for one
  {lit}`SELECT`. -/
  derived : Bool := false
  deriving Repr, DecidableEq

/-- What an expression of the current query may name besides its row: the subqueries after
the query whose expressions resolution resolves, which is {lit}`current` (none for the
statement's query), as {lit}`later`, the shape of subquery {lit}`base + k` at position {lit}`k`;
and the aggregates of the query. Use {lean}`({} : SubqueryShapes)` where neither is modeled. -/
structure SubqueryShapes where
  /-- The index of the subquery whose expressions are resolved, or none for the statement's
  query. -/
  current : Option Nat := none
  /-- The shapes of the subqueries after it, in order. -/
  later : List SubqueryShape := []
  /-- The number of cells of the queries around the current query, which come first in its
  row; 0 for the statement's query. -/
  outer : Nat := 0
  /-- The aggregate calls of the current query as written, which an expression names by index
  ({lit}`Resolved.Expr.aggregateValue`, ADR 0018, D3); empty where no aggregate is modeled. -/
  aggregates : List Syntax.Expr := []
  deriving Repr

/-- The index of the first subquery after the current query. -/
def SubqueryShapes.base (shapes : SubqueryShapes) : Nat :=
  match shapes.current with
  | none => 0
  | some index => index + 1

/-- The shape of the subquery that an expression of the current query names: subquery
{lit}`index` when it comes after the current query and the current query is around it; none
otherwise, which the frontend never gives. -/
def SubqueryShapes.find (shapes : SubqueryShapes) (index : Nat) : Option SubqueryShape :=
  if index < shapes.base then none
  else (shapes.later[index - shapes.base]?).filter (·.parent == shapes.current)

/-- The shape of the subquery whose one result column {lit}`IN` or a scalar subquery reads
({name}`SubqueryShapes.find`): {name}`RestrictionKind.subqueryHere` when resolution has none,
{name}`RestrictionKind.compoundSubqueryColumn` for the column of a derived table
({name}`SubqueryShape.derived`), and SQLite's {lit}`sub-select returns %d columns - expected 1`
for another number of columns. -/
def SubqueryShapes.column (shapes : SubqueryShapes) (index : Nat) : Except ValueIssue SubqueryShape :=
  match shapes.find index with
  | none => .error (.restriction [] .subqueryHere)
  | some shape =>
    if shape.derived then .error (.restriction [] .compoundSubqueryColumn)
    else if shape.columns == 1 then .ok shape else .error (.prepare (.subqueryColumns shape.columns))

/-- The smaller of two optional positions. -/
def minPosition : Option Nat → Option Nat → Option Nat
  | some a, some b => some (min a b)
  | some a, none | none, some a => some a
  | none, none => none

mutual
/-- The lowest cell position that a resolved expression reads, with the subqueries that it
names ({name}`SubqueryShape.lowest`); none when it reads no cell. -/
def Resolved.Expr.lowestRead (shapes : SubqueryShapes) : Resolved.Expr → Option Nat
  | .column position => some position
  | .literal _ | .now _ | .aggregateValue _ | .parameter _ => none
  | .exists index | .subquery index => (shapes.find index).bind (·.lowest)
  | .inQuery operand index .. => minPosition (operand.lowestRead shapes) ((shapes.find index).bind (·.lowest))
  | .compare _ _ left right _ | .and left right | .or left right | .arithmetic _ left right | .coalesce left right =>
    minPosition (left.lowestRead shapes) (right.lowestRead shapes)
  | .not operand | .isNull operand _ | .cast _ operand => operand.lowestRead shapes
  | .inList operand values .. => minPosition (operand.lowestRead shapes) (Resolved.Arguments.lowestRead shapes values)
  | .json _ arguments | .date _ arguments | .scalar _ arguments => Resolved.Arguments.lowestRead shapes arguments

/-- The lowest cell position that the arguments read ({name}`Resolved.Expr.lowestRead`). -/
def Resolved.Arguments.lowestRead (shapes : SubqueryShapes) : Resolved.Arguments → Option Nat
  | .nil => none
  | .cons head tail => minPosition (head.lowestRead shapes) (Resolved.Arguments.lowestRead shapes tail)
end

/-- Whether the arguments read a cell below {lit}`width`, such as a cell of a query around
the current one ({name}`Resolved.Arguments.lowestRead`). -/
def Resolved.Arguments.readsUnder (shapes : SubqueryShapes) (width : Nat) (arguments : Resolved.Arguments) : Bool :=
  (arguments.lowestRead shapes).any (· < width)

/-- Whether the expression reads a cell below {lit}`width` ({name}`Resolved.Expr.lowestRead`). -/
def Resolved.Expr.readsUnder (shapes : SubqueryShapes) (width : Nat) (expression : Resolved.Expr) : Bool :=
  (expression.lowestRead shapes).any (· < width)

/-- The collation of {lit}`operand IN (q)` ({lit}`sqlite3BinaryCompareCollSeq` of the operand
and the result column of {lit}`q`): the explicit collation of the operand, else of the result
column, else the column collation of the operand, else of the result column, else
{lit}`BINARY`. -/
def inCollation (scope : Scope) (operand : Syntax.Expr) (shape : SubqueryShape) : Collation :=
  (operand.explicitCollation <|> shape.explicitCollation <|> operand.columnCollation scope <|>
    shape.columnCollation).getD .binary

end Belay.Sqlite.Model
