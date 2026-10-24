import Belay.Sqlite.Model.Resolution.CompoundResolution
import Belay.Sqlite.Model.Resolution.SubqueryScopes
import Belay.Sqlite.Model.QueryRun

set_option doc.verso true

/-! Resolution of the subqueries of a statement (ADR 0018, D1). The scopes go outward-in:
the statement's query or write, then each subquery in the order in which SQLite finds its tables
({name}`Belay.Sqlite.Model.scopeOrder`), enclosed by the scope of the query around it
({name}`Belay.Sqlite.Model.Scope.enclose`), with its cells after the outer cells. The bodies follow their dependencies, derived sources before the containing query
and each expression subquery before its containing expressions,
because an expression needs the shapes of the subqueries that it names
({name}`Belay.Sqlite.Model.SubqueryShape`). A compound subquery (ADR 0019, D3) has its terms after
it, so their bodies come before its own; the terms of a compound go from right to left, as
SQLite resolves them. An issue of subquery {lit}`i` is at the path
{lit}`[field, i]` and the path within its clauses, where {lit}`field` is the child of the
statement's syntax that holds its subqueries: 8 for {lit}`SELECT`. -/

namespace Belay.Sqlite.Model

/-- The shape of a resolved subquery ({name}`SubqueryShape`): the query around it, its number
of result columns, the affinity and collations of its first result column, and the lowest
cell that it or a subquery that it names reads. -/
def subqueryShape (scope : Scope) (shapes : SubqueryShapes) (subquery : Syntax.Subquery) (query : Resolved.Query)
    (affinity : Option Affinity) : SubqueryShape :=
  let (explicitCollation, columnCollation) := firstCollations scope subquery.columns
  { parent := subquery.parent, columns := query.columns.length, affinity, explicitCollation, columnCollation,
    lowest := query.expressions.foldl (fun lowest expression => minPosition lowest (expression.lowestRead shapes))
      (query.sources.foldl (fun lowest source => match source.source with
        | .subquery index _ => minPosition lowest ((shapes.find index).bind (·.lowest))
        | .table _ | .each .. | .pragma _ => lowest) none) }

/-- The order of body resolution: derived sources in FROM order, then expression subqueries
in written order, each after its own children; compound terms go right to left. The bounded
walk follows the existing indexed parent relation and does not change evaluation order. -/
def subqueryBodyOrder (main : QueryScope) (compound : Option Syntax.Compound)
    (scopes : List QueryScope) (subqueries : List Syntax.Subquery) : Nat → Option Nat → List Nat
  | 0, _ => []
  | fuel + 1, parent =>
    let children := (List.range subqueries.length).filter fun index =>
      (subqueries[index]?.map (·.parent)) == some parent
    if children.isEmpty then [] else
    let sources := ((parent.bind (scopes[·]?)).getD main).sourceIndexes
    let ordered := match compoundOf compound subqueries parent with
      | some terms => terms.terms.reverse
      | none => (sources ++ children).eraseDups
    ordered.flatMap fun child =>
      subqueryBodyOrder main compound scopes subqueries fuel (some child) ++ [child]

/-- Refresh a query scope after its derived sources resolve. Their column types also rebuild
USING/NATURAL equalities. The outer sources retain their existing cell positions and depths. -/
def QueryScope.refresh (catalog : Catalog) (shapes : List SubqueryShape) (query : Syntax.Subquery)
    (around : QueryScope) : Except ValueIssue QueryScope := do
  let scope := around.scope.refreshSources shapes
  if scope = around.scope then pure around else do
    let callback := fun index => match shapes[index]?.bind (·.source) with
      | some source => Except.ok source
      | none => Except.error (SourceIssue.value (.restriction [] .subqueryHere))
    let sources := resolveSources catalog query.source query.joins around.outer callback
    let (pending, inner) ← sources.mapError fun
      | .value issue => issue
      | .noSuchTable name => .prepare (.noSuchSource name)
    pure { around with pending, scope := scope.filter (·.depth > 0) ++ inner }

