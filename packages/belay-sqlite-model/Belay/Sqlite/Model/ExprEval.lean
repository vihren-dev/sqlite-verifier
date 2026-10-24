import Belay.Sqlite.Model.Truth
import Belay.Sqlite.Model.Date.Functions

set_option doc.verso true

/-! The value of an expression over one row, with its fault (ADR 0013, D2). SQLite
evaluates an expression lazily and folds some of it away (checked on native SQLite
3.51.0): it short-circuits {lit}`AND`, {lit}`OR` and {lit}`COALESCE`, and folds
{lit}`X AND 0` to 0 without evaluating {lit}`X`. The model evaluates every part and
records whether a JSON function of the expression fails: {lit}`must` when SQLite certainly
reports it, {lit}`may` when SQLite may skip it or the model does not describe it, and
{lit}`none` when no call fails. -/

namespace Belay.Sqlite.Model.Resolved

/-- {lit}`x IN (q)` over the value of {lit}`x` and the first values of the rows of {lit}`q`, as
SQLite 3.51.0 computes it: an empty subquery gives 0 ({lit}`NOT IN`: 1), also for NULL; else a
NULL operand gives NULL; a value that compares equal under the affinity and the collation
({name}`comparisonOperands`) gives 1 ({lit}`NOT IN`: 0); else a NULL among the values gives NULL;
else 0 ({lit}`NOT IN`: 1). -/
def inValue (affinity : Option Affinity) (collation : Collation) (negated : Bool) (value : Value)
    (candidates : List Value) : Value :=
  if candidates.isEmpty then truth negated
  else if value.isNull then .null
  else if candidates.any (fun candidate =>
      let (a, b) := comparisonOperands affinity value candidate
      !b.isNull && collation.compare a b == .eq) then truth (!negated)
  else if candidates.any (·.isNull) then .null
  else truth negated

mutual
/-- The value of an expression over the cells of one row, in column order, with its
{name}`Fault`. A column past the end of the row reads as NULL. {lit}`AND` is false when an
operand is false, else NULL when an operand is NULL, else true; {lit}`OR` is the dual;
{lit}`NOT` keeps NULL; a comparison applies its affinity first
({name}`comparisonOperands`). Arithmetic and {lit}`CAST` follow {name}`ArithmeticOperator.apply`
and {name}`castValue`; {lit}`COALESCE` gives its first operand unless that is NULL. A JSON
function gives the value of {name}`Json.apply` over the values of its arguments, each with
whether it has the JSON subtype ({lit}`Arguments.givesJson`), and NULL with
{name}`Fault.ofJson` when it fails. The fault of {lit}`AND`, {lit}`OR` and
{lit}`COALESCE` is softened ({name}`Fault.soften`), because SQLite may skip an operand; every
other expression joins the faults of its parts ({name}`Fault.join`). {lit}`context.clock` is the
statement's clock value in Julian-day milliseconds ({name}`EvalContext`): a time keyword is its text at the clock
value ({lit}`TimeKeyword.value`), and a date and time function gives
{lit}`DateFunction.value` at the clock value. A scalar function of ADR 0015 gives
{name}`ScalarFunction.apply` over its argument values, and NULL with {name}`Fault.ofFunction`
when it fails; {lit}`iif` gives {name}`iifValue`, and only its first argument is certain
to run, so the faults of the others are softened. A subquery form reads the results of its
subquery for the row ({name}`EvalContext`), with the subquery's fault: {lit}`EXISTS` is 1 when
the subquery gives a row, a scalar subquery the first value of its first row or NULL, and
{lit}`IN` gives {name}`inValue`, also for a list, whose values SQLite may skip once one matches,
so their faults are softened; a scalar subquery or {lit}`IN` whose rows SQLite's plan can
change ({name}`SubqueryRun.firstCertain`, {name}`SubqueryRun.rowsCertain`) is
{lean}`Fault.may`. -/
def Expr.evaluate (context : EvalContext) (row : List Value) : Expr → Value × Fault
  | .column position => (row.getD position .null, .none)
  | .literal value => (value, .none)
  | .compare operator affinity left right collation =>
    let (a, first) := left.evaluate context row
    let (b, second) := right.evaluate context row
    let (a, b) := comparisonOperands affinity a b
    (operator.apply a b collation, first.join second)
  | .and left right =>
    let (a, first) := left.evaluate context row
    let (b, second) := right.evaluate context row
    (Value.and a b, (first.join second).soften)
  | .or left right =>
    let (a, first) := left.evaluate context row
    let (b, second) := right.evaluate context row
    (Value.or a b, (first.join second).soften)
  | .not operand =>
    let (value, fault) := operand.evaluate context row
    (Value.not value, fault)
  | .isNull operand negated =>
    let (value, fault) := operand.evaluate context row
    (truth (value.isNull != negated), fault)
  | .arithmetic operator left right =>
    let (a, first) := left.evaluate context row
    let (b, second) := right.evaluate context row
    (operator.apply a b, first.join second)
  | .cast affinity operand =>
    let (value, fault) := operand.evaluate context row
    (castValue affinity value, fault)
  | .coalesce first rest =>
    let (value, fault) := first.evaluate context row
    let (other, later) := rest.evaluate context row
    (if value.isNull then other else value, (fault.join later).soften)
  | .json function arguments =>
    let (values, fault) := arguments.evaluate context row
    let result := Json.apply function (values.zip (arguments.givesJson context row))
    (match result with
      | .ok value => value
      | .error _ => .null, fault.join (Fault.ofJson result))
  | .date function arguments =>
    let (values, fault) := arguments.evaluate context row
    (function.value context.clock values, fault)
  | .now keyword => (keyword.value context.clock, .none)
  | .parameter number => (parameterValue context.parameters number, .none)
  | .counter kind => (((context.counters.read kind).map Value.integer).getD .null, .none)
  | .scalar .iif .nil => (.null, .none)
  | .scalar .iif (.cons condition rest) =>
    let (value, fault) := condition.evaluate context row
    let (values, later) := rest.evaluate context row
    (iifValue (value :: values), fault.join later.soften)
  | .scalar function arguments =>
    let (values, fault) := arguments.evaluate context row
    let result := function.apply values
    (match result with
      | .ok value => value
      | .error _ => .null, fault.join (Fault.ofFunction result))
  | .exists index =>
    let run := context.subqueries index row
    (truth !run.rows.isEmpty, run.fault)
  | .inQuery operand index affinity collation negated =>
    let (value, fault) := operand.evaluate context row
    let run := context.subqueries index row
    (inValue affinity collation negated value (run.rows.filterMap List.head?),
      fault.join (if run.rowsCertain then run.fault else .may))
  | .inList operand values affinity collation negated =>
    let (value, fault) := operand.evaluate context row
    let (candidates, later) := values.evaluate context row
    (inValue affinity collation negated value candidates, fault.join later.soften)
  | .aggregateValue index => (context.aggregates.getD index .null, .none)
  | .subquery index =>
    let run := context.subqueries index row
    ((run.rows.head?.bind List.head?).getD .null, if run.firstCertain then run.fault else .may)

