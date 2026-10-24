import Belay.Sqlite.Model.Resolution.ExprForms
import Belay.Sqlite.Model.Resolution.FunctionCatalog
import Belay.Sqlite.Model.Resolution.Collations
import Belay.Sqlite.Model.NumberConvert

set_option doc.verso true

/-! The resolution of a function call after its arguments resolved (ADR 0015, D1 and D2), in
the order of SQLite 3.51.0's {lit}`resolveExprStep`: the errors of the arguments come first,
then the name and the number of arguments against the catalog
({name}`Belay.Sqlite.Model.builtinFunction?`),
then an aggregate where only a row value can be, then the function. -/

namespace Belay.Sqlite.Model

/-- Whether a numeric literal is a REAL token of SQLite's tokenizer: it has a point or an
exponent and is no hexadecimal integer. -/
def realToken (text : String) : Bool :=
  let bytes := text.toUTF8.toList
  !(bytes.take 2 == [48, 120] || bytes.take 2 == [48, 88]) && bytes.any fun byte => byte == 46 || byte == 101 || byte == 69

/-- Whether the second argument of {lit}`likelihood` is what SQLite accepts
({lit}`exprProbability`): a REAL literal of at most 1.0. A sign, an integer or text is not. -/
def likelihoodConstant : Syntax.Expr → Bool
  | .numeric text => realToken text && (atof text.toUTF8.toList).1 ≤ 1.0
  | .null | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .qualified .. | .negate _ | .positive _
  | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .callStar _ | .call .. | .arithmetic .. | .cast ..
  | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf .. | .concatenate .. | .raise .. => false

/-- The collation of a call that compares its arguments ({lit}`SQLITE_FUNC_NEEDCOLL`): the
explicit or column collation of the left-most argument that has one, else {lit}`BINARY`. A
column without {lit}`COLLATE` has {lit}`BINARY`, so it decides. -/
def functionCollation (scope : Scope) (arguments : List Syntax.Expr) : Collation :=
  (arguments.findSome? fun argument => argument.explicitCollation <|> argument.columnCollation scope).getD .binary

/-- The first resolved argument, or NULL. -/
def Resolved.Arguments.first : Resolved.Arguments → Resolved.Expr
  | .nil => .literal .null
  | .cons head _ => head

/-- A call of a scalar function of the catalog over its resolved arguments, with no
affinity, as SQLite gives a function result none: {lit}`COALESCE` and {lit}`ifnull` are a
chain of {name}`Resolved.Expr.coalesce`; {lit}`likely`, {lit}`unlikely` and {lit}`likelihood`
are their first argument, and {lit}`likelihood` needs {name}`likelihoodConstant`; a JSON or
date and time function keeps its form; {lit}`changes`, {lit}`total_changes` and
{lit}`last_insert_rowid` are {name}`Resolved.Expr.counter` (ADR 0024, D2); the functions of ADR 0015 are
{name}`Resolved.Expr.scalar`; any other function is {name}`unmodeledFunction`. -/
def scalarCall (scope : Scope) (name : String) (written : List Syntax.Expr) (arguments : Resolved.Arguments) :
    Except ValueIssue Operand :=
  let scalar := fun (function : Resolved.ScalarFunction) => Except.ok (Resolved.Expr.scalar function arguments, none)
  match normalizeIdentifier name with
  | "coalesce" | "ifnull" => .ok (coalesceOf arguments, none)
  | "likely" | "unlikely" => .ok (arguments.first, none)
  | "likelihood" =>
    if (written[1]?.map likelihoodConstant).getD false then .ok (arguments.first, none)
    else .error (.prepare .likelihoodArgument)
  | "changes" => .ok (.counter .changes, none)
  | "total_changes" => .ok (.counter .totalChanges, none)
  | "last_insert_rowid" => .ok (.counter .lastInsertRowid, none)
  | "typeof" => scalar .typeof
  | "length" => scalar .length
  | "octet_length" => scalar .octetLength
  | "abs" => scalar .abs
  | "sign" => scalar .sign
  | "zeroblob" => scalar .zeroblob
  | "iif" | "if" => scalar .iif
  | "nullif" => scalar (.nullif (functionCollation scope written))
  | "min" => scalar (.min (functionCollation scope written))
  | "max" => scalar (.max (functionCollation scope written))
  | "like" => scalar .like
  | "glob" => scalar .glob
  | "lower" => scalar .lower
  | "upper" => scalar .upper
  | "substr" | "substring" => scalar .substr
  | "instr" => scalar .instr
  | "replace" => scalar .replace
  | "trim" => scalar (.trim .both)
  | "ltrim" => scalar (.trim .leading)
  | "rtrim" => scalar (.trim .trailing)
  | "hex" => scalar .hex
  | "unhex" => scalar .unhex
  | "quote" => scalar .quote
  | "unistr_quote" => scalar .unistrQuote
  | "char" => scalar .char
  | "unicode" => scalar .unicode
  | "unistr" => scalar .unistr
  | "concat" => scalar .concat
  | "concat_ws" => scalar .concatWs
  | "round" => scalar .round
  | "floor" => scalar .floor
  | "ceil" | "ceiling" => scalar .ceil
  | "trunc" => scalar .trunc
  | "sqrt" => scalar .sqrt
  | "pi" => scalar .pi
  | "degrees" => scalar .degrees
  | "radians" => scalar .radians
  | "mod" => scalar .mod
  | "printf" | "format" => scalar .printf
  | _ => match jsonFunctionNamed name, dateFunctionNamed name with
    | some function, _ => jsonCall name function arguments
    | none, some function => dateCall function arguments
    | none, none => .error unmodeledFunction

/-- A call over its resolved arguments ({lit}`resolveExprStep` after the arguments): a name
that names no function is {name}`ExprError.noSuchFunction`; a number of arguments that no
form accepts is {name}`ExprError.wrongArgumentCount`, with the name as written; an aggregate
call is {name}`aggregateIssue` for the aggregates of the model and, outside {lit}`misuse`,
{name}`unmodeledFunction` for the others; a window function is {name}`unmodeledFunction`;
else {name}`scalarCall`. For example, {lit}`nosuch(1)` is {lit}`no such function: nosuch`. -/
def callOperand (scope : Scope) (misuse : Bool) (name : String) (written : List Syntax.Expr)
    (arguments : Resolved.Arguments) : Except ValueIssue Operand :=
  match builtinFunction? (normalizeIdentifier name) with
  | none => .error (.prepare (.noSuchFunction name))
  | some function =>
    if !function.accepts written.length then .error (.prepare (.wrongArgumentCount name))
    else if function.isAggregateCall written.length then
      .error (if misuse || (aggregateNamed name).isSome || (pairAggregateNamed name).isSome then aggregateIssue misuse name
        else unmodeledFunction)
    else if function.scalar.isNone then .error unmodeledFunction
    else scalarCall scope name written arguments

/-- The issue of {lit}`name(*)` other than {lit}`count(*)`: {name}`ExprError.noSuchFunction` for
a name that names no function, else {name}`ExprError.wrongArgumentCount`, as SQLite reports. -/
def starCallIssue (name : String) : ValueIssue :=
  match builtinFunction? (normalizeIdentifier name) with
  | none => .prepare (.noSuchFunction name)
  | some _ => .prepare (.wrongArgumentCount name)

end Belay.Sqlite.Model
