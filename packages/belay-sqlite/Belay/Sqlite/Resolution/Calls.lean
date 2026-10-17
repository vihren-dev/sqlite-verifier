import Belay.Sqlite.Resolution.QueryAffinity
import Belay.Sqlite.Resolution.Values

set_option doc.verso true

/-! The calls of two or more arguments, after their arguments are resolved: {lit}`COALESCE`
and the JSON functions of ADR 0012, amendment 5, slices 6b and 6c. A call keeps its arguments in
written order; its arguments after the second come from {lit}`Syntax.Expr.more` nodes as
{lit}`Resolved.Expr.arguments`. -/

namespace Belay.Sqlite

/-- The arguments that a resolved operand stands for: the list of an
{lit}`Resolved.Expr.arguments` carrier, or the operand itself. -/
def argumentsOf : Resolved.Expr → Resolved.Arguments
  | .arguments list => list
  | expression@(.column _) | expression@(.literal _) | expression@(.compare ..) | expression@(.and ..)
  | expression@(.or ..) | expression@(.not _) | expression@(.isNull ..) | expression@(.arithmetic ..)
  | expression@(.cast ..) | expression@(.coalesce ..) | expression@(.json ..) | expression@(.now _) =>
    .cons expression .nil

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

/-- The JSON function that a folded name names, if any. -/
def jsonFunctionNamed (name : String) : Option Resolved.JsonFunction :=
  match normalizeIdentifier name with
  | "json_extract" => some .extract
  | "->" => some .arrowJson
  | "->>" => some .arrowValue
  | "json_type" => some .typeName
  | "json_valid" => some .valid
  | "json_array_length" => some .arrayLength
  | "json" => some .json
  | _ => none

/-- Whether SQLite accepts the number of arguments of a JSON function: one or more for
{lit}`json_extract`, exactly two for {lit}`->` and {lit}`->>`, one or two for
{lit}`json_type`, {lit}`json_valid` and {lit}`json_array_length`, and exactly one for
{lit}`json`. -/
def Resolved.JsonFunction.accepts : Resolved.JsonFunction → Nat → Bool
  | .extract, count => count ≥ 1
  | .arrowJson, count | .arrowValue, count => count == 2
  | .typeName, count | .valid, count | .arrayLength, count => count == 1 || count == 2
  | .json, count => count == 1

/-- A JSON call of the named function over resolved arguments, or SQLite's
{lit}`wrong number of arguments to function %s()` when the function does not accept their
number; SQLite checks the number after it resolves the arguments. -/
def jsonCall (name : String) (function : Resolved.JsonFunction) (arguments : Resolved.Arguments) :
    Except ValueIssue Operand :=
  if function.accepts arguments.length then .ok (.json function arguments, none)
  else .error (.prepare (.wrongArgumentCount name))

/-- A call of two or more arguments over its resolved first operand and the rest: a
{lit}`COALESCE`, a JSON function ({name}`jsonCall`), or the issue of {lit}`issue` for any
other name. -/
def pairCall (name : String) (first rest : Resolved.Expr) (issue : ValueIssue) : Except ValueIssue Operand :=
  let arguments := Resolved.Arguments.cons first (argumentsOf rest)
  if normalizeIdentifier name == "coalesce" then .ok (coalesceOf arguments, none)
  else match jsonFunctionNamed name with
    | some function => jsonCall name function arguments
    | none => .error issue

end Belay.Sqlite
