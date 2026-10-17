import Belay.Sqlite.Resolution.QueryAffinity

set_option doc.verso true

/-! The calls of two or more arguments, after their arguments are resolved: {lit}`COALESCE`
and the JSON functions of ADR 0012, amendment 5, slice 6b. A call keeps its arguments in
written order; its arguments after the second come from {lit}`Syntax.Expr.more` nodes as
{lit}`Resolved.Expr.arguments`. -/

namespace Belay.Sqlite

/-- The arguments that a resolved operand stands for: the list of an
{lit}`Resolved.Expr.arguments` carrier, or the operand itself. -/
def argumentsOf : Resolved.Expr → Resolved.Arguments
  | .arguments list => list
  | expression@(.column _) | expression@(.literal _) | expression@(.compare ..) | expression@(.and ..)
  | expression@(.or ..) | expression@(.not _) | expression@(.isNull ..) | expression@(.arithmetic ..)
  | expression@(.cast ..) | expression@(.coalesce ..) | expression@(.json ..) => .cons expression .nil

/-- The resolved {lit}`Syntax.Expr.more` node of an argument and the arguments after it. -/
def moreArguments (first rest : Resolved.Expr) : Operand := (.arguments (.cons first (argumentsOf rest)), none)

/-- The number of arguments in a list. -/
def Resolved.Arguments.length : Resolved.Arguments → Nat
  | .nil => 0
  | .cons _ tail => tail.length + 1

/-- {lit}`COALESCE` of arguments in order: the first argument that is not NULL, as a chain
of {lit}`Resolved.Expr.coalesce`; NULL without arguments. -/
def coalesceOf : Resolved.Arguments → Resolved.Expr
  | .nil => .literal .null
  | .cons head .nil => head
  | .cons head tail => .coalesce head (coalesceOf tail)

/-- The JSON function that a folded name calls with the number of arguments, if any:
{lit}`json_extract` with one or more, and {lit}`->` and {lit}`->>` with exactly two. -/
def jsonFunctionNamed (name : String) (count : Nat) : Option Resolved.JsonFunction :=
  match normalizeIdentifier name with
  | "json_extract" => if count ≥ 1 then some .extract else none
  | "->" => if count == 2 then some .arrowJson else none
  | "->>" => if count == 2 then some .arrowValue else none
  | _ => none

/-- A call of two or more arguments over its resolved first operand and the rest: a
{lit}`COALESCE`, a JSON function, or the issue of {lit}`issue` for any other name. -/
def pairCall (name : String) (first rest : Resolved.Expr) (issue : ValueIssue) : Except ValueIssue Operand :=
  let arguments := Resolved.Arguments.cons first (argumentsOf rest)
  if normalizeIdentifier name == "coalesce" then .ok (coalesceOf arguments, none)
  else match jsonFunctionNamed name arguments.length with
    | some function => .ok (.json function arguments, none)
    | none => .error issue

end Belay.Sqlite
