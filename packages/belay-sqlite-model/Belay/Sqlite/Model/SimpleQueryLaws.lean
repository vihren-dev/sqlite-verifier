import Belay.Sqlite.Model.PossibleResultsLaws
import Belay.Sqlite.Model.QueryPlainLaws
import Belay.Sqlite.Model.QueryLaws

set_option doc.verso true

/-! The run of a simple query (ADR 0017, S4): a query that only selects columns of its source
rows that {lit}`WHERE` keeps, without aggregate, grouping, ordering, window, {lit}`HAVING`,
{lit}`DISTINCT` or compound. Its one result has a row exactly when {lit}`WHERE` is true for a
source row, and its run has no window mismatch and no overflow. These are the facts that the
query forms {lit}`SELECT e` and {lit}`SELECT 1 FROM t WHERE p` read. -/

namespace Belay.Sqlite.Model.Resolved

/-- A simple query: it has no aggregate, no grouping term, no ordering term, no
{lit}`LIMIT` or {lit}`OFFSET`, no {lit}`HAVING`, no {lit}`DISTINCT` and no compound. For example,
the query of {lit}`SELECT 1 FROM t WHERE p` is simple. -/
structure Query.Simple (query : Query) : Prop where
  /-- The query is no aggregate query. -/
  aggregate : query.aggregate = false
  /-- The query has no {lit}`GROUP BY`. -/
  groupBy : query.groupBy = []
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

/-- The simple query of the given sources, {lit}`WHERE` condition and result columns with their
names: it is not an aggregate query, and has no grouping, ordering, window, {lit}`HAVING`,
{lit}`DISTINCT` or compound, and it reads no cell of an outer query. -/
def Query.simple (sources : List QuerySource) (filter : Option Expr) (columns : List Output) (names : List String) :
    Query :=
  { sources, filter, aggregate := false, groupBy := [], columns, names, orderBy := [], offset := 0, limit := none,
    limitParameter := none, offsetParameter := none, outer := 0, aggregates := [], having := none, distinct := none }

/-- For all sources, condition, result columns and names, {name}`Query.simple` of them is a simple
query ({name}`Query.Simple`). -/
theorem Query.simple_isSimple (sources : List QuerySource) (filter : Option Expr) (columns : List Output)
    (names : List String) : (Query.simple sources filter columns names).Simple :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

/-- For every simple query, over any rows, the one result has as many rows as the rows that
{lit}`WHERE` keeps. Proof sketch: the window takes all records ({name}`Query.results_window`), the sort
keeps their number ({name}`stableSort_perm`), and a query without aggregate or {lit}`DISTINCT` has one record
for each kept row. -/
theorem Query.Simple.results_length {query : Query} (simple : query.Simple) (context : EvalContext)
    (rows : List (List Value)) : (query.results context rows).length = (filtered context query rows).length := by
  rw [Query.results_window]
  simp only [Query.sortedRecords, Query.uniqueRecords, simple.compound, simple.distinct, Query.stop, simple.limit,
    simple.offset, Option.map_none, windowRows, List.drop_zero, List.length_map]
  rw [(stableSort_perm _ _).length_eq]
  simp [records, simple.aggregate]

/-- For every simple query, the window binds to the query itself, for any values. Proof sketch:
{name}`Query.bindWindow_literal`; a simple query has no window parameter. -/
theorem Query.Simple.bindWindow {query : Query} (simple : query.Simple) (parameters : List Value) :
    query.bindWindow parameters = some query :=
  Query.bindWindow_literal parameters query simple.limitParameter simple.offsetParameter

