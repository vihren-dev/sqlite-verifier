import Belay.Sqlite.Model.SimpleSubqueryRun

set_option doc.verso true

/-! The run of a count query (ADR 0017, S4): the query {lit}`SELECT count(*) FROM t WHERE p`, an
aggregate query of one group with the one result column {lit}`count(*)` and no grouping, ordering, window,
{lit}`HAVING`, {lit}`DISTINCT` or compound. Its one result is one row, the number of source rows that
{lit}`WHERE` keeps, also when there are none. -/

namespace Belay.Sqlite.Model.Resolved

/-- A count query: an aggregate query with no grouping term, whose one result column is
{lit}`count(*)`, and that has no ordering term, no {lit}`LIMIT`, no {lit}`OFFSET`, no {lit}`HAVING`, no
{lit}`DISTINCT`, no compound and no other aggregate. For example, the query of
{lit}`SELECT count(*) FROM t WHERE x > 1` is a count query. -/
structure Query.Count (query : Query) : Prop where
  /-- The query is an aggregate query. -/
  aggregate : query.aggregate = true
  /-- The query has no {lit}`GROUP BY`. -/
  groupBy : query.groupBy = []
  /-- The one result column is {lit}`count(*)`. -/
  columns : query.columns = [.aggregate .countRows]
  /-- No expression names another aggregate. -/
  aggregates : query.aggregates = []
  /-- The query has no {lit}`ORDER BY`. -/
  orderBy : query.orderBy = []
  /-- The query skips no row. -/
  offset : query.offset = 0
  /-- The query has no {lit}`LIMIT`. -/
  limit : query.limit = none
  /-- The query has no {lit}`LIMIT ?`. -/
  limitParameter : query.limitParameter = none
  /-- The query has no {lit}`OFFSET ?`. -/
  offsetParameter : query.offsetParameter = none
  /-- The query has no {lit}`HAVING`. -/
  having : query.having = none
  /-- The query is no {lit}`SELECT DISTINCT`. -/
  distinct : query.distinct = none
  /-- The query is no compound. -/
  compound : query.compound = none

/-- The count query of the given sources, {lit}`WHERE` condition and result name: an aggregate query of one
group with the one result column {lit}`count(*)`, and without grouping, ordering, window, {lit}`HAVING`,
{lit}`DISTINCT` or compound, that reads no cell of an outer query. -/
def Query.countOf (sources : List QuerySource) (filter : Option Expr) (name : String) : Query :=
  { sources, filter, aggregate := true, groupBy := [], columns := [.aggregate .countRows], names := [name],
    orderBy := [], offset := 0, limit := none, limitParameter := none, offsetParameter := none, outer := 0,
    aggregates := [], having := none, distinct := none }

/-- For all sources, condition and name, {name}`Query.countOf` of them is a count query ({name}`Query.Count`).
Proof sketch: each field of {name}`Query.Count` is the value that the definition of {name}`Query.countOf` gives, so
each holds by definitional equality. -/
theorem Query.countOf_isCount (sources : List QuerySource) (filter : Option Expr) (name : String) :
    (Query.countOf sources filter name).Count :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- For every count query, over any rows, the records are one record: the row with the number of rows that
{lit}`WHERE` keeps, and no sort value. Proof sketch: the one group is the kept rows ({name}`queryGroups`), no
{lit}`HAVING` removes it, and {name}`countRows_eval` gives the value of {lit}`count(*)`. -/
theorem Query.Count.uniqueRecords {query : Query} (count : query.Count) (context : EvalContext)
    (rows : List (List Value)) :
    query.uniqueRecords context rows = [([.integer (filtered context query rows).length], [])] := by
  unfold Query.uniqueRecords records
  simp [count.compound, count.distinct, count.aggregate, count.groupBy, count.having, count.columns, count.orderBy,
    queryGroups, Aggregate.eval]

