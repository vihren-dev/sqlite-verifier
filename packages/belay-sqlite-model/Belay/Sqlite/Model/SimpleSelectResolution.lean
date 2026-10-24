import Belay.Sqlite.Model.SimpleQueryLaws
import Belay.Sqlite.Model.Resolution.Resolve

set_option doc.verso true

/-! The resolution of a simple {lit}`SELECT` (ADR 0017, S4): a statement with one query, without
subqueries, joins, grouping, ordering, window, {lit}`HAVING`, {lit}`DISTINCT` and compound, and
with result columns that call no aggregate. Resolution turns it into the simple query
({name}`Belay.Sqlite.Model.Resolved.Query.Simple`) of its resolved sources, result columns and
{lit}`WHERE` condition. The lemma takes the resolved parts as hypotheses, because the catalog is
free: a proof of a claim over every database gives them from the table that it assumes. -/

namespace Belay.Sqlite.Model

/-- A simple query in the syntax: no join, grouping, ordering, {lit}`LIMIT`, {lit}`OFFSET`,
{lit}`HAVING`, {lit}`DISTINCT` and compound, and no aggregate call in a result column. For
example, {lit}`SELECT 1 FROM t WHERE x = 0` is simple. -/
structure Syntax.Subquery.Simple (query : Syntax.Subquery) : Prop where
  /-- The query has no join. -/
  joins : query.joins = []
  /-- The query has no {lit}`GROUP BY`. -/
  groupBy : query.groupBy = []
  /-- The query has no {lit}`ORDER BY`. -/
  orderBy : query.orderBy = []
  /-- The query has no {lit}`LIMIT`. -/
  limit : query.limit = none
  /-- The query has no {lit}`OFFSET`. -/
  offset : query.offset = none
  /-- The query has no {lit}`HAVING`. -/
  having : query.having = none
  /-- The query is no {lit}`SELECT DISTINCT`. -/
  distinct : query.distinct = false
  /-- The query is no compound. -/
  compound : query.compound = none
  /-- No result column calls an aggregate. -/
  columns : (query.columns.all fun
    | .expression value _ _ => value.aggregateCalls.isEmpty
    | .star | .sourceStar _ => true) = true

/-- The {lit}`WHERE` condition of a query resolves to the resolved condition: there is none and no
resolved condition, or there is a term that names no alias of the result columns and resolves, as
a condition, to an expression, with the shapes of the subqueries that it names (by default, none). -/
def FilterResolves (dqs : Bool) (scope : Scope) (aliases : List Identifier) (filter : Option Syntax.Expr)
    (condition : Option Resolved.Expr) (shapes : SubqueryShapes := { later := [] }) : Prop :=
  (filter = none ∧ condition = none) ∨
    ∃ (term : Syntax.Expr) (expression : Resolved.Expr) (affinity : Option Affinity),
      filter = some term ∧ condition = some expression ∧ namesAlias scope aliases term = false ∧
        resolveOperand dqs scope shapes true term = .ok (expression, affinity)

/-- For every statement with a single query, without joins, subqueries and compound, whose sources
resolve, whose result columns hold no {lit}`*` that SQLite refuses, and whose body resolves to a
query, resolution gives that query and no subquery, and leaves the catalog as it is. Proof sketch:
unfold the resolver; without subqueries it has no scope, no subquery body and no check of
fallible calls to make, so only the sources, the star check and the body remain. -/
theorem resolveSelect_no_subqueries (context : ResolveContext) (catalog : Catalog) (query : Syntax.Subquery)
    (q : Resolved.Query) (affinity : Option Affinity) (pending : List PendingSource) (scope : Scope)
    (noCompound : query.compound = none) (noJoins : query.joins = [])
    (sourcesOk : resolveSources catalog query.source [] = .ok (pending, scope))
    (noStar : starIssue scope query.columns = none)
    (body : resolveQueryBody context.profile.dqsDml scope { later := [] } [] pending query = .ok (q, affinity)) :
    resolveSelect context catalog query [] = .ok (.query q [], catalog) := by
  have noSources : sourceExpansion catalog 8 [] none =
      (fun _ => .error (.value (.restriction [] .subqueryHere))) := by funext index; rfl
  unfold resolveSelect
  rw [noSources]
  simp [noJoins, sourcesOk, subqueryScopes, scopeOrder, resolveSubqueryBodies, subqueryBodyOrder, QueryScope.refresh, Scope.refreshSources, noStar, noCompound, body, Bind.bind,
    Except.bind, Except.mapError, Pure.pure, Except.pure]

