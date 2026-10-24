import Belay.Sqlite.Model.Resolution.QueryExprs

set_option doc.verso true

/-! Where SQLite refuses a function that is not deterministic (ADR 0024, D5). SQLite gives
{lit}`non-deterministic functions prohibited in ...` while it walks the names of a generated
column, an index expression or the filter of a partial index, for {lit}`changes()`,
{lit}`total_changes()`, {lit}`last_insert_rowid()`, {lit}`random()` and {lit}`randomblob(n)`,
as for the time keywords. Which error of the walk SQLite reports depends on the order of the walk:
an error replaces an earlier message, and some errors stop the walk (checked natively, 3.51.0).
So {lit}`count(a) + changes()` gives the non-deterministic error and {lit}`changes() + count(a)` the
misuse, {lit}`nosuch + changes()` gives {lit}`no such column`, and {lit}`abs(nosuch) + changes()`
gives the non-deterministic error. The model gives the error of the call where it is the only
error of the walk, and the restriction {lit}`nondeterministicErrorOrder` for an expression with
such a call and another error. -/

namespace Belay.Sqlite.Model

/-- The number of arguments that makes a call of the function a call that SQLite refuses in a
schema position, or none for another function: none for the name {lit}`changes`,
{lit}`total_changes`, {lit}`last_insert_rowid` and {lit}`random`, one for {lit}`randomblob`.
A call with another number of arguments is a prepare error of its own. -/
def nondeterministicArity (name : String) : Option Nat :=
  match normalizeIdentifier name with
  | "changes" | "total_changes" | "last_insert_rowid" | "random" => some 0
  | "randomblob" => some 1
  | _ => none

namespace Syntax

/-- Whether the call is one that SQLite refuses in a schema position
({name}`Belay.Sqlite.Model.nondeterministicArity`), with its number of arguments. -/
def Expr.isNondeterministicCall (name : String) (arguments : List Expr) : Bool :=
  nondeterministicArity name == some arguments.length

mutual
/-- Whether an expression has a call of {name}`Expr.isNondeterministicCall` anywhere in it. -/
def Expr.hasNondeterministicCall : Expr → Bool
  | .call name arguments => Expr.isNondeterministicCall name arguments || Expr.anyNondeterministicCall arguments
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .concatenate left right =>
    left.hasNondeterministicCall || right.hasNondeterministicCall
  | .not operand | .isNull operand _ | .negate operand | .positive operand | .cast operand _
  | .collate operand _ | .inQuery operand .. => operand.hasNondeterministicCall
  | .caseOf arguments _ => Expr.anyNondeterministicCall arguments
  | .inList operand values _ => operand.hasNondeterministicCall || Expr.anyNondeterministicCall values
  | .between operand low high _ =>
    operand.hasNondeterministicCall || low.hasNondeterministicCall || high.hasNondeterministicCall
  | .raise _ (some message) => message.hasNondeterministicCall
  | .raise _ none | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier ..
  | .qualified .. | .callStar _ | .exists _ | .subquery _ => false

/-- Whether some expression of the list has such a call ({name}`Expr.hasNondeterministicCall`). -/
def Expr.anyNondeterministicCall : List Expr → Bool
  | [] => false
  | expression :: rest => expression.hasNondeterministicCall || Expr.anyNondeterministicCall rest
end

mutual
/-- The expression with each call of {name}`Expr.isNondeterministicCall` replaced by what the
call leaves to resolve: {lit}`NULL` for a call without arguments, and the argument of
{lit}`randomblob`. The result has the other errors of the walk of names and no call that SQLite
refuses. -/
def Expr.withoutNondeterministicCalls : Expr → Expr
  | .call name arguments =>
    if Expr.isNondeterministicCall name arguments then
      match arguments with
      | [argument] => argument.withoutNondeterministicCalls
      | _ => .null
    else .call name (Expr.listWithoutNondeterministicCalls arguments)
  | .compare operator left right =>
    .compare operator left.withoutNondeterministicCalls right.withoutNondeterministicCalls
  | .and left right => .and left.withoutNondeterministicCalls right.withoutNondeterministicCalls
  | .or left right => .or left.withoutNondeterministicCalls right.withoutNondeterministicCalls
  | .arithmetic operator left right =>
    .arithmetic operator left.withoutNondeterministicCalls right.withoutNondeterministicCalls
  | .concatenate left right => .concatenate left.withoutNondeterministicCalls right.withoutNondeterministicCalls
  | .not operand => .not operand.withoutNondeterministicCalls
  | .isNull operand negated => .isNull operand.withoutNondeterministicCalls negated
  | .negate operand => .negate operand.withoutNondeterministicCalls
  | .positive operand => .positive operand.withoutNondeterministicCalls
  | .cast operand typeName => .cast operand.withoutNondeterministicCalls typeName
  | .collate operand name => .collate operand.withoutNondeterministicCalls name
  | .inQuery operand index negated => .inQuery operand.withoutNondeterministicCalls index negated
  | .caseOf arguments hasBase => .caseOf (Expr.listWithoutNondeterministicCalls arguments) hasBase
  | .inList operand values negated =>
    .inList operand.withoutNondeterministicCalls (Expr.listWithoutNondeterministicCalls values) negated
  | .between operand low high negated =>
    .between operand.withoutNondeterministicCalls low.withoutNondeterministicCalls
      high.withoutNondeterministicCalls negated
  | .raise kind (some message) => .raise kind (some message.withoutNondeterministicCalls)
  | expression@(.raise _ none) | expression@.null | expression@(.numeric _) | expression@(.string _)
  | expression@(.blob _) | expression@(.parameter _) | expression@(.currentTime _) | expression@(.identifier ..)
  | expression@(.qualified ..) | expression@(.callStar _) | expression@(.exists _) | expression@(.subquery _) =>
    expression

/-- Each expression of the list without such calls ({name}`Expr.withoutNondeterministicCalls`). -/
def Expr.listWithoutNondeterministicCalls : List Expr → List Expr
  | [] => []
  | expression :: rest => expression.withoutNondeterministicCalls :: Expr.listWithoutNondeterministicCalls rest
end

end Syntax

/-- SQLite's error where a function that is not deterministic is prohibited: nothing for an
expression without such a call, whose resolution reports its own errors. Else resolve the
expression without the calls ({name}`Syntax.Expr.withoutNondeterministicCalls`): when that finds no
error, the error of the call; when it finds a restriction, that restriction; and when it finds
a prepare error, the restriction {name}`RestrictionKind.nondeterministicErrorOrder`, because
which message SQLite keeps depends on the order of the walk, also for a missing column. For example,
{lit}`changes()` alone gives the error, and {lit}`nosuch + changes()` the restriction. -/
def prohibitNondeterministic (dqs : Bool) (scope : Scope) (error : ExprError) (expression : Syntax.Expr) :
    Except ValueIssue Unit :=
  if !expression.hasNondeterministicCall then pure ()
  else match resolveOperand dqs scope {} true expression.withoutNondeterministicCalls with
    | .ok _ => throw (.prepare error)
    | .error issue@(.restriction ..) => throw issue
    | .error (.prepare _) => throw (.restriction [] .nondeterministicErrorOrder)

end Belay.Sqlite.Model
