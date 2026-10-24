import Belay.Sqlite.Model.SimpleSourceResolution

set_option doc.verso true

/-! The resolution of a simple {lit}`SELECT` statement as a statement (ADR 0017, S4): the
statement with the clauses of a simple query and no list of subqueries resolves to the query of
{name}`Belay.Sqlite.Model.resolveSelect_simple` and leaves the state as it is. The forms with one
table and without {lit}`FROM` give their sources. -/

namespace Belay.Sqlite.Model

/-- A {lit}`SELECT` without {lit}`FROM` and without joins resolves to no source and no scope, for
any catalog. Proof sketch: unfold the resolver; there is no table to look up. -/
theorem resolveSources_none (catalog : Catalog) :
    resolveSources catalog none [] = .ok ([], []) := by
  simp [resolveSources]

/-- For every simple query ({name}`Syntax.Subquery.Simple`) without parent, whose parts resolve as
in {name}`resolveSelect_simple`, the statement of its clauses with an empty list of subqueries
resolves to the simple resolved query of those parts, with no subquery, and leaves the state as it
is. Proof sketch: the statement builds the query from its clauses, and {name}`resolveSelect_simple`
gives its resolution; the catalog of the result is the catalog of the state. -/
theorem resolveStatement_select_simple (context : ResolveContext) (state : ResolveState) (query : Syntax.Subquery)
    (simple : query.Simple) (parent : query.parent = none) (pending : List PendingSource) (scope : Scope)
    (resolved : List (List (Resolved.Output × String × Option Affinity))) (condition : Option Resolved.Expr)
    (sources : List Resolved.QuerySource)
    (sourcesOk : resolveSources state.catalog query.source [] = .ok (pending, scope))
    (noStar : starIssue scope query.columns = none)
    (columns : resolveAll (resolveResultColumn context.profile.dqsDml scope { later := [] }) query.columns = .ok resolved)
    (filter : FilterResolves context.profile.dqsDml scope ((resultAliases scope query.columns).filterMap id) query.filter
      condition)
    (pendingOk : resolvePendingSources context.profile.dqsDml scope pending = .ok sources)
    (noFeed : (resolved.flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false) :
    resolveStatement context state (.select query.columns query.source query.joins query.filter query.groupBy
        query.orderBy query.limit query.offset [] query.having query.distinct query.compound) =
      .ok (.query (Resolved.Query.simple sources condition (resolved.flatten.map (·.1)) (resolved.flatten.map (·.2.1))) [],
        state) := by
  have rebuilt : ({ query with parent := none } : Syntax.Subquery) = query := by
    cases query
    simp_all
  have unfolded : resolveStatement context state (.select query.columns query.source query.joins query.filter
      query.groupBy query.orderBy query.limit query.offset [] query.having query.distinct query.compound) =
      state.withCatalog (resolveSelect context state.catalog { query with parent := none } []) := rfl
  rw [unfolded, rebuilt]
  rw [resolveSelect_simple context state.catalog query simple pending scope resolved condition sources sourcesOk noStar
    columns filter pendingOk noFeed]
  rfl

/-- For every {lit}`SELECT` of one table (no joins, no table-function arguments), whose table the
catalog does not have and whose name is neither a table of SQLite itself ({name}`reservedName`) nor a
table-valued function ({name}`eponymousName`), the statement resolves to the prepare error
{lit}`no such table`, for any clauses after {lit}`FROM`, and leaves the state as it is. The source reference has no indexed query.
Proof sketch:
the lookup of the first table fails with that error, which the resolver of the statement turns
into the prepare error. -/
theorem resolveStatement_select_missing_table (context : ResolveContext) (state : ResolveState) (query : Syntax.Subquery)
    (reference : Syntax.TableReference) (source : query.source = some reference) (noJoins : query.joins = [])
    (namedSource : reference.query = none) (arguments : reference.arguments = none) (missing : state.catalog.findTable reference.table = none)
    (notReserved : reservedName reference.table = false) (notFunction : eponymousName reference.table = false) :
    resolveStatement context state (.select query.columns query.source query.joins query.filter query.groupBy
        query.orderBy query.limit query.offset [] query.having query.distinct query.compound) =
      .ok (.prepareError (.noSuchTable reference.table), state) := by
  have unfolded : resolveStatement context state (.select query.columns query.source query.joins query.filter
      query.groupBy query.orderBy query.limit query.offset [] query.having query.distinct query.compound) =
      state.withCatalog (resolveSelect context state.catalog { query with parent := none } []) := rfl
  rw [unfolded]
  unfold resolveSelect
  simp [source, noJoins, resolveSources, resolveReference, namedSource, arguments, resolveTableReference, missing, notReserved,
    notFunction, Except.mapError, SourceIssue.under, maximumJoinTables, prepareError, ResolveState.withCatalog, Bind.bind, Except.bind, Functor.map, Except.map]

/-- For every SELECT without subqueries, joins, compound or a parent, whose sources resolve,
whose result columns pass the star check, and whose body reports a prepare error, the statement
resolves to that error and leaves the whole resolution state unchanged.
Proof sketch: lift {name}`resolveSelect_no_subqueries_prepareError` through the state wrapper. -/
theorem resolveStatement_select_body_prepareError (context : ResolveContext) (state : ResolveState)
    (query : Syntax.Subquery) (pending : List PendingSource) (scope : Scope) (error : ExprError)
    (parent : query.parent = none) (noCompound : query.compound = none) (noJoins : query.joins = [])
    (sourcesOk : resolveSources state.catalog query.source [] = .ok (pending, scope))
    (noStar : starIssue scope query.columns = none)
    (body : resolveQueryBody context.profile.dqsDml scope { later := [] } [] pending query = .error (.prepare error)) :
    resolveStatement context state (.select query.columns query.source query.joins query.filter query.groupBy
      query.orderBy query.limit query.offset [] query.having query.distinct query.compound) =
      .ok (.prepareError (.expression error), state) := by
  have rebuilt : ({ query with parent := none } : Syntax.Subquery) = query := by cases query; simp_all
  change state.withCatalog (resolveSelect context state.catalog { query with parent := none } []) = _
  rw [rebuilt, resolveSelect_no_subqueries_prepareError context state.catalog query pending scope error
    noCompound noJoins sourcesOk noStar body]
  rfl

end Belay.Sqlite.Model
