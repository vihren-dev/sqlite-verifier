import Belay.Sqlite.Model.Resolution.QueryAffinity
import Belay.Sqlite.Model.Resolution.Values
import Belay.Sqlite.Model.Resolution.ExprAny

set_option doc.verso true

/-! Calls after their arguments are resolved: {lit}`COALESCE`, the JSON functions of ADR
0012, amendment 5, slices 6b and 6c, and the date and time functions of slice 6f. A call
keeps its arguments in written order. -/

namespace Belay.Sqlite.Model

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
  | "json_quote" => some .quote
  | "json_array" => some .array
  | "json_object" => some .object
  | "json_set" => some .set
  | "json_insert" => some .insert
  | "json_replace" => some .replace
  | "json_remove" => some .remove
  | "json_patch" => some .patch
  | "json_pretty" => some .pretty
  | "json_error_position" => some .errorPosition
  | "jsonb" => some .jsonb
  | "jsonb_extract" => some .jsonbExtract
  | "jsonb_array" => some .jsonbArray
  | "jsonb_object" => some .jsonbObject
  | "jsonb_set" => some .jsonbSet
  | "jsonb_insert" => some .jsonbInsert
  | "jsonb_replace" => some .jsonbReplace
  | "jsonb_remove" => some .jsonbRemove
  | "jsonb_patch" => some .jsonbPatch
  | _ => none

/-- Whether SQLite accepts the number of arguments of a JSON function: one or more for
{lit}`json_extract`, exactly two for {lit}`->` and {lit}`->>`, one or two for
{lit}`json_type`, {lit}`json_valid`, {lit}`json_array_length` and {lit}`json_pretty`, exactly one
for {lit}`json`, {lit}`json_quote` and {lit}`json_error_position`, exactly two for
{lit}`json_patch`, and any number for {lit}`json_array`, {lit}`json_object` and the edit
functions, whose own checks follow when they run; each {lit}`jsonb_*` function as its
{lit}`json_*` form. -/
def Resolved.JsonFunction.accepts : Resolved.JsonFunction → Nat → Bool
  | .extract, count | .jsonbExtract, count => count ≥ 1
  | .arrowJson, count | .arrowValue, count | .patch, count | .jsonbPatch, count => count == 2
  | .typeName, count | .valid, count | .arrayLength, count | .pretty, count => count == 1 || count == 2
  | .json, count | .quote, count | .errorPosition, count | .jsonb, count => count == 1
  | .array, _ | .object, _ | .set, _ | .insert, _ | .replace, _ | .remove, _ | .jsonbArray, _ | .jsonbObject, _
  | .jsonbSet, _ | .jsonbInsert, _ | .jsonbReplace, _ | .jsonbRemove, _ => true

/-- Whether the expression itself passes on the value of one of its arguments with its JSON
subtype: {lit}`COALESCE`, {lit}`iif`, {lit}`nullif`, {lit}`min`, {lit}`max` and a scalar subquery; its parts are not
inspected. -/
def Resolved.Expr.passesValue : Resolved.Expr → Bool
  | .coalesce .. | .scalar .iif _ | .scalar (.nullif _) _ | .scalar (.min _) _ | .scalar (.max _) _
  | .subquery _ => true
  | .scalar .typeof _ | .scalar .length _ | .scalar .octetLength _ | .scalar .abs _ | .scalar .sign _
  | .scalar .zeroblob _ | .scalar .like _ | .scalar .glob _ | .scalar .lower _ | .scalar .upper _
  | .scalar .substr _ | .scalar .instr _ | .scalar .replace _ | .scalar (.trim _) _ | .scalar .hex _
  | .scalar .unhex _ | .scalar .quote _ | .scalar .unistrQuote _ | .scalar .char _ | .scalar .unicode _
  | .scalar .unistr _ | .scalar .concat _ | .scalar .pipes _ | .scalar .concatWs _ | .scalar .round _ | .scalar .floor _
  | .scalar .ceil _ | .scalar .trunc _ | .scalar .sqrt _ | .scalar .pi _ | .scalar .degrees _
  | .scalar .radians _ | .scalar .mod _ | .scalar .printf _ | .column _ | .literal _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic ..
  | .cast .. | .json .. | .now _ | .date .. | .exists .. | .inQuery .. | .inList .. | .aggregateValue _ | .parameter _ | .counter _ => false

/-- Whether the expression itself is a scalar subquery, whose value may have the JSON subtype
of a JSON call in the subquery, which the expression does not show; its parts are not
inspected. -/
def Resolved.Expr.isSubquery : Resolved.Expr → Bool
  | .subquery _ => true
  | .column _ | .literal _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. | .cast ..
  | .coalesce .. | .json .. | .now _ | .date .. | .scalar .. | .exists .. | .inQuery .. | .inList .. | .aggregateValue _
  | .parameter _ | .counter _ => false

/-- Whether the JSON subtype of an argument is not described: the argument passes on a value
({name}`Resolved.Expr.passesValue`) and has a JSON call or a scalar subquery inside
({name}`Resolved.Expr.isSubquery`). A direct JSON call is described ({lit}`Expr.givesJson`),
and any other expression gives no subtype. -/
def Resolved.Expr.subtypeUndescribed (argument : Resolved.Expr) : Bool :=
  argument.passesValue && (argument.any Resolved.Expr.isJsonCall || argument.any Resolved.Expr.isSubquery)

/-- The arguments of a call in written order. -/
def Resolved.Arguments.toList : Resolved.Arguments → List Resolved.Expr
  | .nil => []
  | .cons head tail => head :: tail.toList

/-- A JSON call of the named function over resolved arguments, or SQLite's
{lit}`wrong number of arguments to function %s()` when the function does not accept their
number; SQLite checks the number after it resolves the arguments. An argument that the
function reads as an SQL value ({name}`Resolved.JsonFunction.valuePositions`) whose subtype is
not described ({name}`Resolved.Expr.subtypeUndescribed`) is the restriction
{lit}`json-subtype`. -/
def jsonCall (name : String) (function : Resolved.JsonFunction) (arguments : Resolved.Arguments) :
    Except ValueIssue Operand :=
  if !function.accepts arguments.length then .error (.prepare (.wrongArgumentCount name))
  else if (function.valuePositions arguments.length).any fun position =>
      (arguments.toList.getD position (.literal .null)).subtypeUndescribed then
    .error (.restriction [] .jsonSubtype)
  else .ok (.json function arguments, none)

/-- The date and time function that a folded name names, if any. -/
def dateFunctionNamed (name : String) : Option Resolved.DateFunction :=
  match normalizeIdentifier name with
  | "date" => some .date
  | "time" => some .time
  | "datetime" => some .datetime
  | "julianday" => some .julianday
  | "unixepoch" => some .unixepoch
  | "strftime" => some .strftime
  | _ => none

/-- A date and time call over resolved arguments, with the clock value 0 until the
execution sets it. SQLite accepts any number of arguments, so the call never fails: the
arguments after the time value are modifiers (slice 6g). -/
def dateCall (function : Resolved.DateFunction) (arguments : Resolved.Arguments) :
    Except ValueIssue Operand :=
  .ok (.date function arguments, none)

end Belay.Sqlite.Model
