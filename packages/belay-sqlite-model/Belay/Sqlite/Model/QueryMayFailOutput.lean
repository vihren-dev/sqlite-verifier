import Belay.Sqlite.Model.SimpleTableOutput
import Belay.Sqlite.Model.StatementQuiet
import Belay.Sqlite.Model.SelectOneResolution

set_option doc.verso true

/-! A query that may fail has no modeled output (ADR 0017, S4): when a call of the {lit}`WHERE`
condition may fail on a row of a table, the run of the query has the fault
{lit}`Fault.may`, and the model does not describe the statement. Then the output has no rows, has not no
rows, and is no error. These three facts do not say which output it is. -/

namespace Belay.Sqlite.Model

/-- For every simple query with a source, rows, context and row of the empty row and the rows, and every
expression of the {lit}`WHERE` condition that may fail on that row ({name}`Resolved.Expr.mayFailOn`), the run
of the query over the rows has the fault {name}`Resolved.Fault.may`. A query without source can have the
fault {name}`Resolved.Fault.must`, so the lemma needs the source. Proof sketch: a query with a source is no
certain JSON failure ({name}`Resolved.Query.mustFail`), and the call that may fail makes the query
{name}`Resolved.Query.mayFail`; so the fault of the run is {name}`Resolved.Fault.may`. -/
theorem Resolved.Query.Simple.run_fault_may {query : Resolved.Query} (simple : query.Simple)
    (context : Resolved.EvalContext) (rows : List (List Value)) (withSource : query.sources.isEmpty = false)
    {row : List Value} (member : row ∈ [] :: rows) {expression : Resolved.Expr} (inFilter : expression ∈ query.filter.toList)
    (fails : expression.mayFailOn context row = true) :
    (query.run context rows).fault = .may := by
  have mayFail : query.mayFail context rows = true := by
    unfold Resolved.Query.mayFail
    simp only [Bool.or_eq_true]
    refine .inr (.inl ?_)
    unfold Resolved.anyMayFail
    exact List.any_eq_true.mpr ⟨row, member, List.any_eq_true.mpr ⟨expression, inFilter, fails⟩⟩
  have noMust : query.mustFail context rows = false := by
    simp [Resolved.Query.mustFail, withSource]
  simp [Resolved.Query.run, simple.compound, simple.bindWindow, noMust, mayFail]

/-- For every query statement that reads no clock and no unknown counter, whose source rows
{lit}`source` and bound window {lit}`bound` exist, when the run of the query has the fault {lit}`may`, the output
of its step has no rows, has not no rows, and is no error. The lemma does not say which output it is.
Proof sketch: the three cases of {name}`resolvedStepOutput_query_hasRows`,
{name}`resolvedStepOutput_query_hasNoRows` and {name}`resolvedStepOutput_query_isError` each require that
the fault of the run be not {lit}`may`. -/
theorem resolvedStepOutput_query_unmodeled (index : Nat) (connection : Connection) (parameters : List Value)
    (query bound : Resolved.Query) (subqueries : List Resolved.Query) (source : Resolved.SourceRows)
    (noClock : (Resolved.Statement.query query subqueries).readsClock = false)
    (known : connection.state.counters.firstUnknown (Resolved.Statement.query query subqueries).counterReads = none)
    (found : query.source (connection.queryContext parameters query subqueries) connection.state.database = some source)
    (window : query.bindWindow parameters = some bound)
    (may : (query.run (connection.queryContext parameters query subqueries) source.rows).fault = .may) :
    (resolvedStepOutput none index connection parameters (.query query subqueries)).hasRows = false ∧
    (resolvedStepOutput none index connection parameters (.query query subqueries)).hasNoRows = false ∧
    (resolvedStepOutput none index connection parameters (.query query subqueries)).isError = false := by
  refine ⟨?_, ?_, ?_⟩
  · refine Bool.eq_false_iff.mpr fun yes => ?_
    have := (resolvedStepOutput_query_hasRows index connection parameters query bound subqueries source noClock known
      found window).mp yes
    simp_all
  · refine Bool.eq_false_iff.mpr fun yes => ?_
    have := (resolvedStepOutput_query_hasNoRows index connection parameters query bound subqueries source noClock known
      found window).mp yes
    simp_all
  · refine Bool.eq_false_iff.mpr fun yes => ?_
    have := (resolvedStepOutput_query_isError index connection parameters query subqueries source noClock known
      found).mp yes
    simp_all

