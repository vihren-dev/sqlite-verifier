import Belay.Sqlite.Model.Resolution.MergedNames

set_option doc.verso true

/-! The collation of an expression as SQLite decides it at prepare time (ADR 0014, D3;
{lit}`sqlite3ExprCollSeq` and {lit}`sqlite3BinaryCompareCollSeq` in 3.51.0). An explicit
{lit}`COLLATE` anywhere in an expression gives its collation; else a column reference, also
under unary plus and {lit}`CAST`, gives its column's collation; else the expression has
none, which compares as {lit}`BINARY`. -/

namespace Belay.Sqlite.Model

mutual
/-- The collation of the first {lit}`COLLATE` in an expression, searched in SQLite's order:
the expression itself, then the left operand, then the right operand or the arguments.
A name that names no collation reads as {lit}`BINARY`; resolution restricts or refuses it
before. -/
def Syntax.Expr.explicitCollation : Syntax.Expr → Option Collation
  | .collate _ name => some ((Collation.named? name).getD .binary)
  | .positive operand | .negate operand | .cast operand _ | .not operand | .isNull operand _
  | .inQuery operand .. =>
    operand.explicitCollation
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .concatenate left right =>
    left.explicitCollation <|> right.explicitCollation
  | .call _ arguments => Syntax.Expr.firstExplicitCollation arguments
  | .inList operand values _ => operand.explicitCollation <|> Syntax.Expr.firstExplicitCollation values
  | .between operand low high _ => operand.explicitCollation <|> low.explicitCollation <|> high.explicitCollation
  | .caseOf operands _ => Syntax.Expr.firstExplicitCollation operands
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .qualified .. | .callStar _
  | .exists _ | .subquery _ | .raise .. =>
    none

/-- The first explicit collation of the arguments ({name}`Syntax.Expr.explicitCollation`). -/
def Syntax.Expr.firstExplicitCollation : List Syntax.Expr → Option Collation
  | [] => none
  | argument :: rest => argument.explicitCollation <|> Syntax.Expr.firstExplicitCollation rest
end

/-- The collation of a column reference over the scope, also under unary plus and CAST.
A name that reads one column has that column's collation, including the right column after
a RIGHT JOIN. A coalesce of columns after a FULL JOIN has none, as does any other expression. -/
def Syntax.Expr.columnCollation (scope : Scope) : Syntax.Expr → Option Collation
  | .identifier name _ => match scope.resolveName name with
    | .found _ [position] => scope.columns[position]?.map (·.collation)
    | .found _ _ | .missing | .ambiguous => none
  | .qualified source column => match scope.resolveQualified source column with
    | .found _ [position] => scope.columns[position]?.map (·.collation)
    | .found _ _ | .missing | .ambiguous => none
  | .positive operand | .cast operand _ | .collate operand _ => operand.columnCollation scope
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .negate _ | .compare .. | .and .. | .or ..
  | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .exists _ | .inQuery .. | .subquery _
  | .inList .. | .between .. | .caseOf .. | .concatenate .. | .raise .. => none

/-- Whether an expression is a column under one {lit}`COLLATE`: a qualified name, or an
unqualified name that reads a column of the scope. The model admits such a
{lit}`GROUP BY` term; a name that reads no column could name a result column. It does not
recurse, so the kernel reduces it in the proofs of conformance cases; a second
{lit}`COLLATE` stays a restriction. -/
def Syntax.Expr.collatedColumn (scope : Scope) : Syntax.Expr → Bool
  | .collate (.identifier name _) _ => (scope.resolveName name matches .found ..)
  | .collate (.qualified ..) _ => true
  | .collate (.collate ..) _ | .collate .null _ | .collate (.numeric _) _ | .collate (.string _) _
  | .collate (.blob _) _ | .collate (.parameter _) _ | .collate (.currentTime _) _ | .collate (.negate _) _ | .collate (.positive _) _
  | .collate (.compare ..) _ | .collate (.and ..) _ | .collate (.or ..) _ | .collate (.not _) _
  | .collate (.isNull ..) _ | .collate (.callStar _) _ | .collate (.call ..) _ | .collate (.arithmetic ..) _
  | .collate (.cast ..) _ | .collate (.exists _) _ | .collate (.inQuery ..) _ | .collate (.subquery _) _
  | .collate (.inList ..) _ | .collate (.between ..) _ | .collate (.caseOf ..) _ | .collate (.concatenate ..) _
  | .collate (.raise ..) _ | .raise .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf .. | .concatenate ..
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .qualified .. | .negate _
  | .positive _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic ..
  | .cast .. => false

/-- The collation of an expression ({lit}`sqlite3ExprCollSeq`): its explicit collation, else
its column's, else {lit}`BINARY`. It is the collation of an {lit}`ORDER BY` or
{lit}`GROUP BY` term and of the operand of {lit}`min` and {lit}`max`. -/
def Syntax.Expr.collationIn (scope : Scope) (expression : Syntax.Expr) : Collation :=
  (expression.explicitCollation <|> expression.columnCollation scope).getD .binary

/-- The collation of a comparison ({lit}`sqlite3BinaryCompareCollSeq`): the explicit
collation of the left operand, else of the right operand, else the column collation of the
left operand, else of the right, else {lit}`BINARY`. -/
def comparisonCollation (scope : Scope) (left right : Syntax.Expr) : Collation :=
  (left.explicitCollation <|> right.explicitCollation <|> left.columnCollation scope <|>
    right.columnCollation scope).getD .binary

/-- The collation of the expression that a star expands to. A right join can select a
later column; a full join can produce a coalesce with no column collation. This reads the
same expansion as {name}`Scope.starOperand`. -/
def Scope.starCollation (scope : Scope) (position : Nat) (column : CatalogColumn) : Option Collation :=
  match scope.starOperand position column with
  | .ok (.column index, _) => scope.columns[index]?.map (·.collation)
  | .ok _ | .error _ => none

/-- The collation of each result column of a {lit}`SELECT`, in the order of its outputs: a
column of {lit}`*` or {lit}`x.*` has its expanded operand's collation (BINARY when it has none), and an expression its
{name}`Syntax.Expr.collationIn`. An {lit}`ORDER BY` or {lit}`GROUP BY` term that names a
result column has that column's collation. -/
def resultCollations (scope : Scope) (results : List Syntax.ResultColumn) : List Collation :=
  results.flatMap fun
    | .star => scope.visible.map fun (position, column) => (scope.starCollation position column).getD .binary
    | .sourceStar name => ((scope.starColumns? name).map (·.map fun (position, column) => (scope.starCollation position column).getD .binary)).getD []
    | .expression value _ _ => [value.collationIn scope]

/-- An aggregate under the collation of its operand: {lit}`min` and {lit}`max` compare
under it; the other aggregates do not compare values. -/
def Resolved.Aggregate.withCollation (collation : Collation) : Resolved.Aggregate → Resolved.Aggregate
  | .min operand _ => .min operand collation
  | .max operand _ => .max operand collation
  | aggregate@.countRows | aggregate@(.count _) | aggregate@(.sum _) | aggregate@(.avg _)
  | aggregate@(.jsonGroupArray ..) | aggregate@(.jsonGroupObject ..) | aggregate@(.groupConcat ..)
  | aggregate@(.total _) => aggregate

end Belay.Sqlite.Model
