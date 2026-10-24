import Belay.Sqlite.Model.Resolution.StatementCatalog
import Belay.Sqlite.Model.Resolution.SourceList
import Belay.Sqlite.Model.Resolution.QueryTerms
import Belay.Sqlite.Model.Resolution.QueryAggregates

set_option doc.verso true

/-! Resolution of the clauses of a query (ADR 0012, slice 1, and amendment 2 for joins),
the statement's query or a subquery (ADR 0018, D1). The steps follow SQLite's resolver: the
tables of {lit}`FROM` ({lit}`Sources`), the result columns, {lit}`WHERE`, the {lit}`ON`
conditions, {lit}`GROUP BY`, {lit}`ORDER BY`, then {lit}`LIMIT` and {lit}`OFFSET`. The paths
of a restriction use the child positions of {lit}`Syntax.Statement.select` and of
{lit}`Syntax.Subquery`: 0 the columns, 1 the first table, 2 the joins, 3 the filter, 4 the
grouping terms, 5 the ordering terms, 6 the limit and 7 the offset. A
grouping term is a column name, also under one {lit}`COLLATE` ({name}`Belay.Sqlite.Model.Syntax.Expr.collatedColumn`),
or a result column; each grouping and ordering term compares under its collation
(ADR 0014, slice 3). -/

namespace Belay.Sqlite.Model