/-- For every count query, over any rows, the one result is one row with one value, the number of rows that
{lit}`WHERE` keeps. With no source row, or with no row kept, the value is zero. Proof sketch: the window takes
the one record ({name}`Query.Count.uniqueRecords`), which the sort and the window keep. -/
theorem Query.Count.results {query : Query} (count : query.Count) (context : EvalContext) (rows : List (List Value)) :
    query.results context rows = [[.integer (filtered context query rows).length]] := by
  unfold Query.results
  simp [count.uniqueRecords, count.limit, count.offset, stableSort, insertStable]

/-- For every count query, the window binds to the query itself, for any values. Proof sketch:
{name}`Query.bindWindow_literal`; a count query has no window parameter. -/
theorem Query.Count.bindWindow {query : Query} (count : query.Count) (parameters : List Value) :
    query.bindWindow parameters = some query :=
  Query.bindWindow_literal parameters query count.limitParameter count.offsetParameter

/-- For every count query whose expressions have no fallible call ({name}`Expr.isFallibleCall`), in a context in
which its expressions have no fault over the empty row and over each of the rows ({name}`Expr.evaluate`), the
run over those rows gives the one result ({name}`Query.Count.results`), no fault, no overflow and no window
mismatch. Proof sketch: the window binds to the query ({name}`Query.Count.bindWindow`); {lit}`count(*)` does not
overflow ({name}`Aggregate.fails`); there is no {lit}`DISTINCT`; and no expression has a fault, so the query neither
certainly nor possibly fails ({name}`Query.mustFail_of_faultless`, {name}`Query.mayFail_of_faultless`). -/
theorem Query.Count.run_of_faultless {query : Query} (count : query.Count) (context : EvalContext)
    (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true) (rows : List (List Value))
    (faultless : ∀ row ∈ [] :: rows, ∀ expression ∈ query.expressions, (expression.evaluate context row).2 = .none) :
    query.run context rows =
      { rows := query.results context rows, fault := .none, overflow := false, mismatch := false } := by
  unfold Query.run
  simp [count.compound, count.bindWindow, Query.mustFail_of_faultless context query rows faultless,
    Query.mayFail_of_faultless context query rows plain faultless, Query.distinctCertain, count.distinct, Query.fails,
    count.columns, count.aggregates, Aggregate.fails]

/-- For every count query that reads no cell of an outer query, whose source rows in a context and database
have no fault, and whose expressions have no fallible call and no fault over the empty row and over each
source row, the run as a subquery for the outer row with no cells ({name}`Query.subqueryRun`) has the one row
of {name}`Query.Count.results` as its rows, no fault, and certain rows; it ends done. Proof sketch: as for
{name}`Query.subqueryRun_simple`, with {name}`Query.Count.run_of_faultless`; a window of no {lit}`LIMIT` and no
{lit}`OFFSET` cuts nowhere ({name}`certainCut`). -/
theorem Query.Count.subqueryRun {query : Query} (count : query.Count) (context : EvalContext) (database : Database)
    (outer : query.outer = 0) (source : SourceRows) (found : query.source context database = some source)
    (clean : source.fault = .none) (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true)
    (faultless : ∀ row ∈ [] :: source.rows, ∀ expression ∈ query.expressions,
      (expression.evaluate context row).2 = .none) :
    query.subqueryRun context database [] =
      { rows := [[.integer (filtered context query source.rows).length]], fault := .none, firstCertain := true,
        rowsCertain := true, ending := .done } := by
  have after : query.sourceAfter context [] database = some source := by
    simpa [Query.sourceAfter, outer, Query.source] using found
  unfold Query.subqueryRun
  rw [after]
  simp only [count.bindWindow context.parameters, count.run_of_faultless context plain source.rows faultless,
    count.results, clean]
  simp [Fault.join, Fault.soften, Query.windowCertain, certainCut, count.limit, count.offset, count.uniqueRecords,
    stableSort, insertStable]
