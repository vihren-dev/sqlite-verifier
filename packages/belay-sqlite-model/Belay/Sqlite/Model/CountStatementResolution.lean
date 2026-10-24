import Belay.Sqlite.Model.CountSelectResolution
import Belay.Sqlite.Model.SubquerySelectResolution
import Belay.Sqlite.Model.SelectOneResolution
import Belay.Sqlite.Model.SubqueryExprResolutionLaws
import Belay.Sqlite.Model.NoFromQuerySteps

set_option doc.verso true

/-! The resolution of {lit}`SELECT 1 WHERE c(SELECT count(*) FROM t WHERE p)` (ADR 0017, S4), the query form
of a bound on the number of rows: for a table that the catalog has, the statement resolves to the simple
query without source and with the condition {lit}`c`, and the one subquery, the count query of the first
source of the table with the condition that {lit}`p` resolves to in the scope of the table. -/

namespace Belay.Sqlite.Model

/-- The shape of a scalar subquery {lit}`(SELECT count(*) …)` that no query surrounds: one result column, with
no affinity and no collation, that is no derived table, and that reads the lowest cell position
{lit}`lowest`. -/
def countShape (lowest : Option Nat) : SubqueryShape :=
  { parent := none, columns := 1, affinity := none, explicitCollation := none, columnCollation := none, lowest,
    derived := false }

/-- For every scope, shapes, subquery syntax of the form {lit}`SELECT count(*) …` and resolved count query, the shape
that resolution records for the subquery is the shape of a count query ({name}`countShape`) for some lowest
position. Proof sketch: the subquery has no parent, its resolved query has one column, its result column
{lit}`count(*)` has no affinity and no collation, and the lowest position is a fold that the lemma leaves
open. -/
theorem subqueryShape_count (scope : Scope) (shapes : SubqueryShapes) (source : Option Syntax.TableReference)
    (filter : Option Syntax.Expr) (name : String) (alias : Option Identifier) (text : String) (query : Resolved.Query)
    (columns : query.columns = [.aggregate .countRows]) :
    ∃ lowest, subqueryShape scope shapes (Syntax.Subquery.mk [.expression (.callStar name) alias text] source []
      filter [] [] none none none none false none) query none = countShape lowest := by
  refine ⟨query.expressions.foldl (fun lowest expression => minPosition lowest (expression.lowestRead shapes)) none, ?_⟩
  simp [subqueryShape, firstCollations, Syntax.Expr.explicitCollation, Syntax.Expr.columnCollation, columns, countShape]

/-- For every statement {lit}`SELECT 1 WHERE c` with one subquery {lit}`SELECT count(*) FROM t WHERE p` of a table that
the catalog of the state has at a position, without table-function arguments, where {lit}`p` resolves in the
scope of the table to a condition, {lit}`c` resolves to a condition that has no fallible call for every shape of a
count query ({name}`countShape`), resolution gives the simple query without source and with that condition, the
literal one named {lit}`"1"`, and the count query of the first source of the table with the condition of {lit}`p` as its
one subquery, and leaves the state as it is. Proof sketch: {name}`resolveStatement_select_of_resolveSelect` and
{name}`resolveSelect_noFrom_one_subquery`; the subquery resolves by {name}`resolveQueryBody_count` in the scope of its table
({name}`resolveSources_table`, {name}`resolvePendingSources_table`), its shape is that of a count query
({name}`subqueryShape_count`), and the statement's query resolves by {name}`resolveQueryBody_simple` in the empty scope
with that shape. -/
theorem resolveStatement_selectOne_count (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (subFilter : Option Syntax.Expr) (mainFilter : Syntax.Expr)
    (position : Nat) (table : CatalogTable) (subCondition : Option Resolved.Expr) (mainCondition : Resolved.Expr)
    (name : String) (text : String) (count : normalizeIdentifier name = "count")
    (arguments : reference.arguments = none) (found : state.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves context.profile.dqsDml (tableScope state.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves context.profile.dqsDml [] [] (some mainFilter) (some mainCondition) { later := [countShape lowest] })
    (plain : mainCondition.any Resolved.Expr.isFallibleCall = false) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
        [Syntax.Subquery.mk [.expression (.callStar name) none text] (some reference) [] subFilter [] [] none none none none
          false none] none false none) =
      .ok (.query (Resolved.Query.selectOneWhere mainCondition)
        [Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition text], state) := by
  have simple : ∀ source filter, (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] source [] filter [] [] none none
      none none false none).Simple := fun _ _ => ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have noFeed : (([[(Resolved.Output.scalar (.literal (.integer 1)), "1", (none : Option Affinity))]] :
      List (List (Resolved.Output × String × Option Affinity))).flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false := by
    simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]
  have subBody := resolveQueryBody_count context.profile.dqsDml (tableScope state.catalog reference position table) (some 0)
    [] [] _ (some reference) subFilter name none text count subCondition _ (by simpa [resultAliases] using subResolves)
    (resolvePendingSources_table _ _ position)
  obtain ⟨lowest, shapeIs⟩ := subqueryShape_count (tableScope state.catalog reference position table) { current := some 0 }
    (some reference) subFilter name none text
    (Resolved.Query.countOf [Resolved.QuerySource.first position] subCondition text) rfl
  have mainBody := resolveQueryBody_simple context.profile.dqsDml [] none [countShape lowest] [] []
    (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none none none false none)
    (simple _ _) _ (some mainCondition) _ (resolveColumns_one _ _ _)
    (by simpa [resultAliases] using mainResolves lowest) (resolvePendingSources_nil _ _) noFeed
  refine resolveStatement_select_of_resolveSelect context state
    (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none none none false none)
    _ rfl _ ?_
  refine resolveSelect_noFrom_one_subquery context state.catalog _ _ rfl rfl rfl (by simp [starIssue]) rfl rfl _ _
    (resolveSources_table state.catalog reference position table arguments found) (by simp [starIssue]) _ _
    (by simpa [resultAliases] using subBody) _ shapeIs.symm _ _ (by simpa using mainBody) ?_
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.simple, Resolved.Output.scalars,
    Resolved.Output.operands, plain, Resolved.Expr.any, Resolved.Expr.isFallibleCall]

end Belay.Sqlite.Model