/-- One resolved result column with its names and the affinity of each: {lit}`*` gives every
column of every source of the query's own sources that is not merged ({name}`Scope.visible`)
under its defined name, a merged pair as its unqualified name ({name}`Scope.starOperand`),
{lit}`x.*` every column of source {lit}`x` ({name}`sourceStarColumns`); an aggregate is a whole
result column, without affinity; any other expression is a scalar with the affinity of its
operand. A name is the {lit}`AS` alias, else the defined name of a referenced column
({name}`definedName`), else the source text as written. -/
def resolveResultColumn (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (column : Nat) :
    Syntax.ResultColumn → Except ValueIssue (List (Resolved.Output × String × Option Affinity))
  | .star => if scope.inner.isEmpty then .error (.prepare .noTablesSpecified) else
      scope.visible.mapM fun (position, defined) =>
        (fun (operand : Operand) => (.scalar operand.1, defined.name.text, operand.2)) <$> scope.starOperand position defined
  | .sourceStar source => (sourceStarColumns scope source).map fun columns =>
      columns.map fun ((expression, affinity), name) => (.scalar expression, name, affinity)
  | .expression value alias text => do
    let named := fun (output : Resolved.Output) (defined : Option String) (affinity : Option Affinity) =>
      [(output, (alias.map (·.text)).getD (defined.getD text), affinity)]
    let outerAggregate := fun (operand : Resolved.Expr) =>
      if operand.readsUnder shapes shapes.outer then throw ((ValueIssue.restriction [] .outerAggregate).under [0, column, 0])
      else pure ()
    match value with
    | .callStar name =>
      if normalizeIdentifier name == "count" then .ok (named (.aggregate .countRows) none none)
      else throw ((starCallIssue name).under [0, column, 0])
    | .call name [] =>
      if normalizeIdentifier name == "count" then .ok (named (.aggregate .countRows) none none)
      else do
        let (resolved, affinity) ← (resolveOperand dqs scope shapes false value).mapError (·.under [0, column, 0])
        .ok (named (.scalar resolved) none affinity)
    | .call name [operand] => match aggregateNamed name with
      | some aggregate =>
        let (resolved, _) ← (resolveOperand dqs scope shapes true operand).mapError (·.under [0, column, 0, 1, 0])
        outerAggregate resolved
        if (aggregate resolved).writesJson && resolved.subtypeUndescribed then
          throw ((ValueIssue.restriction [] .jsonSubtype).under [0, column, 0, 1, 0])
        .ok (named (.aggregate ((aggregate resolved).withCollation (operand.collationIn scope))) none none)
      | none => do
        let (resolved, affinity) ← (resolveOperand dqs scope shapes false value).mapError (·.under [0, column, 0])
        .ok (named (.scalar resolved) none affinity)
    | .call name [first, second] => match pairAggregateNamed name with
      | some aggregate =>
        let (label, _) ← (resolveOperand dqs scope shapes true first).mapError (·.under [0, column, 0, 1, 0])
        let (operand, _) ← (resolveOperand dqs scope shapes true second).mapError (·.under [0, column, 0, 1, 1])
        outerAggregate (.coalesce label operand)
        if operand.subtypeUndescribed then throw ((ValueIssue.restriction [] .jsonSubtype).under [0, column, 0, 1, 1])
        .ok (named (.aggregate (aggregate label operand)) none none)
      | none => do
        let (resolved, affinity) ← (resolveOperand dqs scope shapes false value).mapError (·.under [0, column, 0])
        .ok (named (.scalar resolved) none affinity)
    | .call _ (_ :: _ :: _ :: _) | .null | .numeric _ | .string _ | .blob _ | .parameter _ | .currentTime _
    | .identifier .. | .qualified .. | .negate _ | .positive _ | .compare .. | .and .. | .or .. | .not _
    | .isNull .. | .arithmetic .. | .cast .. | .collate .. | .exists _ | .inQuery .. | .subquery _ | .inList ..
    | .between .. | .caseOf .. | .concatenate .. | .raise .. =>
      let (resolved, affinity) ← (resolveOperand dqs scope shapes false value).mapError (·.under [0, column, 0])
      .ok (named (.scalar resolved) (definedName scope value) affinity)

/-- The aliases of the result columns as written, one for each output: none for each column
of {lit}`*` and {lit}`x.*`. -/
def resultAliases (scope : Scope) (results : List Syntax.ResultColumn) : List (Option Identifier) :=
  results.flatMap fun
    | .star => scope.visible.map fun _ => none
    | .sourceStar name => ((scope.starColumns? name).map (·.map fun _ => none)).getD []
    | .expression _ alias _ => [alias]

/-- The explicit collation and the column collation of the first result column, as
{name}`inCollation` needs them for a subquery: those of its expression, or the collation of
the first expanded operand of {lit}`*` or {lit}`x.*`. -/
def firstCollations (scope : Scope) : List Syntax.ResultColumn → Option Collation × Option Collation
  | .expression value _ _ :: _ => (value.explicitCollation, value.columnCollation scope)
  | .star :: _ => (none, (scope.visible.head?.bind fun (position, column) => scope.starCollation position column))
  | .sourceStar name :: _ => (none, ((scope.starColumns? name).bind (·.head?)).bind fun (position, column) => scope.starCollation position column)
  | [] => (none, none)

/-- Resolve the clauses of a query over its scope ({lit}`resolveSources`, enclosed by the
scopes of the queries around it), with the shapes of the subqueries that its expressions name
and the aliases of the queries around it, which a name in {lit}`WHERE` can name: the resolved
query and the affinity of its first result column. See the module documentation for the steps.
A scalar subquery is no grouping term, so it is a bare column of an aggregate query. The
query is an aggregate query when it has {lit}`GROUP BY` or an aggregate in a result column, and
then the aggregate calls of its result columns, {lit}`HAVING` and {lit}`ORDER BY` are its
aggregates (ADR 0018, D3); {lit}`HAVING` in another query is SQLite's {lit}`HAVING clause on a
non-aggregate query`, and an aggregate in its {lit}`ORDER BY` SQLite's misuse. {lit}`HAVING` and
{lit}`ORDER BY` expressions
must read only grouping terms and aggregates ({name}`Resolved.Expr.grouped`). A fallible call
over an aggregate is {name}`RestrictionKind.aggregateInExpression`, because the model's fault scan
does not read aggregate values; an {lit}`ORDER BY` expression of {lit}`SELECT DISTINCT` that is no
result column is {name}`RestrictionKind.distinctOrderBy`. -/
def resolveQueryBody (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (outerAliases : List Identifier)
    (pending : List PendingSource) (query : Syntax.Subquery) : Except ValueIssue (Resolved.Query × Option Affinity) := do
  let aggregate := !query.groupBy.isEmpty || query.columns.any fun
    | .expression value _ _ => !value.aggregateCalls.isEmpty
    | .star | .sourceStar _ => false
  let calls := (query.columns.flatMap (fun
      | .expression value _ _ => if aggregateCall value then [] else value.aggregateCalls
      | .star | .sourceStar _ => []) ++
    (if aggregate then query.having.toList.flatMap Syntax.Expr.aggregateCalls ++
      query.orderBy.flatMap (·.expression.aggregateCalls) else [])) |> Syntax.Expr.distinctList
  let shapes := { shapes with aggregates := calls }
  let aggregates ← resolveAll (fun _ call => resolveAggregateCall dqs scope shapes call) calls
  let outputs := (← resolveAll (resolveResultColumn dqs scope shapes) query.columns).flatten
  -- SQLite resolves the result columns before it checks HAVING.
  if query.having.isSome && !aggregate then throw (.prepare .havingNonAggregate)
  let aliases := resultAliases scope query.columns
  let visibleAliases := aliases.filterMap id ++ outerAliases
  let condition ← match query.filter with
    | none => pure none
    | some term =>
      if namesAlias scope visibleAliases term then throw (aliasInExpression.under [3])
      else some <$> condition [3] (resolveOperand dqs scope shapes true term)
  let sources ← resolvePendingSources dqs scope pending
  let collations := resultCollations scope query.columns
  let terms ← resolveAll (resolveGroupTerm dqs scope shapes aliases outputs collations) query.groupBy
  if aggregate && !outputs.all (groupedOutput (terms.map Prod.fst) ·.1) then
    throw (.restriction [0] .bareColumn)
  let having ← match query.having with
    | none => pure none
    | some term =>
      if namesAlias scope visibleAliases term then throw (aliasInExpression.under [9])
      else
        let resolved ← Belay.Sqlite.Model.condition [9] (resolveOperand dqs scope shapes false term)
        if resolved.grouped (terms.map Prod.fst) then pure (some resolved) else throw (.restriction [9] .bareColumn)
  let order ← resolveAll (fun item (term : Syntax.OrderTerm) => match namedResult aliases term.expression with
    | some (.ok column) =>
      .ok { key := .output column, descending := term.descending, collation := collations.getD column .binary }
    | some (.error ()) => .error (.prepare (.orderByOutOfRange (item + 1) outputs.length))
    | none =>
      if namesAlias scope visibleAliases term.expression then .error (aliasInExpression.under [5, item, 0])
      else (resolveOperand dqs scope shapes (!aggregate) term.expression).mapError (·.under [5, item, 0]) >>= fun (e, _) =>
        if aggregate && !e.grouped (terms.map Prod.fst) then .error (.restriction [5, item] .aggregateOrderBy)
        else if query.distinct && !outputs.any (·.1 == .scalar e) then .error (.restriction [5, item] .distinctOrderBy)
        else .ok ({ key := .expression e, descending := term.descending, collation := term.expression.collationIn scope }
          : Resolved.SortTerm)) query.orderBy
  let feedsCall := fun (expression : Resolved.Expr) =>
    expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)
  let scalars := outputs.filterMap fun (output, _) => match output with
    | .scalar expression => some expression
    | .aggregate _ => none
  let sorted := order.filterMap fun term => match term.key with
    | .expression expression => some expression
    | .output _ => none
  if (scalars ++ having.toList ++ sorted).any feedsCall then
    throw (.restriction [] .aggregateInExpression)
  let (limitValue, limitParameter) ← windowValue [6] query.limit
  let (offsetValue, offsetParameter) ← windowValue [7] query.offset
  if offsetValue.any (· < 0) then throw (.restriction [7] .negativeOffset)
  if windowSkipsFailure query.groupBy query.limit query.offset (outputs.map (·.1) ++ aggregates.map .aggregate) then
    throw (.restriction [6] .windowedGroupSum)
  return ({ sources, filter := condition, aggregate, groupBy := terms,
            columns := outputs.map (·.1), names := outputs.map (·.2.1), orderBy := order,
            offset := (offsetValue.getD 0).toNat,
            limit := limitValue.bind fun value => if value < 0 then none else some value.toNat,
            limitParameter, offsetParameter,
            outer := shapes.outer, aggregates, having,
            distinct := if query.distinct then some collations else none }, (outputs.head?.bind (·.2.2)))

end Belay.Sqlite.Model
