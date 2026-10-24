import Belay.Sqlite.Model.AggregateQueryLaws
import Belay.Sqlite.Model.CountSelectResolution
import Belay.Sqlite.Model.SubquerySelectResolution

set_option doc.verso true

/-! The resolution of the whole-table aggregate query {lit}`SELECT agg(x) FROM t WHERE p` (ADR 0017, S4), such as
{lit}`SELECT sum(c) FROM t`: the body of the query, with its one result column an aggregate of one operand and its
{lit}`WHERE` condition, resolves to the whole-table aggregate query
({name}`Belay.Sqlite.Model.Resolved.Query.aggregateOf`) of its resolved sources, condition and aggregate. The lemmas
take the resolved sources, operand and condition as hypotheses, because the catalog is free. -/

namespace Belay.Sqlite.Model

/-- For every subquery shapes that have zero outer cells ({lit}`shapes.outer = 0`): the result column {lit}`agg(x)`,
where the name {lit}`agg` names an aggregate of one operand ({name}`aggregateNamed`) that does not write JSON and the
operand {lit}`x` resolves ({name}`resolveOperand`) to an expression, resolves to that aggregate of the resolved operand,
with the collation of the operand (only {lit}`min` and {lit}`max` use it), named by its alias or else its text, with no
affinity. Proof sketch: unfold the resolver; the name gives the aggregate, and the operand resolves by the hypothesis. -/
theorem resolveColumns_aggregate (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (name : String)
    (operand : Syntax.Expr) (alias : Option Identifier) (text : String)
    (build : Resolved.Expr → Resolved.Aggregate) (named : aggregateNamed name = some build) (resolved : Resolved.Expr)
    (affinity : Option Affinity) (operandOk : resolveOperand dqs scope shapes true operand = .ok (resolved, affinity))
    (outerZero : shapes.outer = 0) (noJson : (build resolved).writesJson = false) :
    resolveAll (resolveResultColumn dqs scope shapes) [.expression (.call name [operand]) alias text] =
      .ok [[(.aggregate ((build resolved).withCollation (operand.collationIn scope)), (alias.map (·.text)).getD text,
        none)]] := by
  have notJson : ¬ (build resolved).writesJson = true := by simp [noJson]
  simp [resolveAll, resolveAllFrom, resolveResultColumn, named, operandOk, outerZero, notJson, Resolved.Expr.readsUnder,
    Except.mapError, Bind.bind, Except.bind, Pure.pure, Except.pure]

/-- For every query {lit}`SELECT agg(x) FROM … WHERE p` without join, grouping, ordering, window, {lit}`HAVING`,
{lit}`DISTINCT` and compound, whose aggregate {lit}`agg` is one of one operand that does not write JSON
({name}`aggregateNamed`), whose operand, pending sources and {lit}`WHERE` condition resolve, the body resolves to the
whole-table aggregate query of its sources and condition ({name}`Resolved.Query.aggregateOf`), named by the alias of
its result column or else its text, with no affinity. Proof sketch: unfold the resolver; the query is an aggregate
query, the call is the result column itself, so it lists no aggregate, and every clause that the query lacks
resolves to its empty form; then follow the steps with the hypotheses. -/
theorem resolveQueryBody_aggregate (dqs : Bool) (scope : Scope) (current : Option Nat) (later : List SubqueryShape)
    (outerAliases : List Identifier) (pending : List PendingSource) (source : Option Syntax.TableReference)
    (filter : Option Syntax.Expr) (name : String) (operand : Syntax.Expr) (alias : Option Identifier) (text : String)
    (build : Resolved.Expr → Resolved.Aggregate) (named : aggregateNamed name = some build) (resolved : Resolved.Expr)
    (affinity : Option Affinity)
    (operandOk : resolveOperand dqs scope { current, later } true operand = .ok (resolved, affinity))
    (noJson : (build resolved).writesJson = false) (condition : Option Resolved.Expr)
    (sources : List Resolved.QuerySource)
    (resolves : FilterResolves dqs scope
      ((resultAliases scope [.expression (.call name [operand]) alias text]).filterMap id ++ outerAliases)
      filter condition { current, later })
    (pendingOk : resolvePendingSources dqs scope pending = .ok sources) :
    resolveQueryBody dqs scope { current, later } outerAliases pending
        (Syntax.Subquery.mk [.expression (.call name [operand]) alias text] source [] filter [] [] none none none none
          false none) =
      .ok (Resolved.Query.aggregateOf sources condition
        ((build resolved).withCollation (operand.collationIn scope)) ((alias.map (·.text)).getD text), none) := by
  have called : aggregateCall (.call name [operand]) = true := by simp [aggregateCall, named]
  have columns := resolveColumns_aggregate dqs scope { current, later } name operand alias text build named resolved
    affinity operandOk rfl noJson
  have aggregates : (Syntax.Expr.call name [operand]).aggregateCalls = [.call name [operand]] := by
    simp [Syntax.Expr.aggregateCalls, called]
  unfold resolveQueryBody
  dsimp only
  have nothing : ∀ {α β : Type} (f : Nat → α → Except ValueIssue β), resolveAll f [] = .ok [] := fun f => by
    simp [resolveAll, resolveAllFrom]
  simp only [List.any_cons, List.any_nil, Bool.or_false, aggregates, List.isEmpty_cons, Bool.not_false, Bool.not_true, called,
    List.isEmpty_nil, Bool.or_true, ite_true, Bool.false_and, Bool.true_and, List.flatMap_cons, List.flatMap_nil,
    List.append_nil, Option.toList_none, Syntax.Expr.distinctList, List.foldl_nil, Bool.not_eq_true',
    columns, nothing, Bind.bind, Except.bind, Pure.pure, Except.pure]
  rcases resolves with ⟨found, rfl⟩ | ⟨term, expression, affinity, found, rfl, names, ok⟩
  · simp [found, pendingOk, windowValue, windowSkipsFailure, groupedOutput, Resolved.Query.aggregateOf,
      Resolved.Output.canFail]
  · simp [found, pendingOk, names, ok, windowValue, windowSkipsFailure, groupedOutput, Resolved.Query.aggregateOf,
      Model.condition, Functor.map, Except.map, Resolved.Output.canFail]

/-- For every statement {lit}`SELECT agg(x) FROM t WHERE p` (or without {lit}`WHERE`) of a table that the catalog of the
state has at a position, without table-function arguments, whose aggregate {lit}`agg` is one of one operand that does not write
JSON ({name}`aggregateNamed`), whose operand resolves in the scope of the table and whose condition resolves
({name}`FilterResolves`), resolution gives the whole-table aggregate query of the first source of the table
({name}`Resolved.Query.aggregateOf`), with no subquery, and leaves the state as it is. Proof sketch:
{name}`resolveStatement_select_of_resolveSelect` and {name}`resolveSelect_no_subqueries`; the body resolves by
{name}`resolveQueryBody_aggregate` in the scope of the table ({name}`resolveSources_table`,
{name}`resolvePendingSources_table`). -/
theorem resolveStatement_select_aggregate (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (filter : Option Syntax.Expr) (name : String) (operand : Syntax.Expr)
    (alias : Option Identifier) (text : String) (build : Resolved.Expr → Resolved.Aggregate)
    (named : aggregateNamed name = some build) (position : Nat) (table : CatalogTable) (resolved : Resolved.Expr)
    (affinity : Option Affinity) (condition : Option Resolved.Expr) (arguments : reference.arguments = none)
    (found : state.catalog.findTable reference.table = some (position, table))
    (operandOk : resolveOperand context.profile.dqsDml (tableScope state.catalog reference position table)
      { current := none, later := [] } true operand = .ok (resolved, affinity))
    (noJson : (build resolved).writesJson = false)
    (resolves : FilterResolves context.profile.dqsDml (tableScope state.catalog reference position table)
      ((resultAliases (tableScope state.catalog reference position table)
        [.expression (.call name [operand]) alias text]).filterMap id) filter condition { current := none, later := [] }) :
    resolveStatement context state (.select [.expression (.call name [operand]) alias text] (some reference) [] filter [] []
        none none [] none false none) =
      .ok (.query (Resolved.Query.aggregateOf [Resolved.QuerySource.first position] condition
        ((build resolved).withCollation (operand.collationIn (tableScope state.catalog reference position table)))
        ((alias.map (·.text)).getD text)) [], state) := by
  refine resolveStatement_select_of_resolveSelect context state
    (Syntax.Subquery.mk [.expression (.call name [operand]) alias text] (some reference) [] filter [] [] none none none
      none false none) [] rfl _ ?_
  refine resolveSelect_no_subqueries context state.catalog _ _ none _ _ rfl rfl
    (resolveSources_table state.catalog reference position table arguments found) (by simp [starIssue]) ?_
  have body := resolveQueryBody_aggregate context.profile.dqsDml (tableScope state.catalog reference position table)
    none [] [] _ (some reference) filter name operand alias text build named resolved affinity operandOk noJson condition
    _ (by simpa using resolves) (resolvePendingSources_table _ _ position)
  exact body

end Belay.Sqlite.Model
