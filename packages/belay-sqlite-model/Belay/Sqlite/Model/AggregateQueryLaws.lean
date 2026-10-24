import Belay.Sqlite.Model.CountQueryLaws

set_option doc.verso true

/-! The run of a whole-table aggregate query (ADR 0017, S4): the query {lit}`SELECT sum(c) FROM t WHERE p`, an
aggregate query of one group with the one result column an aggregate and no grouping, ordering, window,
{lit}`HAVING`, {lit}`DISTINCT` or compound. Its one result is one row, the value of the aggregate over the rows that
{lit}`WHERE` keeps, also when there are none. It fails when the aggregate fails, for example when {lit}`sum` overflows. The
count query ({name}`Belay.Sqlite.Model.Resolved.Query.countOf`) is the case of {lit}`count(*)`. -/

namespace Belay.Sqlite.Model.Resolved

/-- The whole-table aggregate query of the given sources, {lit}`WHERE` condition, aggregate and result name: an aggregate
query of one group with the one result column the aggregate, and without grouping, ordering, window, {lit}`HAVING`,
{lit}`DISTINCT` or compound, that reads no cell of an outer query. For example, {lit}`SELECT sum(c) FROM t` is
the whole-table aggregate query of the table, no condition, the aggregate {lit}`sum` of the column {lit}`c`. -/
def Query.aggregateOf (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate) (name : String) : Query :=
  { sources, filter, aggregate := true, groupBy := [], columns := [.aggregate aggregate], names := [name],
    orderBy := [], offset := 0, limit := none, limitParameter := none, offsetParameter := none, outer := 0,
    aggregates := [], having := none, distinct := none }

/-- The count query is the whole-table aggregate query of {lit}`count(*)`. Proof sketch: the definitions agree. -/
theorem Query.countOf_eq_aggregateOf (sources : List QuerySource) (filter : Option Expr) (name : String) :
    Query.countOf sources filter name = Query.aggregateOf sources filter .countRows name := rfl

/-- The whole-table aggregate query has no {lit}`ORDER BY`, no window, no {lit}`HAVING`, no {lit}`DISTINCT`, no compound
and no grouping, and its one result column is the aggregate. Proof sketch: each field is the value that the definition
gives, so each holds by definitional equality. -/
theorem Query.aggregateOf_fields (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) :
    (Query.aggregateOf sources filter aggregate name).aggregate = true ∧
      (Query.aggregateOf sources filter aggregate name).groupBy = [] ∧
      (Query.aggregateOf sources filter aggregate name).columns = [.aggregate aggregate] ∧
      (Query.aggregateOf sources filter aggregate name).aggregates = [] ∧
      (Query.aggregateOf sources filter aggregate name).orderBy = [] ∧
      (Query.aggregateOf sources filter aggregate name).offset = 0 ∧
      (Query.aggregateOf sources filter aggregate name).limit = none ∧
      (Query.aggregateOf sources filter aggregate name).having = none ∧
      (Query.aggregateOf sources filter aggregate name).distinct = none ∧
      (Query.aggregateOf sources filter aggregate name).compound = none :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- For every whole-table aggregate query, over any rows, the records are one record: the row with the value of the
aggregate over the rows that {lit}`WHERE` keeps, and no sort value. Proof sketch: the one group is the kept rows
({name}`queryGroups`), and no {lit}`HAVING` removes it. -/
theorem Query.aggregateOf_uniqueRecords (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) (context : EvalContext) (rows : List (List Value)) :
    (Query.aggregateOf sources filter aggregate name).uniqueRecords context rows =
      [([aggregate.eval context (filtered context (Query.aggregateOf sources filter aggregate name) rows)], [])] := by
  obtain ⟨isAggregate, noGroup, columns, noAggregates, noOrder, noOffset, noLimit, noHaving, notDistinct, noCompound⟩ :=
    Query.aggregateOf_fields sources filter aggregate name
  unfold Query.uniqueRecords records
  simp [noCompound, notDistinct, isAggregate, noGroup, noHaving, columns, noOrder, queryGroups, Aggregate.eval]

/-- The rows that {lit}`WHERE` keeps of a whole-table aggregate query are the rows for which its condition, if any, is true.
Proof sketch: the definitions agree. -/
theorem Query.aggregateOf_filtered (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) (context : EvalContext) (rows : List (List Value)) :
    filtered context (Query.aggregateOf sources filter aggregate name) rows =
      rows.filter fun row => filter.all fun condition => truthy (condition.eval context row) := rfl

