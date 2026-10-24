import Belay.Sqlite.Model.Resolution.SourceExpansion

set_option doc.verso true

/-! Enclosing scopes and source expansion for indexed subqueries (ADR 0019, D5). -/

namespace Belay.Sqlite.Model

/-- One query of a statement before resolution resolves its body: its scope, its pending
sources, the number of outer cells, and the aliases that its {lit}`WHERE` may name, of the
queries around it and of itself. -/
structure QueryScope where
  /-- The scope of the query, enclosed by those of the queries around it. -/
  scope : Scope
  /-- The sources of {lit}`FROM` whose expressions are not resolved yet. -/
  pending : List PendingSource
  /-- The number of cells of the queries around it. -/
  outer : Nat
  /-- The aliases of the result columns of the queries around it. -/
  outerAliases : List Identifier
  /-- The aliases of its own result columns and of the queries around it. -/
  aliases : List Identifier

/-- The scope of a write's table or of no table, as the scope of the statement around its
subqueries: no pending sources, outer cells or aliases. -/
def QueryScope.ofScope (scope : Scope) : QueryScope :=
  { scope, pending := [], outer := 0, outerAliases := [], aliases := [] }

/-- The indexed derived sources of a query, in FROM order. -/
def QueryScope.sourceIndexes (query : QueryScope) : List Nat :=
  query.pending.filterMap fun source => match source.item with
    | .subquery index _ => some index
    | .table _ | .each .. | .pragma _ => none

/-- The scope of subquery {lit}`index` in the scope of the query around it: the sources of its
{lit}`FROM` placed after the cells of that query, then the error of its {lit}`*` and {lit}`x.*`
({name}`starIssue`). A derived source can read enclosing queries, but not sources or aliases
of the query that uses it as a source. Paths start at {lit}`[field, index]`. -/
def subqueryScope (catalog : Catalog) (field : Nat) (around : QueryScope) (index : Nat) (subquery : Syntax.Subquery)
    (subqueries : List Syntax.Subquery := []) :
    Except SourceIssue QueryScope := do
  let derived := around.sourceIndexes.contains index
  let outer := if derived then (around.scope.filter (·.depth > 0)).map
    (fun source => { source with depth := source.depth - 1 }) else around.scope
  let aliases := if derived then around.outerAliases else around.aliases
  let width := if derived then around.outer else around.scope.columns.length
  let (pending, inner) ←
    if (subqueries.drop (index + 1)).isEmpty then
      (resolveSources catalog subquery.source subquery.joins width).mapError (·.under [field, index])
    else
      resolveSources catalog subquery.source subquery.joins width
        (sourceExpansion catalog field subqueries (some index)) [field, index]
  let scope := Scope.enclose outer inner
  if let some issue := starIssue scope subquery.columns then throw (.value (issue.under [field, index]))
  pure { scope, pending, outer := width, outerAliases := aliases,
         aliases := (resultAliases scope subquery.columns).filterMap id ++ aliases }

/-- The scopes of the subqueries, in the order of the list, around the statement's query or
write {lit}`main`, whose compound is {lit}`compound`: each in the order of {name}`scopeOrder`
({name}`subqueryScope`), around the statement's query or an earlier subquery. A subquery whose
parent is a later one or is not visited, and a subquery under a compound that is not one of its
terms, such as a subquery in the compound's {lit}`ORDER BY`, are
{name}`RestrictionKind.subqueryHere`. -/
def subqueryScopes (catalog : Catalog) (field : Nat) (main : QueryScope) (compound : Option Syntax.Compound)
    (subqueries : List Syntax.Subquery) : Except SourceIssue (List QueryScope) := do
  let found ← (scopeOrder compound subqueries (subqueries.length + 1) none).foldlM (fun found index => do
    let refused := SourceIssue.value (.restriction [field, index] .subqueryHere)
    let some subquery := subqueries[index]? | throw refused
    let around? := match subquery.parent with
      | none => some main
      | some parent => if parent < index then List.lookup parent found else none
    match around?, (compoundOf compound subqueries subquery.parent).all (·.terms.contains index) with
    | some around, true => pure (found ++ [(index, ← subqueryScope catalog field around index subquery subqueries)])
    | some _, false | none, true | none, false => throw refused) []
  (List.range subqueries.length).mapM fun index => match List.lookup index found with
    | some scope => pure scope
    | none => throw (.value (.restriction [field, index] .subqueryHere))

end Belay.Sqlite.Model
