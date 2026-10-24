import Belay.Sqlite.Model.NoFromQuerySteps
import Belay.Sqlite.Model.SelectNoFromResolution

set_option doc.verso true

/-! The output of {lit}`SELECT e` and {lit}`SELECT e WHERE c` without {lit}`FROM` (ADR 0017, S4): when the
expression and the condition are calm, the query reads the one row with no cells, so its output has a row
exactly when the condition, if any, is true for that row, has no row exactly when it is not, and is never
an error. Without {lit}`WHERE`, it has a row. -/

namespace Belay.Sqlite.Model

/-- For every calm condition and calm expression, the statement of the simple query without source, with that
condition and the one scalar column of the expression, is calm ({name}`Resolved.Statement.Calm`). Proof sketch: the
expressions of the statement are the condition and the expression. -/
theorem Resolved.Statement.Calm.selectNoFrom (condition : Option Resolved.Expr) (expression : Resolved.Expr)
    (names : List String) (conditionCalm : ∀ part ∈ condition.toList, part.Calm) (calm : expression.Calm) :
    (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Calm := by
  intro part member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.expressions, Resolved.Query.keptExpressions,
    Resolved.Query.simple, List.mem_append, List.flatMap_nil, Resolved.Output.scalars, Resolved.Output.operands,
    List.mem_singleton, List.map_nil, List.append_nil, List.flatMap_cons, Option.toList_none] at member
  rcases member with member | member
  · exact conditionCalm part member
  · rw [member]
    exact calm

/-- For every connection, values, calm condition, calm expression and names, the output of the step of the
simple query {lit}`SELECT e WHERE c` without source has rows exactly when the condition, if any, is true for
the row with no cells in the context of the values. Proof sketch: {name}`resolvedStepOutput_noFrom_hasRows`;
a calm statement has no fault ({name}`Resolved.Statement.Calm.faultless_nil`) and its context is the context of
the values ({name}`Connection.queryContext_of_calm`). -/
theorem resolvedStepOutput_selectNoFrom_hasRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Option Resolved.Expr) (expression : Resolved.Expr) (names : List String)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [] condition [.scalar expression] names) [])).hasRows = true ↔
      condition.all (fun part => Resolved.truthy (part.eval (Resolved.EvalContext.bound parameters) [])) = true := by
  rw [resolvedStepOutput_noFrom_hasRows index connection parameters condition _ names [] calm
    (fun part member => calm.faultless_nil connection parameters (rows := []) [] (by simp) part member),
    Connection.queryContext_of_calm connection parameters _ calm]

/-- For every connection, values, calm condition, calm expression and names as in
{name}`resolvedStepOutput_selectNoFrom_hasRows`, the output of the step has no rows exactly when the condition,
if any, is not true for the row with no cells. Proof sketch: as for
{name}`resolvedStepOutput_selectNoFrom_hasRows`, with {name}`resolvedStepOutput_noFrom_hasNoRows`. -/
theorem resolvedStepOutput_selectNoFrom_hasNoRows (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Option Resolved.Expr) (expression : Resolved.Expr) (names : List String)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [] condition [.scalar expression] names) [])).hasNoRows = true ↔
      condition.all (fun part => Resolved.truthy (part.eval (Resolved.EvalContext.bound parameters) [])) = false := by
  rw [resolvedStepOutput_noFrom_hasNoRows index connection parameters condition _ names [] calm
    (fun part member => calm.faultless_nil connection parameters (rows := []) [] (by simp) part member),
    Connection.queryContext_of_calm connection parameters _ calm]

/-- For every connection, values, calm condition, calm expression and names as in
{name}`resolvedStepOutput_selectNoFrom_hasRows`, the output of the step is no error. Proof sketch:
{name}`resolvedStepOutput_noFrom_not_isError`. -/
theorem resolvedStepOutput_selectNoFrom_not_isError (index : Nat) (connection : Connection) (parameters : List Value)
    (condition : Option Resolved.Expr) (expression : Resolved.Expr) (names : List String)
    (calm : (Resolved.Statement.query (Resolved.Query.simple [] condition [.scalar expression] names) []).Calm) :
    (resolvedStepOutput none index connection parameters
      (.query (Resolved.Query.simple [] condition [.scalar expression] names) [])).isError = false :=
  resolvedStepOutput_noFrom_not_isError index connection parameters condition _ names [] calm
    (fun part member => calm.faultless_nil connection parameters (rows := []) [] (by simp) part member)

end Belay.Sqlite.Model
