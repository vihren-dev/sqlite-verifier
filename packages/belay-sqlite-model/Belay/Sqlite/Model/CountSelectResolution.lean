import Belay.Sqlite.Model.CountQueryLaws
import Belay.Sqlite.Model.SimpleSourceResolution

set_option doc.verso true

/-! The resolution of the count query {lit}`SELECT count(*) FROM t WHERE p` (ADR 0017, S4): the body of the
query, with its one result column {lit}`count(*)` and its {lit}`WHERE` condition, resolves to the count query
({name}`Belay.Sqlite.Model.Resolved.Query.countOf`) of its resolved sources and condition. The lemma
takes the resolved sources and condition as hypotheses, because the catalog is free. -/

namespace Belay.Sqlite.Model

/-- The result column {lit}`count(*)` resolves, in any scope and with any shapes of subqueries, to the aggregate
that counts rows, named by its alias or else by its text, with no affinity. Proof sketch: unfold the resolver; the
name of the call is {lit}`count`. -/
theorem resolveColumns_countStar (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (name : String)
    (alias : Option Identifier) (text : String) (count : normalizeIdentifier name = "count") :
    resolveAll (resolveResultColumn dqs scope shapes) [.expression (.callStar name) alias text] =
      .ok [[(.aggregate .countRows, (alias.map (·.text)).getD text, none)]] := by
  simp [resolveAll, resolveAllFrom, resolveResultColumn, count, Bind.bind, Except.bind, Pure.pure, Except.pure]

/-- For every query {lit}`SELECT count(*) FROM … WHERE p` without join, grouping, ordering, window,
{lit}`HAVING`, {lit}`DISTINCT` and compound, whose pending sources and {lit}`WHERE` condition resolve, the body resolves to the
count query of its sources and condition ({name}`Resolved.Query.countOf`), named by the alias of its result column or else its
text, with no affinity. Proof sketch: unfold the resolver; the query is an aggregate query, the call is the
result column itself, so it lists no aggregate, and every clause that the query lacks resolves to its empty form; then
follow the steps with the hypotheses. -/
theorem resolveQueryBody_count (dqs : Bool) (scope : Scope) (current : Option Nat) (later : List SubqueryShape)
    (outerAliases : List Identifier) (pending : List PendingSource) (source : Option Syntax.TableReference)
    (filter : Option Syntax.Expr) (name : String) (alias : Option Identifier) (text : String)
    (count : normalizeIdentifier name = "count") (condition : Option Resolved.Expr) (sources : List Resolved.QuerySource)
    (resolves : FilterResolves dqs scope ((resultAliases scope [.expression (.callStar name) alias text]).filterMap id ++ outerAliases)
      filter condition { current, later })
    (pendingOk : resolvePendingSources dqs scope pending = .ok sources) :
    resolveQueryBody dqs scope { current, later } outerAliases pending
        (Syntax.Subquery.mk [.expression (.callStar name) alias text] source [] filter [] [] none none none none false none) =
      .ok (Resolved.Query.countOf sources condition ((alias.map (·.text)).getD text), none) := by
  have called : aggregateCall (.callStar name) = true := by simp [aggregateCall, count]
  have columns := resolveColumns_countStar dqs scope { current, later } name alias text count
  have aggregates : (Syntax.Expr.callStar name).aggregateCalls = [.callStar name] := by
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
  · simp [found, pendingOk, windowValue, windowSkipsFailure, groupedOutput, Resolved.Query.countOf, Resolved.Output.canFail]
  · simp [found, pendingOk, names, ok, windowValue, windowSkipsFailure, groupedOutput, Resolved.Query.countOf,
      Model.condition, Functor.map, Except.map, Resolved.Output.canFail]

end Belay.Sqlite.Model