/-- For every simple query ({name}`Syntax.Subquery.Simple`) whose pending sources, result columns and
{lit}`WHERE` condition resolve, and in which no fallible call in a scalar result column has an aggregate value
below it (the hypothesis {lit}`noFeed`), the body resolves to the simple resolved query of its sources, columns and condition, with the names of the
columns and the affinity of the first one. Proof sketch: unfold the resolver and rewrite its
aggregate flag and its aggregate calls, which are none for a simple query, then follow its steps
with the hypotheses; the clauses that a simple query lacks resolve to their empty forms. -/
theorem resolveQueryBody_simple (dqs : Bool) (scope : Scope) (current : Option Nat) (later : List SubqueryShape)
    (outerAliases : List Identifier) (pending : List PendingSource) (query : Syntax.Subquery)
    (simple : query.Simple) (resolved : List (List (Resolved.Output × String × Option Affinity)))
    (condition : Option Resolved.Expr) (sources : List Resolved.QuerySource)
    (columns : resolveAll (resolveResultColumn dqs scope { current, later }) query.columns = .ok resolved)
    (filter : FilterResolves dqs scope ((resultAliases scope query.columns).filterMap id ++ outerAliases) query.filter condition { current, later })
    (pendingOk : resolvePendingSources dqs scope pending = .ok sources)
    (noFeed : (resolved.flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false) :
    resolveQueryBody dqs scope { current, later } outerAliases pending query =
      .ok (Resolved.Query.simple sources condition (resolved.flatten.map (·.1)) (resolved.flatten.map (·.2.1)),
           resolved.flatten.head?.bind (·.2.2)) := by
  unfold Resolved.Query.simple
  obtain ⟨-, noGroup, noOrder, noLimit, noOffset, noHaving, notDistinct, -, noAggregate⟩ := simple
  have columnFree : ∀ value alias text, Syntax.ResultColumn.expression value alias text ∈ query.columns →
      value.aggregateCalls = [] := fun value alias text member => by
    simp only [List.all_eq_true] at noAggregate
    simpa [List.isEmpty_iff] using noAggregate _ member
  have noCalls : ∀ g : Syntax.ResultColumn → List Syntax.Expr,
      (∀ value alias text, Syntax.ResultColumn.expression value alias text ∈ query.columns →
        g (.expression value alias text) = []) → g .star = [] → (∀ source, g (.sourceStar source) = []) →
      query.columns.flatMap g = [] := fun g expression star sourceStar =>
    List.flatMap_eq_nil_iff.mpr fun column member => by
      cases column with
      | star => exact star
      | sourceStar source => exact sourceStar source
      | expression value alias text => exact expression value alias text member
  have notAggregate : ∀ g : Syntax.ResultColumn → Bool,
      (∀ value alias text, Syntax.ResultColumn.expression value alias text ∈ query.columns →
        g (.expression value alias text) = false) → g .star = false → (∀ source, g (.sourceStar source) = false) →
      query.columns.any g = false := fun g expression star sourceStar =>
    List.any_eq_false.mpr fun column member => by
      cases column with
      | star => simp [star]
      | sourceStar source => simp [sourceStar source]
      | expression value alias text => simp [expression value alias text member]
  have distinctNil : Syntax.Expr.distinctList [] = [] := rfl
  unfold resolveQueryBody
  simp only [noGroup, noOrder, noLimit, noOffset, noHaving, notDistinct]
  rw [notAggregate _ ?flagColumn rfl (fun _ => rfl)]
  simp only [List.isEmpty_nil, Bool.not_true, Bool.or_false, Bool.false_and, Option.toList_none, List.flatMap_nil,
    List.append_nil, ite_false, Bool.false_eq_true]
  rw [noCalls _ ?callColumn rfl (fun _ => rfl)]
  simp only [distinctNil]
  simp only [columns, pendingOk]
  rcases filter with ⟨found, rfl⟩ | ⟨term, expression, affinity, found, rfl, names, resolves⟩
  · simp [resolveAll, resolveAllFrom, windowValue, windowSkipsFailure, Bind.bind, Except.bind, pure, Except.pure, found]
    refine (ite_eq_right_of_eq_false _ _ (eq_false fun feed => ?_)).trans rfl
    rw [List.append_nil, List.append_nil] at feed
    exact absurd (feed.symm.trans noFeed) (by simp)
  · simp [resolveAll, resolveAllFrom, windowValue, windowSkipsFailure, Bind.bind, Except.bind, pure, Except.pure, found,
      names, resolves, Model.condition, Functor.map, Except.map]
    refine (ite_eq_right_of_eq_false _ _ (eq_false fun feed => ?_)).trans rfl
    rw [List.append_nil, List.append_nil] at feed
    exact absurd (feed.symm.trans noFeed) (by simp)
  case flagColumn => intro value alias text member; simp [columnFree value alias text member]
  case callColumn => intro value alias text member; simp [columnFree value alias text member]

/-- For every simple statement ({name}`Syntax.Subquery.Simple`) without subqueries, whose sources resolve,
whose result columns have no star issue ({name}`starIssue`) and resolve, whose {lit}`WHERE` condition resolves
as {name}`FilterResolves` says (the condition is absent, or it names no alias of a result column and its operand
resolves), whose pending sources resolve, and in which no fallible call in a scalar result column has an
aggregate value below it, resolution gives the simple resolved query of those parts, with no subquery, and
leaves the catalog as it is. Proof sketch:
{name}`resolveSelect_no_subqueries` with {name}`resolveQueryBody_simple`. -/
theorem resolveSelect_simple (context : ResolveContext) (catalog : Catalog) (query : Syntax.Subquery)
    (simple : query.Simple) (pending : List PendingSource) (scope : Scope)
    (resolved : List (List (Resolved.Output × String × Option Affinity))) (condition : Option Resolved.Expr)
    (sources : List Resolved.QuerySource)
    (sourcesOk : resolveSources catalog query.source [] = .ok (pending, scope))
    (noStar : starIssue scope query.columns = none)
    (columns : resolveAll (resolveResultColumn context.profile.dqsDml scope { later := [] }) query.columns = .ok resolved)
    (filter : FilterResolves context.profile.dqsDml scope ((resultAliases scope query.columns).filterMap id) query.filter
      condition)
    (pendingOk : resolvePendingSources context.profile.dqsDml scope pending = .ok sources)
    (noFeed : (resolved.flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false) :
    resolveSelect context catalog query [] =
      .ok (.query (Resolved.Query.simple sources condition (resolved.flatten.map (·.1)) (resolved.flatten.map (·.2.1))) [],
        catalog) :=
  resolveSelect_no_subqueries context catalog query _ _ pending scope simple.compound simple.joins sourcesOk noStar
    (resolveQueryBody_simple context.profile.dqsDml scope none [] [] pending query simple resolved condition sources
      columns (by simpa using filter) pendingOk noFeed)

/-- For every SELECT without subqueries, joins or compound, if its sources resolve, its result
columns have no star issue, and its body reports a prepare error, the SELECT reports that error
and leaves the catalog unchanged. This includes a missing column in any body clause.
Proof sketch: the source and star checks pass; the body error passes through the common resolver. -/
theorem resolveSelect_no_subqueries_prepareError (context : ResolveContext) (catalog : Catalog)
    (query : Syntax.Subquery) (pending : List PendingSource) (scope : Scope) (error : ExprError)
    (noCompound : query.compound = none) (noJoins : query.joins = [])
    (sourcesOk : resolveSources catalog query.source [] = .ok (pending, scope))
    (noStar : starIssue scope query.columns = none)
    (body : resolveQueryBody context.profile.dqsDml scope { later := [] } [] pending query = .error (.prepare error)) :
    resolveSelect context catalog query [] = .ok (.prepareError (.expression error), catalog) := by
  have noSources : sourceExpansion catalog 8 [] none =
      (fun _ => .error (.value (.restriction [] .subqueryHere))) := by funext index; rfl
  unfold resolveSelect
  rw [noSources]
  simp [noJoins, sourcesOk, subqueryScopes, scopeOrder, resolveSubqueryBodies, subqueryBodyOrder, QueryScope.refresh, Scope.refreshSources, noStar, noCompound, body,
    issueResolution, prepareError, Bind.bind, Except.bind, Except.mapError, Pure.pure, Except.pure]

end Belay.Sqlite.Model
