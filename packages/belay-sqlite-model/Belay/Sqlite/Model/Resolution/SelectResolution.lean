import Belay.Sqlite.Model.Resolution.SubqueryResolution

set_option doc.verso true

/-! Resolution of a {lit}`SELECT` statement with its subqueries (ADR 0018, D1): the sources of
its query, its subqueries ({lit}`SubqueryResolution`), whose syntax is at child 8 of
{lit}`Syntax.Statement.select`, and then the body of its query, or of its compound from the
terms among its subqueries (ADR 0019, D3). -/

namespace Belay.Sqlite.Model

/-- Resolve a {lit}`SELECT` with its subqueries: the statement's
query and its subqueries, or SQLite's {lit}`no such table: %s`, a prepare error or a
restriction. SQLite expands the {lit}`*` of the statement's query ({name}`starIssue`) before
its subqueries. A compound query resolves from its terms ({name}`resolveCompoundBody`). A query
without {lit}`FROM`, or a term of the compound without {lit}`FROM`, that has a call that can
fail, in a statement with a subquery that is no term, is
{name}`RestrictionKind.subqueryFallibleCall`. -/
def resolveSelect (context : ResolveContext) (catalog : Catalog) (query : Syntax.Subquery)
    (subqueries : List Syntax.Subquery) : StatementResolution :=
  let dqs := context.profile.dqsDml
  let resolved : Except SourceIssue (Resolved.Query × List Resolved.Query) := do
    let (pending, scope) ← resolveSources catalog query.source query.joins
    if let some issue := starIssue scope query.columns then throw (.value issue)
    let main : QueryScope := { scope, pending, outer := 0, outerAliases := [],
                               aliases := (resultAliases scope query.columns).filterMap id }
    let scopes ← subqueryScopes catalog 8 main query.compound subqueries
    let (resolvedSubqueries, shapes) ← (resolveSubqueryBodies dqs 8 query.compound scopes subqueries).mapError .value
    let body : Except ValueIssue (Resolved.Query × List Resolved.Query) := match query.compound with
      | some compound => do
        let terms ← compoundTerms 0 none compound (scopes.map QueryScope.scope) subqueries resolvedSubqueries shapes
        pure ((← resolveCompoundBody dqs 0 query compound terms).1, terms.map CompoundTerm.query)
      | none => do
        let (resolved, _) ← resolveQueryBody dqs scope { later := shapes } [] pending query
        pure (resolved, [resolved])
    let (resolvedQuery, ran) ← body.mapError SourceIssue.value
    let terms := (query.compound.map Syntax.Compound.terms).getD []
    if (List.range subqueries.length).any (!terms.contains ·) &&
        ran.any fun (ran : Resolved.Query) => ran.sources.isEmpty && ran.expressions.any (·.any Resolved.Expr.isFallibleCall) then
      throw (SourceIssue.value (ValueIssue.restriction [] .subqueryFallibleCall))
    pure (resolvedQuery, resolvedSubqueries)
  match resolved with
  | .ok (resolvedQuery, resolvedSubqueries) => .ok (.query resolvedQuery resolvedSubqueries, catalog)
  | .error (.noSuchTable name) => prepareError catalog (.noSuchTable name)
  | .error (.value issue) => issueResolution catalog [] issue

/-- For every successful resolution of a {lit}`SELECT`, the catalog is unchanged and the
resolved statement applied to the input catalog gives the input catalog again
({lit}`Resolved.Statement.applyCatalog`); the statement is not transaction control.
Proof sketch: every branch of the resolver returns the input catalog and a query or a
prepare error. -/
theorem resolveSelect_same (context : ResolveContext) (catalog after : Catalog)
    (query : Syntax.Subquery) (subqueries : List Syntax.Subquery) (statement : Resolved.Statement)
    (ok : resolveSelect context catalog query subqueries = .ok (statement, after)) :
    after = catalog ∧ statement.applyCatalog catalog = catalog ∧ statement.isControl = false := by
  unfold resolveSelect at ok
  simp only [prepareError, issueResolution] at ok
  repeat' split at ok
  all_goals first | (cases ok; exact ⟨rfl, rfl, rfl⟩) | (cases ok)

end Belay.Sqlite.Model
