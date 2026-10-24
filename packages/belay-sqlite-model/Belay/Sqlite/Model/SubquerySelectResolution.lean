import Belay.Sqlite.Model.SimpleStatementResolution
import Belay.Sqlite.Model.SubqueryExprResolutionLaws

set_option doc.verso true

/-! The resolution of a {lit}`SELECT` without {lit}`FROM` and with one subquery (ADR 0017, S4):
the statement {lit}`SELECT e WHERE c(q)` where {lit}`c` names the subquery {lit}`q` once or more. The
subquery is resolved first, in the scope of its own sources, and the shapes of the result give the
resolution of the statement's own query. The lemma takes both resolutions as hypotheses, because
the catalog is free: a proof of a claim over every database gives them from the table that the
subquery names. -/

namespace Belay.Sqlite.Model

/-- For every {lit}`SELECT` without {lit}`FROM`, joins and compound, with one subquery that has no parent
and no compound, whose sources and body resolve, and whose own body resolves with the shape of that
subquery, and whose resolved expressions have no fallible call, resolution gives the statement's
query and the one resolved subquery, and leaves the catalog as it is. Proof sketch: unfold the resolver; the
statement's own scope is empty, so the scopes of the subquery are its own scope and the order of the
subqueries is the one subquery; the body of the subquery resolves as hypothesised and its shape is the one that the
statement's body reads; the check of fallible calls in a statement with a subquery passes because
the statement's expressions have none. -/
theorem resolveSelect_noFrom_one_subquery (context : ResolveContext) (catalog : Catalog) (main sub : Syntax.Subquery)
    (mainNoFrom : main.source = none) (mainNoJoins : main.joins = []) (mainNoCompound : main.compound = none)
    (mainNoStar : starIssue [] main.columns = none)
    (parentless : sub.parent = none) (subNoCompound : sub.compound = none)
    (pending : List PendingSource) (inner : Scope)
    (subSources : resolveSources catalog sub.source sub.joins = .ok (pending, inner))
    (subNoStar : starIssue inner sub.columns = none)
    (subQuery : Resolved.Query) (affinity : Option Affinity)
    (subBody : resolveQueryBody context.profile.dqsDml inner { current := some 0 }
      ((resultAliases [] main.columns).filterMap id) pending sub = .ok (subQuery, affinity))
    (shape : SubqueryShape) (shapeIs : shape = subqueryShape inner { current := some 0 } sub subQuery affinity)
    (mainQuery : Resolved.Query) (mainAffinity : Option Affinity)
    (mainBody : resolveQueryBody context.profile.dqsDml [] { later := [shape] } [] [] main = .ok (mainQuery, mainAffinity))
    (plain : mainQuery.expressions.all (!·.any Resolved.Expr.isFallibleCall) = true) :
    resolveSelect context catalog main [sub] = .ok (.query mainQuery [subQuery], catalog) := by
  have order : scopeOrder none [sub] 2 none = [0] := by
    simp [scopeOrder, parentless, compoundOf]
  have noFallible : (mainQuery.sources.isEmpty && mainQuery.expressions.any (·.any Resolved.Expr.isFallibleCall)) = false := by
    simp only [List.all_eq_true, Bool.not_eq_true'] at plain
    simp [List.any_eq_false.mpr fun expression member => by simpa using plain expression member]
  have noMain : resolveSources catalog none [] 0 (sourceExpansion catalog 8 [sub] none) = .ok ([], []) := rfl
  have unique : ([0] : List Nat).eraseDups = [0] := rfl
  have noSource : (subqueryShape inner { current := some 0 } sub subQuery affinity).source = none := rfl
  subst shapeIs
  unfold resolveSelect
  simp [compoundColumnsIssue, noMain, mainNoFrom, mainNoJoins, mainNoCompound, mainNoStar, subqueryScopes, order, subqueryScope,
    parentless, Scope.columns, Scope.enclose, subSources, subNoStar, resolveSubqueryBodies, subqueryBodyOrder, QueryScope.sourceIndexes, QueryScope.refresh, Scope.refreshSources,
    unique, noSource, subNoCompound, subBody,
    mainBody, noFallible, Bind.bind, Except.bind, Except.mapError, Pure.pure, Except.pure, compoundOf]

/-- For every {lit}`SELECT` statement of a query without parent and a list of subqueries, whose resolution of
the query with the subqueries against the catalog of the state gives a resolved statement and
the same catalog, the resolution of the statement gives that statement and leaves the state as it is.
Proof sketch: the statement builds the query from its clauses, and the resolution of the
statement is that of the query. -/
theorem resolveStatement_select_of_resolveSelect (context : ResolveContext) (state : ResolveState)
    (query : Syntax.Subquery) (subqueries : List Syntax.Subquery) (parent : query.parent = none)
    (statement : Resolved.Statement)
    (resolved : resolveSelect context state.catalog query subqueries = .ok (statement, state.catalog)) :
    resolveStatement context state (.select query.columns query.source query.joins query.filter query.groupBy
        query.orderBy query.limit query.offset subqueries query.having query.distinct query.compound) =
      .ok (statement, state) := by
  have rebuilt : ({ query with parent := none } : Syntax.Subquery) = query := by
    cases query
    simp_all
  have unfolded : resolveStatement context state (.select query.columns query.source query.joins query.filter
      query.groupBy query.orderBy query.limit query.offset subqueries query.having query.distinct query.compound) =
      state.withCatalog (resolveSelect context state.catalog { query with parent := none } subqueries) := rfl
  rw [unfolded, rebuilt, resolved]
  rfl

end Belay.Sqlite.Model