/-- For every simple query, the one result has a row exactly when {lit}`WHERE` is true for some
source row. A query without {lit}`WHERE` has no condition to fail, so every source row passes and the result has
a row exactly when the source has a row. Proof sketch: {name}`Query.Simple.results_length` and {name}`mem_filtered`. -/
theorem Query.Simple.results_ne_nil_iff {query : Query} (simple : query.Simple) (context : EvalContext)
    (rows : List (List Value)) :
    query.results context rows ≠ [] ↔
      ∃ row ∈ rows, query.filter.all (fun condition => truthy (condition.eval context row)) = true := by
  rw [Ne, ← List.length_eq_zero_iff, simple.results_length, List.length_eq_zero_iff]
  constructor
  · intro nonempty
    obtain ⟨row, member⟩ := List.exists_mem_of_ne_nil _ nonempty
    exact ⟨row, ((mem_filtered context query rows row).mp member).1, ((mem_filtered context query rows row).mp member).2⟩
  · rintro ⟨row, member, kept⟩ empty
    have := (mem_filtered context query rows row).mpr ⟨member, kept⟩
    simp_all

/-- For every simple query, the one result has no row exactly when {lit}`WHERE` is not true for any
source row. A query without {lit}`WHERE` has every source row pass, so the result has no row exactly when the
source has no row. An empty source satisfies the condition on the right without further requirements. Proof
sketch: the negation of {name}`Query.Simple.results_ne_nil_iff`. -/
theorem Query.Simple.results_eq_nil_iff {query : Query} (simple : query.Simple) (context : EvalContext)
    (rows : List (List Value)) :
    query.results context rows = [] ↔
      ∀ row ∈ rows, query.filter.all (fun condition => truthy (condition.eval context row)) = false := by
  have := simple.results_ne_nil_iff context rows
  constructor
  · intro empty row member
    exact Bool.eq_false_iff.mpr fun kept => this.mpr ⟨row, member, kept⟩ empty
  · intro every
    exact Classical.byContradiction fun nonempty => by
      obtain ⟨row, member, kept⟩ := this.mp nonempty
      simp [every row member] at kept

/-- For every simple query whose expressions have no fallible call ({name}`Expr.isFallibleCall`),
in a context in which its expressions have no fault over the empty row and over each of the rows
({name}`Expr.evaluate`), the run over those rows gives the one result, no
fault, no overflow and no window mismatch. Proof sketch: the window binds to the query
({name}`Query.Simple.bindWindow`); no aggregate means no overflow; no {lit}`DISTINCT` means that the
rows are certain; and no expression has a fault, so the query neither certainly nor possibly fails
({name}`Query.mayFail_of_faultless`). -/
theorem Query.Simple.run_of_faultless {query : Query} (simple : query.Simple) (context : EvalContext)
    (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true) (rows : List (List Value))
    (faultless : ∀ row ∈ [] :: rows, ∀ expression ∈ query.expressions, (expression.evaluate context row).2 = .none) :
    query.run context rows =
      { rows := query.results context rows, fault := .none, overflow := false, mismatch := false } := by
  have noMustFail := Query.mustFail_of_faultless context query rows faultless
  unfold Query.run
  simp [simple.compound, simple.bindWindow, noMustFail, Query.mayFail_of_faultless context query rows plain faultless,
    Query.distinctCertain, simple.distinct, Query.fails, simple.aggregate]

/-- For every simple query whose expressions have no fallible call ({name}`Expr.isFallibleCall`),
in a quiet context ({name}`EvalContext.Quiet`), over any rows, the run gives the one result, no
fault, no overflow and no window mismatch. Proof sketch: {name}`Query.Simple.run_of_faultless`;
no expression has a fault in a quiet context ({name}`Expr.fault_of_plain`). -/
theorem Query.Simple.run_plain {query : Query} (simple : query.Simple) (context : EvalContext) (quiet : context.Quiet)
    (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true) (rows : List (List Value)) :
    query.run context rows =
      { rows := query.results context rows, fault := .none, overflow := false, mismatch := false } := by
  refine simple.run_of_faultless context plain rows fun row _ expression member => ?_
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  exact Expr.fault_of_plain context quiet row expression (plain expression member)

end Belay.Sqlite.Model.Resolved