/-- The values of the arguments of a call over one row, in written order, with the
joined fault of the arguments. -/
def Arguments.evaluate (context : EvalContext) (row : List Value) : Arguments → List Value × Fault
  | .nil => ([], .none)
  | .cons head tail =>
    let (value, fault) := head.evaluate context row
    let (values, later) := tail.evaluate context row
    (value :: values, fault.join later)

/-- Whether the value of an expression over one row has SQLite's JSON subtype, which makes a
JSON function read a text argument as JSON: a call of a function that always gives it
({name}`JsonFunction.givesJson`), {lit}`json_extract` with two or more paths, and with one path
when it selects an array or an object ({name}`Json.extractGivesJson`). Any other expression
gives false; resolution refuses an argument whose subtype the model does not describe
(restriction {lit}`json-subtype`). -/
def Expr.givesJson (context : EvalContext) (row : List Value) : Expr → Bool
  | .json .extract (.cons json (.cons path .nil)) =>
    Json.extractGivesJson (json.evaluate context row).1 (path.evaluate context row).1
  | .json .extract (.cons _ (.cons _ (.cons _ _))) => true
  | .json function _ => function.givesJson
  | .column _ | .literal _ | .compare _ _ _ _ _ | .and _ _ | .or _ _ | .not _ | .isNull _ _
  | .arithmetic _ _ _ | .cast _ _ | .coalesce _ _ | .now _ | .date _ _ | .scalar _ _ | .exists _ | .inList .. | .aggregateValue _
  | .inQuery _ _ _ _ _ | .subquery _ | .parameter _ | .counter _ => false

/-- Whether each argument of a call over one row has SQLite's JSON subtype
({lit}`Expr.givesJson`), in written order. -/
def Arguments.givesJson (context : EvalContext) (row : List Value) : Arguments → List Bool
  | .nil => []
  | .cons head tail => head.givesJson context row :: tail.givesJson context row
end

/-- The value of an expression over one row in a context: the value of
{name}`Expr.evaluate`. -/
def Expr.eval (context : EvalContext) (row : List Value) (expression : Expr) : Value := (expression.evaluate context row).1

/-- The values of the arguments of a call over one row in a context: the values of
{name}`Arguments.evaluate`. -/
def Arguments.eval (context : EvalContext) (row : List Value) (arguments : Arguments) : List Value :=
  (arguments.evaluate context row).1

/-- Whether the fault of the expression over the row in the context is not
{lean}`Fault.none`. -/
def Expr.mayFailOn (context : EvalContext) (row : List Value) (expression : Expr) : Bool :=
  (expression.evaluate context row).2 != .none

/-- Whether the fault of the expression over the row in the context is
{lean}`Fault.must`. -/
def Expr.mustFailOn (context : EvalContext) (row : List Value) (expression : Expr) : Bool :=
  (expression.evaluate context row).2 == .must

end Belay.Sqlite.Model.Resolved