/-- For every connection, values and quiet statement of a query without subqueries, the context of the
query on the connection is the context of the values ({name}`Resolved.EvalContext.bound`): the statement
reads no counter, so the context knows none. Proof sketch: the statement reads no counters
({name}`Resolved.Statement.Quiet.counterReads`), and the view of the counters for no read is no counter. -/
theorem Connection.queryContext_of_quiet (connection : Connection) (parameters : List Value) (query : Resolved.Query)
    (quiet : (Resolved.Statement.query query []).Quiet) :
    connection.queryContext parameters query [] = Resolved.EvalContext.bound parameters := by
  simp only [Connection.queryContext, quiet.counterReads, Resolved.statementContext_nil]
  rfl

/-- For every connection, values, table at a position of the database of the connection and quiet statement of
the simple query of that table with a {lit}`WHERE` condition, where some expression of the condition may fail
({name}`Resolved.Expr.mayFailOn`) on the empty row or on a row of the table, the output of the step has no
rows, has not no rows, and is no error. The lemma does not say which output it is. Proof sketch:
{name}`Resolved.Query.Simple.run_fault_may` gives the fault {lit}`may`, and
{name}`resolvedStepOutput_query_unmodeled` the three facts, with the source of
{name}`Resolved.Query.source_first`. -/
theorem resolvedStepOutput_simpleTable_unmodeled (index position : Nat) (connection : Connection)
    (parameters : List Value) (table : Table) (condition : Option Resolved.Expr) (columns : List Resolved.Output)
    (names : List String) (present : connection.state.database.table position = some table)
    (quiet : (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) []).Quiet)
    {row : List Value} (member : row ∈ [] :: Resolved.sourceRows table) {expression : Resolved.Expr}
    (inFilter : expression ∈ condition.toList) (fails : expression.mayFailOn (Resolved.EvalContext.bound parameters) row = true) :
    (resolvedStepOutput none index connection parameters (.query
      (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])).hasRows = false ∧
    (resolvedStepOutput none index connection parameters (.query
      (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])).hasNoRows = false ∧
    (resolvedStepOutput none index connection parameters (.query
      (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])).isError = false := by
  have found := Resolved.Query.source_first
    (connection.queryContext parameters (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names) [])
    (Resolved.Query.simple [Resolved.QuerySource.first position] condition columns names)
    connection.state.database position table rfl present
  have context := Connection.queryContext_of_quiet connection parameters _ quiet
  exact resolvedStepOutput_query_unmodeled index connection parameters _ _ [] _ quiet.readsClock (quiet.firstUnknown _) found
    ((Resolved.Query.simple_isSimple _ _ _ _).bindWindow parameters)
    ((Resolved.Query.simple_isSimple _ _ _ _).run_fault_may _ _ rfl (by simpa using member) inFilter (by rw [context]; exact fails))

/-- For every condition whose expressions are quiet ({name}`Resolved.Expr.Quiet`) and every position, the
statement of the query {lit}`SELECT 1 FROM t WHERE p` that resolution gives is quiet
({name}`Resolved.Statement.Quiet`): the literal one is quiet, and the first source of a table has no
expression. Proof sketch: as for {name}`Resolved.Statement.Calm.selectOne`; the expressions of the statement
are the condition and the literal. -/
theorem Resolved.Statement.Quiet.selectOne (position : Nat) (condition : Option Resolved.Expr)
    (quiet : ∀ expression ∈ condition.toList, expression.Quiet) :
    (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition
      [.scalar (.literal (.integer 1))] ["1"]) []).Quiet := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.expressions, Resolved.Query.keptExpressions,
    Resolved.Query.simple, Resolved.QuerySource.first, Resolved.QuerySource.expressions, List.mem_append,
    List.mem_flatMap, List.flatMap_nil, List.append_nil, List.mem_cons, List.mem_nil_iff, or_false] at member
  have literal : (Resolved.Expr.literal (.integer 1)).Quiet := by
    simp [Resolved.Expr.Quiet, Resolved.Expr.any, Resolved.Expr.readsClockHere, Resolved.Expr.readsCounterHere]
  simp only [Resolved.Output.scalars, Resolved.Output.operands, List.mem_singleton, List.not_mem_nil, exists_eq_left,
    List.map_nil, or_false, Option.toList_none] at member
  rcases member with member | rfl
  · exact quiet expression member
  · exact literal

end Belay.Sqlite.Model
