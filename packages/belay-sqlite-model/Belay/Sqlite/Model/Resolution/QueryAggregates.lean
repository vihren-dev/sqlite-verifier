import Belay.Sqlite.Model.Resolution.QueryExprs
import Belay.Sqlite.Model.Resolution.QueryTerms

set_option doc.verso true

/-! The aggregates of a query (ADR 0018, D3): the aggregate calls of its result columns,
{lit}`HAVING` and {lit}`ORDER BY`, which resolution lists so that an expression names one by its
index ({lit}`Resolved.Expr.aggregateValue`), and the resolution of one aggregate call. -/

namespace Belay.Sqlite.Model

mutual
/-- The aggregate calls of an expression as written ({name}`aggregateCall`), in written order,
without the calls inside their arguments, which are SQLite's {lit}`misuse of aggregate function`.
A subquery's expressions are not parts of the expression that names it. -/
def Syntax.Expr.aggregateCalls (expression : Syntax.Expr) : List Syntax.Expr :=
  if aggregateCall expression then [expression] else match expression with
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .concatenate left right =>
    left.aggregateCalls ++ right.aggregateCalls
  | .not operand | .isNull operand _ | .negate operand | .positive operand | .cast operand _ | .collate operand _
  | .inQuery operand .. => operand.aggregateCalls
  | .call _ arguments | .caseOf arguments _ => Syntax.Expr.aggregateCallsIn arguments
  | .inList operand values _ => operand.aggregateCalls ++ Syntax.Expr.aggregateCallsIn values
  | .between operand low high _ => operand.aggregateCalls ++ low.aggregateCalls ++ high.aggregateCalls
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .qualified ..
  | .callStar _ | .exists _ | .subquery _ | .raise .. => []

/-- The aggregate calls of each expression in order ({name}`Syntax.Expr.aggregateCalls`). -/
def Syntax.Expr.aggregateCallsIn : List Syntax.Expr → List Syntax.Expr
  | [] => []
  | expression :: rest => expression.aggregateCalls ++ Syntax.Expr.aggregateCallsIn rest
end

/-- Resolve one aggregate call ({name}`aggregateCall`): {lit}`count(*)` and {lit}`count()` count the
rows, an aggregate of one or two operands resolves them with aggregates as misuse. An operand
that reads a cell of a query around the current one is {name}`RestrictionKind.outerAggregate`,
and a JSON aggregate over a value whose JSON subtype the model does not describe is
{name}`RestrictionKind.jsonSubtype`. The issue of operand {lit}`k` is at {lit}`[1, k]`. -/
def resolveAggregateCall (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) :
    Syntax.Expr → Except ValueIssue Resolved.Aggregate
  | .callStar _ | .call _ [] => .ok .countRows
  | .call name [operand] => match aggregateNamed name with
    | some aggregate => do
      let (resolved, _) ← (resolveOperand dqs scope shapes true operand).mapError (·.under [1, 0])
      if resolved.readsUnder shapes shapes.outer then throw (.restriction [] .outerAggregate)
      if (aggregate resolved).writesJson && resolved.subtypeUndescribed then throw (.restriction [1, 0] .jsonSubtype)
      .ok ((aggregate resolved).withCollation (operand.collationIn scope))
    | none => .error (.restriction [] .aggregateInExpression)
  | .call name [first, second] => match pairAggregateNamed name with
    | some aggregate => do
      let (label, _) ← (resolveOperand dqs scope shapes true first).mapError (·.under [1, 0])
      let (operand, _) ← (resolveOperand dqs scope shapes true second).mapError (·.under [1, 1])
      if (Resolved.Expr.coalesce label operand).readsUnder shapes shapes.outer then
        throw (.restriction [] .outerAggregate)
      if operand.subtypeUndescribed then throw (.restriction [1, 1] .jsonSubtype)
      .ok (aggregate label operand)
    | none => .error (.restriction [] .aggregateInExpression)
  | .call _ (_ :: _ :: _ :: _) | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier ..
  | .qualified .. | .negate _ | .positive _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic ..
  | .cast .. | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf ..
  | .concatenate .. | .raise .. => .error (.restriction [] .aggregateInExpression)

/-- Resolve {lit}`GROUP BY` term {lit}`item` of a query whose result columns are {lit}`outputs`,
with aliases {lit}`aliases` and collations {lit}`collations`: a column name, also under one
{lit}`COLLATE`, or a qualified name, with its collation; a result column number or alias, with
the column's collation; a parameter, as a constant value that names no result column (ADR 0019,
D1); an aggregate, also inside the result column that a number or an alias
names, is SQLite's {lit}`aggregate functions are not allowed in the GROUP BY clause`; any other term is {name}`RestrictionKind.groupByTerm`. -/
def resolveGroupTerm (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (aliases : List (Option Identifier))
    (outputs : List (Resolved.Output × String × Option Affinity)) (collations : List Collation) (item : Nat)
    (term : Syntax.Expr) : Except ValueIssue (Resolved.Expr × Collation) :=
  let grouped := fun (column : Nat) => match outputs[column]? with
    | some (.scalar expression, _) =>
      if expression.any (· matches .aggregateValue _) then .error (.prepare .aggregateInGroupBy)
      else .ok (expression, collations.getD column .binary)
    | some (.aggregate _, _) | none => .error (.prepare .aggregateInGroupBy)
  match term with
    | .identifier name _ => match scope.resolveName name, aliasIndex aliases name with
      | .found _ reads, _ => (scope.nameRead reads).map (·.1, term.collationIn scope) |>.mapError (·.under [4, item])
      | .missing, some column => grouped column
      | .missing, none | .ambiguous, _ =>
        (resolveOperand dqs scope shapes true term).map (·.1, term.collationIn scope) |>.mapError (·.under [4, item])
    | .callStar name | .call name [] | .call name [_] =>
      .error (if aggregateCall term then .prepare .aggregateInGroupBy else (callIssue name).under [4, item])
    | .numeric _ | .negate _ => match namedResult aliases term with
      | some (.ok column) => grouped column
      | some (.error ()) => .error (.prepare (.groupByOutOfRange (item + 1) outputs.length))
      | none => .error (.restriction [4, item] .groupByTerm)
    | .qualified .. | .parameter _ =>
      (resolveOperand dqs scope shapes true term).map (·.1, term.collationIn scope) |>.mapError (·.under [4, item])
    | .collate .. =>
      if term.collatedColumn scope then
        (resolveOperand dqs scope shapes true term).map (·.1, term.collationIn scope) |>.mapError (·.under [4, item])
      else .error (.restriction [4, item] .groupByTerm)
    | .call _ (_ :: _ :: _) | .null | .string _ | .blob _ | .currentTime _ | .positive _ | .compare ..
    | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. | .cast .. | .exists _ | .inQuery .. | .subquery _
    | .inList .. | .between .. | .caseOf .. | .concatenate .. | .raise .. =>
      .error (.restriction [4, item] .groupByTerm)

end Belay.Sqlite.Model
