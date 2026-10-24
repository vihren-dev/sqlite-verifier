import Belay.Sqlite.Model.QueryMayFailOutput
import Belay.Sqlite.Model.ExistsSubqueryOutput

set_option doc.verso true

/-! A subquery that calls a function that can fail has no modeled output (ADR 0017, S4): SQLite may
evaluate a subquery for rows that the model does not reach, so the model does not describe a failure
inside one. The output of the statement with such a subquery has no rows, has not no rows, and is no error. -/

namespace Belay.Sqlite.Model

/-- For every query statement that reads no clock and no unknown counter, whose subqueries (those that are
no term of a compound) have a fallible call in some expression, the output of its step has no rows, has not
no rows, and is no error. The lemma does not say which output it is. Proof sketch: {name}`resolvedStepOutput_query`; the
model describes the statement only when the subqueries are plain ({name}`Resolved.Query.described`), so
the output is {name}`unmodeledHere`. -/
theorem resolvedStepOutput_query_unmodeled_of_subquery (index : Nat) (connection : Connection) (parameters : List Value)
    (query : Resolved.Query) (subqueries : List Resolved.Query)
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (fallible : Resolved.subqueriesPlain (query.nestedSubqueries subqueries) = false) :
    (resolvedStepOutput none index connection parameters (.query query subqueries)).hasRows = false ∧
    (resolvedStepOutput none index connection parameters (.query query subqueries)).hasNoRows = false ∧
    (resolvedStepOutput none index connection parameters (.query query subqueries)).isError = false := by
  rw [resolvedStepOutput_query index connection parameters query subqueries noClock known]
  simp [Resolved.Query.described, fallible, Output.hasRows, Output.hasNoRows, Output.isError]

/-- For every quiet condition {lit}`c` and every quiet condition of the subquery, the statement of
{lit}`SELECT 1 WHERE c` with the one subquery {lit}`SELECT 1 FROM t WHERE p` that resolution gives is quiet
({name}`Resolved.Statement.Quiet`). Proof sketch: as for {name}`Resolved.Statement.Calm.selectOne_subquery`. -/
theorem Resolved.Statement.Quiet.selectOne_subquery (position : Nat) (main : Resolved.Expr)
    (subCondition : Option Resolved.Expr) (mainQuiet : main.Quiet)
    (subQuiet : ∀ expression ∈ subCondition.toList, expression.Quiet) :
    (Resolved.Statement.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition
        [.scalar (.literal (.integer 1))] ["1"]]).Quiet := by
  have literal : (Resolved.Expr.literal (.integer 1)).Quiet := by
    simp [Resolved.Expr.Quiet, Resolved.Expr.any, Resolved.Expr.readsClockHere, Resolved.Expr.readsCounterHere]
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.selectOneWhere_expressions,
    Resolved.Query.simple_first_expressions, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append,
    List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with (rfl | rfl) | member | rfl
  · exact mainQuiet
  · exact literal
  · exact subQuiet expression (by simpa using member)
  · exact literal

/-- For every connection, values, quiet main condition {lit}`c`, and quiet condition of the one subquery
{lit}`SELECT 1 FROM t WHERE p` of a table at a position, where some part of the condition of the subquery is a
fallible call, the output of the step of {lit}`SELECT 1 WHERE c` has no rows, has not no rows, and is no error.
Proof sketch: {name}`resolvedStepOutput_query_unmodeled_of_subquery`; the statement is quiet
({name}`Resolved.Statement.Quiet.selectOne_subquery`), and the one subquery is not plain. -/
theorem resolvedStepOutput_selectOne_subquery_unmodeled (index position : Nat) (connection : Connection)
    (parameters : List Value) (main : Resolved.Expr) (subCondition : Option Resolved.Expr)
    (mainQuiet : main.Quiet) (subQuiet : ∀ expression ∈ subCondition.toList, expression.Quiet)
    {expression : Resolved.Expr} (inCondition : expression ∈ subCondition.toList)
    (fallible : expression.any Resolved.Expr.isFallibleCall = true) :
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition
        [.scalar (.literal (.integer 1))] ["1"]])).hasRows = false ∧
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition
        [.scalar (.literal (.integer 1))] ["1"]])).hasNoRows = false ∧
    (resolvedStepOutput none index connection parameters (.query (Resolved.Query.selectOneWhere main)
      [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition
        [.scalar (.literal (.integer 1))] ["1"]])).isError = false := by
  have quiet := Resolved.Statement.Quiet.selectOne_subquery position main subCondition mainQuiet subQuiet
  refine resolvedStepOutput_query_unmodeled_of_subquery index connection parameters _ _ quiet.readsClock
    (quiet.firstUnknown _) ?_
  have notPlain : ¬ (Resolved.Query.simple [Resolved.QuerySource.first position] subCondition
      [.scalar (.literal (.integer 1))] ["1"]).expressions.all (!·.any Resolved.Expr.isFallibleCall) = true := by
    rw [Resolved.Query.simple_first_expressions]
    simp only [List.all_eq_true, List.mem_append, Bool.not_eq_true']
    intro all
    simp [all expression (.inl inCondition)] at fallible
  simpa [Resolved.subqueriesPlain, Resolved.Query.nestedSubqueries, Resolved.Query.selectOneWhere,
    Resolved.Query.simple] using notPlain

end Belay.Sqlite.Model
