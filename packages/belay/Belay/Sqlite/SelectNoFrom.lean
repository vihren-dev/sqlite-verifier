import Belay.Sqlite.QueryBridge
import Belay.Sqlite.Model

set_option doc.verso true

/-! The query form {lit}`SELECT e` and {lit}`SELECT e WHERE c` without {lit}`FROM` over every database (ADR 0017, S4):
a value that needs no table. When {lit}`e` is no function call, has no aggregate call inside, and resolves to a calm
expression, and the condition resolves to a calm condition, the claims {lit}`Holds` and {lit}`Empty` of the query say
whether the condition is true, and {lit}`Fails` does not hold. Without {lit}`WHERE`, {lit}`Holds` holds for every
database. -/

namespace Belay.Sqlite

open Belay.Sqlite.Model

/-- For every script whose first statement is {lit}`SELECT e` (or {lit}`SELECT e WHERE c`) without {lit}`FROM`, where
{lit}`e` is no function call, has no aggregate call inside, and resolves in the empty scope to an expression
without a fallible call, and the condition resolves to a condition, the output of the script is the output of the
step of the simple query without source. Proof sketch: {name}`Script.outputOn_query` with the resolution of
{name}`resolveStatement_selectNoFrom`. -/
theorem Script.outputOn_selectNoFrom
    {script : Script} {db : Database} {value : Syntax.Expr} {text : String}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {expression : Resolved.Expr} {affinity : Option Affinity} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression value none text] none [] filter [] [] none none []
      none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (operand : resolveOperand runContext.profile.dqsDml [] { later := [] } false value = .ok (expression, affinity))
    (resolves : FilterResolves runContext.profile.dqsDml [] [] filter condition)
    (plain : expression.any Resolved.Expr.isFallibleCall = false) :
    script.outputOn db = some (resolvedStepOutput none 0 db.raw.connection parameters
      (.query (Resolved.Query.simple [] condition [.scalar expression] [(definedName [] value).getD text]) [])) :=
  Script.outputOn_query script db _ parameters rest _ [] _ head
    (resolveStatement_selectNoFrom runContext db.raw.connection.resolveState value text filter expression affinity condition
      notCall noAggregate operand plain resolves)

/-- For every script that is one read-only statement and is as in {name}`Script.outputOn_selectNoFrom`, where the expression and the condition are calm (they
have no fallible call, no clock and no counter read): {name}`Holds` of the script on the database means that the
condition is true for the row with no cells, in the context of the values. Without {lit}`WHERE`, {name}`Holds` holds.
Proof sketch: {name}`Script.outputOn_selectNoFrom` and {name}`resolvedStepOutput_selectNoFrom_hasRows`. -/
theorem Holds.iff_selectNoFrom
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {value : Syntax.Expr} {text : String}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {expression : Resolved.Expr} {affinity : Option Affinity} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression value none text] none [] filter [] [] none none []
      none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (operand : resolveOperand runContext.profile.dqsDml [] { later := [] } false value = .ok (expression, affinity))
    (resolves : FilterResolves runContext.profile.dqsDml [] [] filter condition)
    (calm : expression.Calm) (conditionCalm : ∀ part ∈ condition.toList, part.Calm) :
    Holds script db isQuery ↔
      condition.all (fun part => Resolved.truthy (part.eval (Resolved.EvalContext.bound parameters) [])) = true := by
  unfold Holds
  rw [Script.outputOn_selectNoFrom head notCall noAggregate operand resolves calm.1, Option.any_some]
  exact resolvedStepOutput_selectNoFrom_hasRows 0 db.raw.connection parameters condition expression _ (Resolved.Statement.Calm.selectNoFrom condition expression _ conditionCalm calm)

/-- For every script as in {name}`Holds.iff_selectNoFrom` (one read-only statement): {name}`Empty` of the script on the database means that the
condition is not true for the row with no cells. Without {lit}`WHERE`, {name}`Empty` does not hold. Proof sketch:
{name}`Script.outputOn_selectNoFrom` and {name}`resolvedStepOutput_selectNoFrom_hasNoRows`. -/
theorem Empty.iff_selectNoFrom
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {value : Syntax.Expr} {text : String}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {expression : Resolved.Expr} {affinity : Option Affinity} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression value none text] none [] filter [] [] none none []
      none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (operand : resolveOperand runContext.profile.dqsDml [] { later := [] } false value = .ok (expression, affinity))
    (resolves : FilterResolves runContext.profile.dqsDml [] [] filter condition)
    (calm : expression.Calm) (conditionCalm : ∀ part ∈ condition.toList, part.Calm) :
    Empty script db isQuery ↔
      condition.all (fun part => Resolved.truthy (part.eval (Resolved.EvalContext.bound parameters) [])) = false := by
  unfold Empty
  rw [Script.outputOn_selectNoFrom head notCall noAggregate operand resolves calm.1, Option.any_some]
  exact resolvedStepOutput_selectNoFrom_hasNoRows 0 db.raw.connection parameters condition expression _ (Resolved.Statement.Calm.selectNoFrom condition expression _ conditionCalm calm)

/-- For every script as in {name}`Holds.iff_selectNoFrom` (one read-only statement), {name}`Fails` of the script on the database does not hold.
Proof sketch: {name}`Script.outputOn_selectNoFrom` and {name}`resolvedStepOutput_selectNoFrom_not_isError`. -/
theorem Fails.not_selectNoFrom
    {script : Script} {db : Database} {isQuery : script.isQuery = true} {value : Syntax.Expr} {text : String}
    {filter : Option Syntax.Expr} {parameters : List Value} {rest : List (Syntax.Statement × List Value)}
    {expression : Resolved.Expr} {affinity : Option Affinity} {condition : Option Resolved.Expr}
    (head : script.statements = (.select [.expression value none text] none [] filter [] [] none none []
      none false none, parameters) :: rest)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (operand : resolveOperand runContext.profile.dqsDml [] { later := [] } false value = .ok (expression, affinity))
    (resolves : FilterResolves runContext.profile.dqsDml [] [] filter condition)
    (calm : expression.Calm) (conditionCalm : ∀ part ∈ condition.toList, part.Calm) :
    ¬ Fails script db isQuery := by
  unfold Fails
  rw [Script.outputOn_selectNoFrom head notCall noAggregate operand resolves calm.1, Option.any_some,
    resolvedStepOutput_selectNoFrom_not_isError 0 db.raw.connection parameters condition expression _ (Resolved.Statement.Calm.selectNoFrom condition expression _ conditionCalm calm)]
  simp

end Belay.Sqlite
