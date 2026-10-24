import Belay.Sqlite.Model.SimpleStatementResolution
import Belay.Sqlite.Model.StatementCalm
import Belay.Sqlite.Model.ExprAnyLaws

set_option doc.verso true

/-! The resolution of {lit}`SELECT e` and {lit}`SELECT e WHERE c` without {lit}`FROM` (ADR 0017, S4), the query
form of a value that needs no table. A scalar result column, including a scalar function call,
resolves to the simple query without source. The non-call convenience law derives that column
from operand resolution. -/

namespace Belay.Sqlite.Model

/-- Whether an expression is a function call, {lit}`f(*)` or {lit}`f(x, ...)`. The result column of an aggregate
function is no scalar, so the operand-based convenience laws exclude calls; the column-resolution
primitive also covers scalar calls. -/
def Syntax.Expr.isCall : Syntax.Expr → Bool
  | .callStar _ | .call .. => true
  | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _ | .identifier .. | .qualified ..
  | .negate _ | .positive _ | .compare .. | .and .. | .or .. | .not _ | .isNull .. | .arithmetic .. | .cast ..
  | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList .. | .between .. | .caseOf .. | .concatenate ..
  | .raise .. => false

/-- A result column that is an expression other than a function call, without an alias, resolves in any scope to
the scalar column of the resolved expression, named by the defined name of the expression or else by its text,
with the affinity of the expression, when the expression resolves as an operand that is no condition. Proof
sketch: unfold {name}`resolveResultColumn`; every other form of expression takes the last branch. -/
theorem resolveColumns_scalar (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (value : Syntax.Expr) (text : String)
    (expression : Resolved.Expr) (affinity : Option Affinity) (notCall : value.isCall = false)
    (operand : resolveOperand dqs scope shapes false value = .ok (expression, affinity)) :
    resolveAll (resolveResultColumn dqs scope shapes) [.expression value none text] =
      .ok [[(.scalar expression, (definedName scope value).getD text, affinity)]] := by
  cases value <;> simp_all [Syntax.Expr.isCall, resolveAll, resolveAllFrom, resolveResultColumn, Bind.bind, Except.bind,
    Pure.pure, Except.pure, Except.mapError]

/-- For every no-FROM SELECT with no aggregate calls whose result column resolves to one
scalar expression and whose filter resolves, resolution gives the simple query and leaves the
state unchanged, provided no fallible call consumes an aggregate value. Scalar calls are
permitted. Proof sketch: specialize {name}`resolveStatement_select_simple` to the empty scope. -/
theorem resolveStatement_selectNoFrom_columns (context : ResolveContext) (state : ResolveState)
    (value : Syntax.Expr) (text name : String) (filter : Option Syntax.Expr)
    (expression : Resolved.Expr) (affinity : Option Affinity) (condition : Option Resolved.Expr)
    (noAggregate : value.aggregateCalls.isEmpty = true)
    (columns : resolveAll (resolveResultColumn context.profile.dqsDml [] { later := [] })
      [.expression value none text] = .ok [[(.scalar expression, name, affinity)]])
    (noFeed : expression.any (fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false)
    (resolves : FilterResolves context.profile.dqsDml [] [] filter condition) :
    resolveStatement context state (.select [.expression value none text] none [] filter [] [] none none [] none false none) =
      .ok (.query (Resolved.Query.simple [] condition [.scalar expression] [name]) [], state) := by
  have simple : (Syntax.Subquery.mk [.expression value none text] none [] filter [] [] none none none none false none).Simple :=
    ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, by simpa using noAggregate⟩
  have result := resolveStatement_select_simple context state
    (Syntax.Subquery.mk [.expression value none text] none [] filter [] [] none none none none false none)
    simple rfl [] [] _ condition [] (resolveSources_none state.catalog) (by simp [starIssue]) columns
    (by simpa [resultAliases] using resolves) (resolvePendingSources_nil _ _) (by
      simp only [List.flatten_cons, List.flatten_nil, List.append_nil, List.filterMap_cons, List.filterMap_nil,
        List.any_cons, List.any_nil, Bool.or_false]
      apply Eq.trans _ noFeed
      congr 1)
  simpa using result

/-- For every statement {lit}`SELECT e` (or {lit}`SELECT e WHERE c`) without {lit}`FROM`, where {lit}`e` is no
function call and has no aggregate call inside, and resolves in the empty scope to an expression without a fallible call, and the condition resolves in
the empty scope to a condition ({name}`FilterResolves`), resolution gives the simple query without source, with that
condition and the one scalar column of the expression, and leaves the state as it is. Proof sketch:
{name}`resolveStatement_select_simple` with the empty source of {name}`resolveSources_none`, the column of
{name}`resolveColumns_scalar`, and no aggregate value below a fallible call ({name}`Resolved.Expr.any_and_eq_false`). -/
theorem resolveStatement_selectNoFrom (context : ResolveContext) (state : ResolveState) (value : Syntax.Expr)
    (text : String) (filter : Option Syntax.Expr) (expression : Resolved.Expr) (affinity : Option Affinity)
    (condition : Option Resolved.Expr) (notCall : value.isCall = false)
    (noAggregate : value.aggregateCalls.isEmpty = true)
    (operand : resolveOperand context.profile.dqsDml [] { later := [] } false value = .ok (expression, affinity))
    (plain : expression.any Resolved.Expr.isFallibleCall = false)
    (resolves : FilterResolves context.profile.dqsDml [] [] filter condition) :
    resolveStatement context state (.select [.expression value none text] none [] filter [] [] none none [] none false none) =
      .ok (.query (Resolved.Query.simple [] condition [.scalar expression] [(definedName [] value).getD text]) [], state) := by
  exact resolveStatement_selectNoFrom_columns context state value text _ filter expression affinity condition
    noAggregate (resolveColumns_scalar context.profile.dqsDml [] { later := [] } value text expression affinity notCall operand)
    (by simpa [Resolved.Expr.isFallibleCall] using Resolved.Expr.any_and_eq_false _ _ expression plain) resolves

end Belay.Sqlite.Model
