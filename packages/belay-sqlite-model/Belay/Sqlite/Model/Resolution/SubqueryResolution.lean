import Belay.Sqlite.Model.Resolution.CompoundResolution
import Belay.Sqlite.Model.QueryRun

set_option doc.verso true

/-! Resolution of the subqueries of a statement (ADR 0018, D1). The scopes go outward-in:
the statement's query or write, then each subquery in the order in which SQLite finds its tables
({name}`Belay.Sqlite.Model.scopeOrder`), enclosed by the scope of the query around it
({name}`Belay.Sqlite.Model.Scope.enclose`), with its cells after the outer cells. The bodies go
inward-out, from the last subquery to the first and then the statement's own expressions,
because an expression needs the shapes of the subqueries that it names
({name}`Belay.Sqlite.Model.SubqueryShape`). A compound subquery (ADR 0019, D3) has its terms after
it, so their bodies come before its own; the terms of a compound go from right to left, as
SQLite resolves them. An issue of subquery {lit}`i` is at the path
{lit}`[field, i]` and the path within its clauses, where {lit}`field` is the child of the
statement's syntax that holds its subqueries: 8 for {lit}`SELECT`. -/

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

/-- A source issue at a path of the statement: a value issue under the path, and a missing
table as it is. -/
def SourceIssue.under (path : List Nat) : SourceIssue → SourceIssue
  | .value issue => .value (issue.under path)
  | .noSuchTable name => .noSuchTable name

/-- The scope of a write's table or of no table, as the scope of the statement around its
subqueries: no pending sources, outer cells or aliases. -/
def QueryScope.ofScope (scope : Scope) : QueryScope :=
  { scope, pending := [], outer := 0, outerAliases := [], aliases := [] }

/-- The scope of subquery {lit}`index` in the scope of the query around it: the sources of its
{lit}`FROM` placed after the cells of that query, then the error of its {lit}`*` and {lit}`x.*`
({name}`starIssue`). Paths start at {lit}`[field, index]`. -/
def subqueryScope (catalog : Catalog) (field : Nat) (around : QueryScope) (index : Nat) (subquery : Syntax.Subquery) :
    Except SourceIssue QueryScope := do
  let width := around.scope.columns.length
  let (pending, inner) ← (resolveSources catalog subquery.source subquery.joins width).mapError (·.under [field, index])
  let scope := Scope.enclose around.scope inner
  if let some issue := starIssue scope subquery.columns then throw (.value (issue.under [field, index]))
  pure { scope, pending, outer := width, outerAliases := around.aliases,
         aliases := (resultAliases scope subquery.columns).filterMap id ++ around.aliases }

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
    | some around, true => pure (found ++ [(index, ← subqueryScope catalog field around index subquery)])
    | some _, false | none, true | none, false => throw refused) []
  (List.range subqueries.length).mapM fun index => match List.lookup index found with
    | some scope => pure scope
    | none => throw (.value (.restriction [field, index] .subqueryHere))

/-- The shape of a resolved subquery ({name}`SubqueryShape`): the query around it, its number
of result columns, the affinity and collations of its first result column, and the lowest
cell that it or a subquery that it names reads. -/
def subqueryShape (scope : Scope) (shapes : SubqueryShapes) (subquery : Syntax.Subquery) (query : Resolved.Query)
    (affinity : Option Affinity) : SubqueryShape :=
  let (explicitCollation, columnCollation) := firstCollations scope subquery.columns
  { parent := subquery.parent, columns := query.columns.length, affinity, explicitCollation, columnCollation,
    lowest := query.expressions.foldl (fun lowest expression => minPosition lowest (expression.lowestRead shapes)) none }

/-- Resolve the bodies of the subqueries from the last to the first, each with the shapes of the
subqueries after it: one {lit}`SELECT` by {name}`resolveQueryBody`, a compound from its terms by
{name}`resolveCompoundBody`; then a term with a term on its right gives
{name}`compoundColumnsIssue`. The terms of the statement's query are those of
{lit}`compound`. The result is the resolved subqueries and their shapes, in the order of the
list. Paths start at {lit}`[field, index]`. -/
def resolveSubqueryBodies (dqs : Bool) (field : Nat) (compound : Option Syntax.Compound) (scopes : List QueryScope)
    (subqueries : List Syntax.Subquery) : Except ValueIssue (List Resolved.Query × List SubqueryShape) :=
  ((List.range subqueries.length).zip (scopes.zip subqueries)).foldr (fun (index, around, subquery) later => do
    let (queries, shapes) ← later
    let current : SubqueryShapes := { current := some index, later := shapes, outer := around.outer }
    let body : Except ValueIssue (Resolved.Query × SubqueryShape) := match subquery.compound with
      | some terms => do
        resolveCompoundBody dqs around.outer subquery terms
          (← compoundTerms (index + 1) (some index) terms (scopes.map QueryScope.scope) subqueries queries shapes)
      | none => do
        let (query, affinity) ← resolveQueryBody dqs around.scope current around.outerAliases around.pending subquery
        pure (query, subqueryShape around.scope current subquery query affinity)
    let (query, shape) ← body.mapError fun (issue : ValueIssue) => issue.under [field, index]
    if let some issue := compoundColumnsIssue (compoundOf compound subqueries subquery.parent) index
        shape.columns (index + 1) shapes then throw issue
    pure (query :: queries, shape :: shapes)) (.ok ([], []))

/-- Resolve the subqueries of a statement around whose own expressions is {lit}`main`: their
scopes ({name}`subqueryScopes`), then their bodies ({name}`resolveSubqueryBodies`), with the
statement's syntax holding them at child {lit}`field`. -/
def resolveSubqueries (dqs : Bool) (catalog : Catalog) (field : Nat) (main : QueryScope)
    (subqueries : List Syntax.Subquery) : Except SourceIssue (List Resolved.Query × List SubqueryShape) := do
  let scopes ← subqueryScopes catalog field main none subqueries
  (resolveSubqueryBodies dqs field none scopes subqueries).mapError .value

/-- Whether a subquery reads the table at the catalog position directly. -/
def Resolved.Query.readsTable (position : Nat) (query : Resolved.Query) : Bool :=
  query.sources.any (·.source == .table position)

end Belay.Sqlite.Model
