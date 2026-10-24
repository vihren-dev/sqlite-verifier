import Belay.Sqlite.Model.SimpleQueryLaws
import Belay.Sqlite.Model.Subqueries

set_option doc.verso true

/-! The run of a simple subquery (ADR 0017, S4): a subquery that only selects columns of its source
rows that {lit}`WHERE` keeps ({name}`Belay.Sqlite.Model.Resolved.Query.Simple`) and reads no cell of a
query around it, run for any outer row of the statement's query, gives one result in the
rows of the subquery, without fault, with certain rows. -/

namespace Belay.Sqlite.Model.Resolved

/-- For every simple query that reads no cell of an outer query, whose source rows in a context and database
have no fault, and whose expressions have no fallible call and no fault over the empty row and over each
source row, the run as a subquery for the outer row with no cells ({name}`Query.subqueryRun`)
has the one result of the query as its rows, no fault, and certain rows; it ends done. Its first row is certain
when the window of one row is ({name}`Query.windowCertain`). Proof sketch: the source rows after the empty outer row are the
source rows ({name}`Query.sourceAfter`), the window binds to the query
({name}`Query.Simple.bindWindow`), the run is the result without fault
({name}`Query.Simple.run_of_faultless`), and a window of no {lit}`LIMIT` and no {lit}`OFFSET` cuts
nowhere ({name}`certainCut`). -/
theorem Query.subqueryRun_simple (context : EvalContext) (database : Database) (query : Query) (simple : query.Simple)
    (outer : query.outer = 0) (source : SourceRows) (found : query.source context database = some source)
    (clean : source.fault = .none) (plain : query.expressions.all (!·.any Expr.isFallibleCall) = true)
    (faultless : ∀ row ∈ [] :: source.rows, ∀ expression ∈ query.expressions,
      (expression.evaluate context row).2 = .none) :
    query.subqueryRun context database [] =
      { rows := query.results context source.rows, fault := .none,
        firstCertain := query.windowCertain context source.rows (some 1), rowsCertain := true, ending := .done } := by
  have after : query.sourceAfter context [] database = some source := by
    simpa [Query.sourceAfter, outer, Query.source] using found
  unfold Query.subqueryRun
  rw [after]
  simp only [simple.bindWindow context.parameters, simple.run_of_faultless context plain source.rows faultless, clean]
  simp [Fault.join, Fault.soften, Query.windowCertain, certainCut, simple.limit, simple.offset]
