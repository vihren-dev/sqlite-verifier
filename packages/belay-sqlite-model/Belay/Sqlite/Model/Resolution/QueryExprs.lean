import Belay.Sqlite.Model.Resolution.Values
import Belay.Sqlite.Model.Resolution.MergedNames
import Belay.Sqlite.Model.Resolution.FunctionCalls
import Belay.Sqlite.Model.Resolution.SyntaxScope
import Belay.Sqlite.Model.ExprEval
import Belay.Sqlite.Model.Resolution.ExprAny
import Belay.Sqlite.Model.ClockReads
import Belay.Sqlite.Model.Resolution.Collations
import Belay.Sqlite.Model.Resolution.SubqueryShapes

set_option doc.verso true

/-! Resolution of the expressions of a query (ADR 0012, slice 1): names become column
positions, and each comparison keeps the affinity and collation that evaluation applies. -/

namespace Belay.Sqlite.Model

mutual
/-- Resolve an expression over the sources in scope. An unqualified identifier is the
operand of its name ({name}`Scope.resolveName`, {name}`Scope.nameOperand`): one column,
or the coalesce of the columns that full joins merged; two columns that no join merged
are SQLite's {lit}`ambiguous column name: %s`. With none: a rowid name
({name}`rowidName`) is a model restriction when a source with a rowid is in scope
({name}`ScopeSource.hasRowid`), because SQLite reads the rowid; a name written in double quotes is a string literal when {lit}`dqs` is on;
an unquoted {lit}`TRUE` or {lit}`FALSE` is the integer 1 or 0; else it is SQLite's
{lit}`no such column: %s`, also for {lit}`[true]`, which only quotes. A qualified name {lit}`x.c` is column
{lit}`c` of the sources named {lit}`x` ({name}`Scope.resolveQualified`): one column, the
coalesce of merged columns, {lit}`ambiguous column name: x.c`, else
{lit}`no such column: x.c`. The operands of {lit}`AND`, {lit}`OR` and {lit}`NOT` must be
conditions. An aggregate gives {name}`aggregateIssue`. A numeric literal has the value of
{name}`queryNumeric`; unary minus of another expression is {lit}`0 - operand` and unary
plus keeps the value without its affinity, as SQLite generates them; a {lit}`CAST` has
the affinity of its type name. A call resolves its arguments first, then is {name}`callOperand`, as SQLite
reports the errors of the arguments before those of the function; {lit}`name(*)` other than
{lit}`count(*)` is {name}`starCallIssue`. The issue path of argument {lit}`k` is
{lit}`[1, k]`. A comparison compares under {name}`comparisonCollation`. {lit}`x COLLATE c`
is the resolved {lit}`x`, whose collation the expression that uses it decides; a name
{lit}`c` other than {lit}`BINARY`, {lit}`NOCASE` and {lit}`RTRIM` is
{name}`RestrictionKind.unknownCollation`. A subquery form names a subquery that resolution
resolved before ({name}`SubqueryShapes.find`), else it is {name}`RestrictionKind.subqueryHere`; a
scalar subquery has the affinity of its result column, {lit}`x IN (q)` compares under
{name}`comparisonAffinity` and {name}`inCollation`, and both read one result column
({name}`SubqueryShapes.column`). An aggregate whose arguments read a cell
of a query around the current one is {name}`RestrictionKind.outerAggregate`. {lit}`x IN (list)`
compares under the affinity and the collation of {lit}`x`, but a list of one constant value with an
explicit collation is {lit}`x = +c`, as SQLite's parser reads it; {lit}`x BETWEEN a AND b` is
{lit}`x >= a AND x <= b`; {lit}`CASE` is {lit}`iif` of its operands ({lit}`resolveCase`); and
{lit}`x || y` is the scalar function of the operator; a listed aggregate call
({name}`SubqueryShapes.aggregates`) that is no misuse names its aggregate by index; {lit}`RAISE`
outside a trigger's statements is {name}`ExprError.raiseOutsideTrigger`. -/
def resolveOperand (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (misuse : Bool) :
    Syntax.Expr → Except ValueIssue Operand
  | .identifier name quote => match scope.resolveName name with
    | .found _ reads => .ok (scope.nameOperand reads)
    | .missing =>
      if rowidName name && scope.any (·.hasRowid) then .error (.restriction [] .rowidName)
      else if quote == .double && dqs then .ok (.literal (.text name.bytes), none)
      else if quote == .none && booleanKeywordName name then
        .ok (.literal (.integer (if name.isKeyword (bytes! "true") then 1 else 0)), none)
      else .error (.prepare (.noSuchColumn name))
    | .ambiguous => .error (.prepare (.ambiguousColumn name))
  | .qualified source column => match scope.resolveQualified source column with
    | .found _ reads => .ok (scope.nameOperand reads)
    | .missing =>
      if rowidName column && scope.rowidSource source then .error (.restriction [] .rowidName)
      else .error (.prepare (.noSuchColumn ⟨source.bytes ++ [46] ++ column.bytes⟩))
    | .ambiguous => .error (.prepare (.ambiguousColumn ⟨source.bytes ++ [46] ++ column.bytes⟩))
  | .compare operator left right => do
    let a ← (resolveOperand dqs scope shapes misuse left).mapError (·.under [1])
    let b ← (resolveOperand dqs scope shapes misuse right).mapError (·.under [2])
    if truthTest operator right b.1 then
      -- x IS [NOT] TRUE is (NOT NOT x) IS [NOT] 1, and x IS [NOT] FALSE is (NOT x) IS [NOT] 1.
      let tested := if b.1.literal? == some (.integer 1) then .not (.not a.1) else .not a.1
      .ok (.compare operator none tested (.literal (.integer 1)), none)
    else .ok (.compare operator (comparisonAffinity a.2 b.2) a.1 b.1 (comparisonCollation scope left right), none)
  | .collate operand name => do
    let resolved ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    if (Collation.named? name).isNone then .error (.restriction [] .unknownCollation) else .ok resolved
  | .and left right => do
    let a ← condition [0] (resolveOperand dqs scope shapes misuse left)
    let b ← condition [1] (resolveOperand dqs scope shapes misuse right)
    .ok (.and a b, none)
  | .or left right => do
    let a ← condition [0] (resolveOperand dqs scope shapes misuse left)
    let b ← condition [1] (resolveOperand dqs scope shapes misuse right)
    .ok (.or a b, none)
  | .not operand => do
    let a ← condition [0] (resolveOperand dqs scope shapes misuse operand)
    .ok (.not a, none)
  | .isNull operand negated => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    .ok (.isNull a.1 negated, none)
  | .arithmetic operator left right => do
    let a ← (resolveOperand dqs scope shapes misuse left).mapError (·.under [1])
    let b ← (resolveOperand dqs scope shapes misuse right).mapError (·.under [2])
    .ok (.arithmetic operator a.1 b.1, none)
  | .cast operand typeName => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    let affinity := affinityOf (some typeName)
    .ok (.cast affinity a.1, some affinity)
  | .numeric text => (queryNumeric text false).map fun value => (.literal value, none)
  | .negate (.numeric text) => (queryNumeric text true).map fun value => (.literal value, none)
  | .negate operand => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    .ok (.arithmetic .subtract (.literal (.integer 0)) a.1, none)
  | .positive operand => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    .ok (a.1, none)
  | .call name arguments => do
    let resolved ← resolveArguments dqs scope shapes misuse 0 arguments
    if aggregateCall (.call name arguments) && resolved.readsUnder shapes shapes.outer then
      throw (.restriction [] .outerAggregate)
    match misuse, (Syntax.Expr.call name arguments).indexIn shapes.aggregates with
    | false, some index => .ok (.aggregateValue index, none)
    | _, _ => callOperand scope misuse name arguments resolved
  | call@(.callStar name) => match misuse, call.indexIn shapes.aggregates with
    | false, some index => .ok (.aggregateValue index, none)
    | _, _ => .error (if aggregateCall call then aggregateIssue misuse name else starCallIssue name)
  | .null => .ok (.literal .null, none)
  | .string bytes => .ok (.literal (.text bytes), none)
  | .blob bytes => .ok (.literal (.blob bytes), none)
  | .currentTime keyword => .ok (.now (timeKeywordNamed keyword), none)
  | .parameter number => .ok (.parameter number, none)
  | .exists index => match shapes.find index with
    | some _ => .ok (.exists index, none)
    | none => .error (.restriction [] .subqueryHere)
  | .subquery index => (shapes.column index).map fun shape => (.subquery index, shape.affinity)
  | .inList operand values negated => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    let resolved ← resolveArguments dqs scope shapes misuse 0 values
    match values, resolved with
    | [value], .cons element .nil =>
      if value.explicitCollation.isSome && (element.lowestRead shapes).isNone &&
          !element.any Resolved.Expr.namesSubquery && !element.readsClock then
        -- SQLite's parser reads `x IN (c)` for one constant `c` as `x = +c`.
        let compared := .compare .eq a.2 a.1 element (comparisonCollation scope operand value)
        .ok (if negated then .not compared else compared, none)
      else .ok (.inList a.1 resolved a.2 (operand.collationIn scope) negated, none)
    | _, _ => .ok (.inList a.1 resolved a.2 (operand.collationIn scope) negated, none)
  | .between operand low high negated => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    let l ← (resolveOperand dqs scope shapes misuse low).mapError (·.under [1])
    let h ← (resolveOperand dqs scope shapes misuse high).mapError (·.under [2])
    let both := Resolved.Expr.and (.compare .ge (comparisonAffinity a.2 l.2) a.1 l.1 (comparisonCollation scope operand low))
      (.compare .le (comparisonAffinity a.2 h.2) a.1 h.1 (comparisonCollation scope operand high))
    .ok (if negated then .not both else both, none)
  | .caseOf operands hasBase => do
    let arguments ← resolveCase dqs scope shapes misuse hasBase none 0 operands
    .ok (.scalar .iif arguments, none)
  | .concatenate left right => do
    let a ← (resolveOperand dqs scope shapes misuse left).mapError (·.under [0])
    let b ← (resolveOperand dqs scope shapes misuse right).mapError (·.under [1])
    .ok (.scalar .pipes (.cons a.1 (.cons b.1 .nil)), none)
  | .raise .. => .error (.prepare .raiseOutsideTrigger)
  | .inQuery operand index negated => do
    let a ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0])
    let shape ← shapes.column index
    .ok (.inQuery a.1 index (comparisonAffinity a.2 shape.affinity) (inCollation scope operand shape) negated, none)