/-- For every whole-table aggregate query, over any rows, the one result is one row with one value, the value of the
aggregate over the rows that {lit}`WHERE` keeps. Proof sketch: the window takes the one record
({name}`Query.aggregateOf_uniqueRecords`), which the sort and the window keep. -/
theorem Query.aggregateOf_results (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) (context : EvalContext) (rows : List (List Value)) :
    (Query.aggregateOf sources filter aggregate name).results context rows =
      [[aggregate.eval context (filtered context (Query.aggregateOf sources filter aggregate name) rows)]] := by
  obtain ⟨_, _, _, _, noOrder, noOffset, noLimit, _, _, _⟩ := Query.aggregateOf_fields sources filter aggregate name
  unfold Query.results
  simp [Query.aggregateOf_uniqueRecords, noLimit, noOffset, stableSort, insertStable]

/-- For every whole-table aggregate query, the window binds to the query itself, for any values. Proof sketch:
{name}`Query.bindWindow_literal`; the query has no window parameter. -/
theorem Query.aggregateOf_bindWindow (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) (parameters : List Value) :
    (Query.aggregateOf sources filter aggregate name).bindWindow parameters =
      some (Query.aggregateOf sources filter aggregate name) :=
  Query.bindWindow_literal parameters _ rfl rfl

/-- For every whole-table aggregate query, over any rows, the query fails ({name}`Query.fails`) exactly when the aggregate
fails ({name}`Aggregate.fails`) over the rows that {lit}`WHERE` keeps. Proof sketch: the one group is the kept rows,
and the query has no other aggregate. -/
theorem Query.aggregateOf_fails (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) (context : EvalContext) (rows : List (List Value)) :
    (Query.aggregateOf sources filter aggregate name).fails context rows =
      aggregate.fails context (filtered context (Query.aggregateOf sources filter aggregate name) rows) := by
  obtain ⟨isAggregate, noGroup, columns, noAggregates, _, _, noLimit, _, _, _⟩ :=
    Query.aggregateOf_fields sources filter aggregate name
  simp [Query.fails, isAggregate, noLimit, noGroup, noAggregates, columns, queryGroups]

/-- For every whole-table aggregate query whose expressions have no fallible call ({name}`Expr.isFallibleCall`), in a
context in which its expressions have no fault over the empty row and over each of the rows ({name}`Expr.evaluate`), the
run over those rows gives the one result ({name}`Query.aggregateOf_results`), no fault, no window mismatch, and an
overflow exactly when the aggregate fails. Proof sketch: the window binds to the query
({name}`Query.aggregateOf_bindWindow`); there is no {lit}`DISTINCT`; and no expression has a fault, so the query neither
certainly nor possibly fails ({name}`Query.mustFail_of_faultless`, {name}`Query.mayFail_of_faultless`). -/
theorem Query.aggregateOf_run_of_faultless (sources : List QuerySource) (filter : Option Expr) (aggregate : Aggregate)
    (name : String) (context : EvalContext)
    (plain : (Query.aggregateOf sources filter aggregate name).expressions.all (!·.any Expr.isFallibleCall) = true)
    (rows : List (List Value))
    (faultless : ∀ row ∈ [] :: rows, ∀ expression ∈ (Query.aggregateOf sources filter aggregate name).expressions,
      (expression.evaluate context row).2 = .none) :
    (Query.aggregateOf sources filter aggregate name).run context rows =
      { rows := (Query.aggregateOf sources filter aggregate name).results context rows, fault := .none,
        overflow := aggregate.fails context (filtered context (Query.aggregateOf sources filter aggregate name) rows),
        mismatch := false } := by
  obtain ⟨_, _, _, _, _, _, _, _, notDistinct, noCompound⟩ := Query.aggregateOf_fields sources filter aggregate name
  unfold Query.run
  simp [noCompound, Query.aggregateOf_bindWindow, Query.mustFail_of_faultless context _ rows faultless,
    Query.mayFail_of_faultless context _ rows plain faultless, Query.distinctCertain, notDistinct,
    Query.aggregateOf_fails]

end Belay.Sqlite.Model.Resolved
