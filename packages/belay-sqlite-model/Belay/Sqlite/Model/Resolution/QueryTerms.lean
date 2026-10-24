import Belay.Sqlite.Model.Resolution.Values
import Belay.Sqlite.Model.Resolution.QueryForm

set_option doc.verso true

/-! The terms of a {lit}`SELECT` that name a result column or a number (ADR 0012, slice 1):
integer literals, the result column that an {lit}`ORDER BY` or {lit}`GROUP BY` term names,
the {lit}`LIMIT` and {lit}`OFFSET` values and parameters, and the checks of grouped result columns that
{lit}`Queries.lean` makes. -/

namespace Belay.Sqlite.Model

/-- The integer of a numeric value, if it is one. -/
def NumericValue.integer? : NumericValue → Option Int
  | .integer value => some value
  | .real | .hexTooBig => none

/-- The value of an integer literal, possibly negated; {lean}`(none : Option Int)`
for any other expression. -/
def integerLiteral : Syntax.Expr → Option Int
  | .numeric text => (numericValue text false).integer?
  | .negate operand => match operand with
    | .numeric text => (numericValue text true).integer?
    | .null | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .negate _ | .positive _
    | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
    | .qualified .. | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf ..
    | .concatenate .. | .raise .. => none
  | .null | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .positive _ | .compare ..
  | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
  | .qualified .. | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf ..
    | .concatenate .. | .raise .. => none

/-- The index of the first result column whose alias has the folded name. -/
def aliasIndex (names : List (Option Identifier)) (name : Identifier) : Option Nat :=
  names.findIdx? fun alias => alias.any (·.sameName name)

mutual
/-- Whether an expression of an aggregate query reads only its grouping terms and its
aggregates (ADR 0018, D3): it is a grouping term, a value that reads no cell, or an expression
of such parts. A column outside the grouping terms, and a subquery, which can read one, are
bare: SQLite reads them from a row of the group that it chooses. -/
def Resolved.Expr.grouped (terms : List Resolved.Expr) (expression : Resolved.Expr) : Bool :=
  terms.contains expression || match expression with
  | .literal _ | .now _ | .aggregateValue _ | .parameter _ | .counter _ => true
  | .column _ | .exists _ | .inQuery .. | .subquery _ => false
  | .compare _ _ left right _ | .and left right | .or left right | .arithmetic _ left right | .coalesce left right =>
    left.grouped terms && right.grouped terms
  | .not operand | .isNull operand _ | .cast _ operand => operand.grouped terms
  | .json _ arguments | .date _ arguments | .scalar _ arguments => Resolved.Arguments.grouped terms arguments
  | .inList operand values .. => operand.grouped terms && Resolved.Arguments.grouped terms values

/-- Whether every argument is grouped ({name}`Resolved.Expr.grouped`). -/
def Resolved.Arguments.grouped (terms : List Resolved.Expr) : Resolved.Arguments → Bool
  | .nil => true
  | .cons head tail => head.grouped terms && Resolved.Arguments.grouped terms tail
end

/-- Whether a result column of an aggregate query is admitted by the model: an
aggregate, or a scalar that reads only the grouping terms and aggregates
({name}`Resolved.Expr.grouped`). SQLite also admits other scalars ("bare columns", whose row
it chooses); that is a model restriction. -/
def groupedOutput (terms : List Resolved.Expr) : Resolved.Output → Bool
  | .aggregate _ => true
  | .scalar expression => expression.grouped terms

/-- The result column that an {lit}`ORDER BY` or {lit}`GROUP BY` term names: an integer
{lit}`k` from 1 to the number of columns names column {lit}`k - 1`; an identifier
names the first column with that alias. {lit}`some (.error ())` is an integer out of
range; {lean}`(none : Option (Except Unit Nat))` is any other term. -/
def namedResult (names : List (Option Identifier)) : Syntax.Expr → Option (Except Unit Nat)
  | .identifier name _ => (aliasIndex names name).map .ok
  | term@.null | term@(.numeric _) | term@(.string _) | term@(.blob _) | term@(.parameter _) | term@(.currentTime _)
  | term@(.negate _) | term@(.positive _) | term@(.compare ..) | term@(.and ..)
  | term@(.or ..) | term@(.not _) | term@(.isNull ..) | term@(.callStar _) | term@(.call ..)
  | term@(.arithmetic ..) | term@(.cast ..) | term@(.qualified ..) | term@(.collate ..) | term@(.exists _)
  | term@(.inQuery ..) | term@(.subquery _) | term@(.inList ..) | term@(.between ..) | term@(.caseOf ..)
  | term@(.concatenate ..) | term@(.raise ..) =>
    (integerLiteral term).map fun (number : Int) =>
      if 1 ≤ number ∧ number ≤ (names.length : Int) then .ok (number.toNat - 1) else .error ()

/-- The number of a lone parameter; {lean}`(none : Option Nat)` for any other expression, also
for an expression that holds a parameter. -/
def Syntax.Expr.parameterNumber? : Syntax.Expr → Option Nat
  | .parameter number => some number
  | .null | .numeric _ | .string _ | .blob _ | .currentTime _ | .identifier .. | .negate _ | .positive _
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
  | .qualified .. | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf ..
  | .concatenate .. | .raise .. => none

/-- Resolve a {lit}`LIMIT` or {lit}`OFFSET` expression to its integer literal and the number of
its parameter: {lit}`(some value, none)` for an integer literal, {lit}`(none, some number)` for
a lone parameter, whose value is read when the query runs, and {lit}`(none, none)` without the
clause. Every other expression is the {lit}`windowValue` restriction. -/
def windowValue (path : List Nat) : Option Syntax.Expr → Except ValueIssue (Option Int × Option Nat)
  | none => .ok (none, none)
  | some term => match integerLiteral term, term.parameterNumber? with
    | some value, _ => .ok (some value, none)
    | none, some number => .ok (none, some number)
    | none, none => .error (.restriction path .windowValue)

/-- Whether a query is a model restriction because SQLite may skip a failing group: it
has {lit}`GROUP BY`, a {lit}`LIMIT` or {lit}`OFFSET`, and a result column that can fail
({name}`Resolved.Output.canFail`). SQLite finalizes the groups in an order that the
model does not describe and stops at the window, so it may never compute a group
whose {lit}`SUM` overflows. -/
def windowSkipsFailure (groupBy : List Syntax.Expr) (limit offset : Option Syntax.Expr)
    (outputs : List Resolved.Output) : Bool :=
  !groupBy.isEmpty && (limit.isSome || offset.isSome) && outputs.any Resolved.Output.canFail

end Belay.Sqlite.Model