/-- Resolve the arguments of a call in written order ({name}`resolveOperand`), from
argument {lit}`index`; the issue of argument {lit}`k` is at {lit}`[1, k]`. -/
def resolveArguments (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (misuse : Bool) (index : Nat) :
    List Syntax.Expr → Except ValueIssue Resolved.Arguments
  | [] => .ok .nil
  | argument :: rest => do
    let a ← (resolveOperand dqs scope shapes misuse argument).mapError (·.under [1, index])
    let tail ← resolveArguments dqs scope shapes misuse (index + 1) rest
    .ok (.cons a.1 tail)

/-- Resolve the operands of {lit}`CASE` from operand {lit}`index` as the arguments of {lit}`iif`,
which gives SQLite's value of {lit}`CASE`: the base expression first when {lit}`needsBase`, which
is then {lit}`base` and not an argument; each {lit}`WHEN` value that is not the last operand,
compared with the base as {lit}`=` compares them ({name}`comparisonAffinity`,
{name}`comparisonCollation`) when there is a base; every other operand as it is. The issue of
operand {lit}`k` is at {lit}`[0, k]`. -/
def resolveCase (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (misuse : Bool) (needsBase : Bool)
    (base : Option (Syntax.Expr × Operand)) (index : Nat) : List Syntax.Expr → Except ValueIssue Resolved.Arguments
  | [] => .ok .nil
  | operand :: rest => do
    let resolved ← (resolveOperand dqs scope shapes misuse operand).mapError (·.under [0, index])
    if needsBase then resolveCase dqs scope shapes misuse false (some (operand, resolved)) (index + 1) rest
    else
      let isWhen := (index - (if base.isSome then 1 else 0)) % 2 == 0 && !rest.isEmpty
      let item := match base, isWhen with
        | some (written, value), true =>
          .compare .eq (comparisonAffinity value.2 resolved.2) value.1 resolved.1 (comparisonCollation scope written operand)
        | _, _ => resolved.1
      let tail ← resolveCase dqs scope shapes misuse false base (index + 1) rest
      .ok (.cons item tail)
end

end Belay.Sqlite.Model