/-- Resolve each body after its dependencies, using the existing query and compound resolvers.
Returned queries and shapes retain their syntax indexes. A FROM source adds the metadata of
all its output columns to its shape; expression subqueries keep first-column metadata only.
Each body issue is located at its subquery's syntax path. -/
def resolveSubqueryBodies (dqs : Bool) (catalog : Catalog) (field : Nat) (main : QueryScope)
    (compound : Option Syntax.Compound) (scopes : List QueryScope) (subqueries : List Syntax.Subquery) :
    Except ValueIssue (List Resolved.Query × List SubqueryShape) := do
  let missing : SubqueryShape :=
    { parent := some subqueries.length, columns := 0,
      affinity := none, explicitCollation := none, columnCollation := none, lowest := none }
  let emptyQuery : Resolved.Query :=
    { sources := [], filter := none, aggregate := false,
      groupBy := [], columns := [], names := [], orderBy := [], offset := 0, limit := none }
  let found ← (subqueryBodyOrder main compound scopes subqueries (subqueries.length + 1) none).foldlM
    (fun found index => do
      let shapes := (List.range subqueries.length).map fun index =>
        ((List.lookup index found).map Prod.snd).getD missing
      let queries := (List.range subqueries.length).map fun index =>
        ((List.lookup index found).map Prod.fst).getD emptyQuery
      let refreshed := scopes.map fun scope => { scope with scope := scope.scope.refreshSources shapes }
      let body : Except ValueIssue (Resolved.Query × SubqueryShape) := do
        let some subquery := subqueries[index]? | throw (.restriction [] .subqueryHere)
        let some around := scopes[index]? | throw (.restriction [] .subqueryHere)
        let around ← around.refresh catalog shapes subquery
        let current : SubqueryShapes :=
          { current := some index, later := shapes.drop (index + 1), outer := around.outer }
        let (query, shape, columns) ← match subquery.compound with
          | some compound => do
            let terms ← compoundTerms 0 (some index) compound (refreshed.map QueryScope.scope)
              subqueries queries shapes
            let (query, shape) ← resolveCompoundBody dqs around.outer subquery compound terms
            pure (query, shape, compoundSourceColumns (terms.map fun term =>
              resultSourceColumns term.scope term.shapes term.written.columns term.query.names))
          | none => do
            let (query, affinity) ← resolveQueryBody dqs around.scope current around.outerAliases around.pending subquery
            pure (query, subqueryShape around.scope current subquery query affinity,
              resultSourceColumns around.scope current subquery.columns query.names)
        let isSource := match subquery.parent with
          | none => main.sourceIndexes.contains index
          | some parent => (scopes[parent]?).any (·.sourceIndexes.contains index)
        let shape ← if !isSource then pure shape else do
          let expanded ← (sourceExpansion catalog field subqueries subquery.parent index).mapError fun
            | .value issue => issue
            | .noSuchTable name => .prepare (.noSuchSource name)
          let columns := (columns.zip expanded.columns).map fun (column, named) =>
            { column with name := named.name.text }
          pure { shape with source := some (derivedScopeSource index none columns) }
        if let some issue := compoundColumnsIssue (compoundOf compound subqueries subquery.parent)
            index shape.columns 0 shapes then throw issue
        pure (query, shape)
      let resolved ← body.mapError (·.under [field, index])
      pure ((index, resolved) :: found)) []
  let resolved ← (List.range subqueries.length).mapM fun index =>
    match List.lookup index found with
    | some resolved => pure resolved
    | none => throw (.restriction [field, index] .subqueryHere)
  pure (resolved.map Prod.fst, resolved.map Prod.snd)

/-- Resolve the subqueries of a statement around whose own expressions is {lit}`main`: their
scopes ({name}`subqueryScopes`), then their bodies ({name}`resolveSubqueryBodies`), with the
statement's syntax holding them at child {lit}`field`. -/
def resolveSubqueries (dqs : Bool) (catalog : Catalog) (field : Nat) (main : QueryScope)
    (subqueries : List Syntax.Subquery) : Except SourceIssue (List Resolved.Query × List SubqueryShape) := do
  let scopes ← subqueryScopes catalog field main none subqueries
  (resolveSubqueryBodies dqs catalog field main none scopes subqueries).mapError .value

/-- Whether a subquery reads the table at the catalog position directly. -/
def Resolved.Query.readsTable (position : Nat) (query : Resolved.Query) : Bool :=
  query.sources.any (·.source == .table position)

end Belay.Sqlite.Model
