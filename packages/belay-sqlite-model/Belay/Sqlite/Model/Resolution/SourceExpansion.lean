import Belay.Sqlite.Model.Resolution.DerivedColumns

set_option doc.verso true

/-! Expand query-source names and stars before resolving expression names (ADR 0019, D5).
This uses the same source resolver as a table query. The later body pass replaces these
name-only columns with their resolved affinities and collations. -/

namespace Belay.Sqlite.Model

/-- Output names before expression resolution: aliases and written expression names, or the
expanded column names of stars. These names determine the columns of a derived source. -/
def sourceOutputNames (scope : Scope) (results : List Syntax.ResultColumn) : List String :=
  results.flatMap fun
    | .star => scope.visible.map (·.2.name.text)
    | .sourceStar name => ((scope.starColumns? name).getD []).map (·.2.name.text)
    | .expression value alias text => [(alias.map (·.text)).getD (value.writtenName.getD text)]

/-- Name-only columns for a derived source. Duplicate names follow {name}`derivedNames`;
a random suffix is the restriction {name}`RestrictionKind.sourceColumnName`. The path locates
the result columns of the source query. Affinity and collation are filled after resolution. -/
def expandedSource (index : Nat) (path : List Nat) (scope : Scope) (results : List Syntax.ResultColumn)
    (names : List String) : Except SourceIssue ScopeSource := do
  let some names := derivedNames scope results names |
    throw (.value (.restriction (path ++ [0]) .sourceColumnName))
  pure (derivedScopeSource index none (names.map fun name =>
    { name, affinity := none, collation := .binary, types := (true, true) }))

/-- Expand one indexed query's sources and stars, without resolving expression names.
The fuel bounds nesting by the statement's number of subqueries. A compound expands its
terms right to left, but its column names come from the left-most term. A source may name
only a later query with this query as parent, as the frontend records it. -/
def expandQuerySources (catalog : Catalog) (field : Nat) (subqueries : List Syntax.Subquery) :
    Nat → Nat → Except SourceIssue (Scope × List Syntax.ResultColumn × List String)
  | 0, index => .error (.value (.restriction [field, index] .subqueryHere))
  | fuel + 1, index => do
    let refused := SourceIssue.value (.restriction [field, index] .subqueryHere)
    let some query := subqueries[index]? | throw refused
    match query.compound with
    | some compound =>
      let terms ← compound.terms.reverse.mapM fun child => do
        if child ≤ index || (subqueries[child]?.map (·.parent)) != some (some index) then throw refused
        expandQuerySources catalog field subqueries fuel child
      let some first := terms.getLast? | throw refused
      pure first
    | none =>
      let (_, scope) ← resolveSources catalog query.source query.joins 0 (fun child => do
        if child ≤ index || (subqueries[child]?.map (·.parent)) != some (some index) then throw refused
        let (scope, results, names) ← expandQuerySources catalog field subqueries fuel child
        expandedSource child [field, child] scope results names) [field, index]
      if let some issue := starIssue scope query.columns then throw (.value (issue.under [field, index]))
      pure (scope, query.columns, sourceOutputNames scope query.columns)

/-- The source callback for the query at {lit}`parent`, or the statement's query when absent.
It checks the indexed-parent relation before expanding names. -/
def sourceExpansion (catalog : Catalog) (field : Nat) (subqueries : List Syntax.Subquery)
    (parent : Option Nat) (index : Nat) : Except SourceIssue ScopeSource := do
  if subqueries.isEmpty then throw (.value (.restriction [] .subqueryHere))
  if (subqueries[index]?.map (·.parent)) != some parent || parent.any (index ≤ ·) then
    throw (.value (.restriction [field, index] .subqueryHere))
  let (scope, results, names) ← expandQuerySources catalog field subqueries (subqueries.length + 1) index
  expandedSource index [field, index] scope results names

/-- Refresh derived columns from already resolved source bodies while retaining placement,
qualification and merged-column rules. Catalog and function sources remain unchanged. -/
def Scope.refreshSources (scope : Scope) (shapes : List SubqueryShape) : Scope :=
  if shapes.all (·.source.isNone) then scope else scope.map fun source =>
    match (source.queryIndex.bind (fun index => shapes[index]?)).bind (·.source) with
    | none => source
    | some resolved => { source with columns := resolved.columns, affinities := resolved.affinities }

end Belay.Sqlite.Model
