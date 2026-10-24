import Belay.Sqlite.Model.SelectNoFromResolution
import Belay.Sqlite.Model.SubquerySelectResolution
import Belay.Sqlite.Model.SelectOneResolution
import Belay.Sqlite.Model.NoFromQuerySteps

set_option doc.verso true

/-! The resolution of {lit}`SELECT 1 WHERE c(SELECT e FROM t WHERE p)` (ADR 0017, S4), the statement whose
condition names a subquery with one expression column, such as {lit}`x IN (SELECT id FROM t WHERE p)` or a scalar
subquery: for a table that the catalog has, the statement resolves to the simple query without source and with the
condition {lit}`c`, and the one subquery, the simple query of the first source of the table with the condition that
{lit}`p` resolves to and the one column that {lit}`e` resolves to in the scope of the table. -/

namespace Belay.Sqlite.Model

/-- The shape of a subquery with one result column that no query surrounds and that is no compound: its
affinity, the explicit collation and the column collation of its result column, and the lowest cell position
{lit}`lowest` that it reads. -/
def scalarShape (affinity : Option Affinity) (explicitCollation columnCollation : Option Collation)
    (lowest : Option Nat) : SubqueryShape :=
  { parent := none, columns := 1, affinity, explicitCollation, columnCollation, lowest, derived := false }

/-- For every catalog, table reference, position, table, name and quote kind, if the table has a column of that name at
a position, the column collation of the name in the scope of the table ({name}`Syntax.Expr.columnCollation`) is the collation of the
column at that position. The formula requires nothing of a name that the table does not have. Proof sketch:
the name resolves to the column alone ({name}`resolveName_one_source`), and the scope of the table has the columns
of the table ({name}`Scope.columns_single`). -/
theorem Syntax.Expr.columnCollation_identifier_table {catalog : Catalog} {reference : Syntax.TableReference}
    {position : Nat} {table : CatalogTable} {name : Identifier} {quote : Syntax.QuoteKind} {index : Nat}
    (found : columnPosition table.columns name = some index) :
    (Syntax.Expr.identifier name quote).columnCollation (tableScope catalog reference position table) =
      table.columns[index]?.map (·.collation) := by
  simp [Syntax.Expr.columnCollation, tableScope, resolveName_one_source found, Scope.columns_single]

/-- For every scope, shapes, subquery syntax with one expression column and no parent, and resolved query with one column,
the shape that resolution records for the subquery is the shape of a one-column subquery ({name}`scalarShape`) with the
affinity given, the collations of the expression ({name}`firstCollations`) and some lowest position. Proof sketch:
the subquery has no parent and one resolved column, and the lowest position is a fold that the lemma leaves open. -/
theorem subqueryShape_scalar (scope : Scope) (shapes : SubqueryShapes) (value : Syntax.Expr) (alias : Option Identifier)
    (text : String) (source : Option Syntax.TableReference) (filter : Option Syntax.Expr) (query : Resolved.Query)
    (affinity : Option Affinity) (one : query.columns.length = 1) :
    ∃ lowest, subqueryShape scope shapes (Syntax.Subquery.mk [.expression value alias text] source [] filter [] [] none none
      none none false none) query affinity =
        scalarShape affinity value.explicitCollation (value.columnCollation scope) lowest :=
  ⟨query.expressions.foldl (fun lowest expression => minPosition lowest (expression.lowestRead shapes)) none, by
    simp [subqueryShape, firstCollations, one, scalarShape]⟩

/-- For every statement {lit}`SELECT 1 WHERE c` with one subquery {lit}`SELECT e FROM t WHERE p` of a table that the catalog of the
state has at a position, without table-function arguments, where {lit}`e` is no function call, has no aggregate call and resolves in
the scope of the table to an expression without a fallible call, {lit}`p` resolves in the scope of the table, and {lit}`c`
resolves to a condition without a fallible call for every lowest position of a one-column subquery with the collations of
{lit}`e` ({name}`scalarShape`), resolution gives the simple query without source and with that condition and the literal one,
and the simple query of the first source of the table with the condition of {lit}`p` and the column of {lit}`e` as its one subquery,
and leaves the state as it is. Proof sketch: {name}`resolveStatement_select_of_resolveSelect` and
{name}`resolveSelect_noFrom_one_subquery`; the subquery resolves by {name}`resolveQueryBody_simple` in the scope of its table
with the column of {name}`resolveColumns_scalar`, its shape is a one-column shape ({name}`subqueryShape_scalar`), and the
statement's query resolves by {name}`resolveQueryBody_simple` in the empty scope with that shape. -/
theorem resolveStatement_selectOne_scalar (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (value : Syntax.Expr) (text : String) (subFilter : Option Syntax.Expr)
    (mainFilter : Syntax.Expr) (position : Nat) (table : CatalogTable) (subCondition : Option Resolved.Expr)
    (mainCondition : Resolved.Expr) (expression : Resolved.Expr) (affinity : Option Affinity)
    (notCall : value.isCall = false) (noAggregate : value.aggregateCalls.isEmpty = true)
    (arguments : reference.arguments = none) (found : state.catalog.findTable reference.table = some (position, table))
    (operand : resolveOperand context.profile.dqsDml (tableScope state.catalog reference position table)
      { current := some 0 } false value = .ok (expression, affinity))
    (valuePlain : expression.any Resolved.Expr.isFallibleCall = false)
    (subResolves : FilterResolves context.profile.dqsDml (tableScope state.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ lowest : Option Nat,
      FilterResolves context.profile.dqsDml [] [] (some mainFilter) (some mainCondition)
        { later := [scalarShape affinity value.explicitCollation (value.columnCollation
          (tableScope state.catalog reference position table)) lowest] })
    (plain : mainCondition.any Resolved.Expr.isFallibleCall = false) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
        [Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none none none
          false none] none false none) =
      .ok (.query (Resolved.Query.selectOneWhere mainCondition)
        [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar expression]
          [(definedName (tableScope state.catalog reference position table) value).getD text]], state) := by
  have simple : ∀ source filter, (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] source [] filter [] [] none none
      none none false none).Simple := fun _ _ => ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have noFeed : (([[(Resolved.Output.scalar (.literal (.integer 1)), "1", (none : Option Affinity))]] :
      List (List (Resolved.Output × String × Option Affinity))).flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false := by
    simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]
  have subSimple : (Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none none none
      false none).Simple := ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, by simpa using noAggregate⟩
  have subBody := resolveQueryBody_simple context.profile.dqsDml (tableScope state.catalog reference position table)
    (some 0) [] [] _ (Syntax.Subquery.mk [.expression value none text] (some reference) [] subFilter [] [] none none
      none none false none) subSimple _ subCondition _
    (resolveColumns_scalar _ _ _ value text expression affinity notCall operand)
    (by simpa [resultAliases] using subResolves) (resolvePendingSources_table _ _ position)
    (by simpa [Resolved.Expr.isFallibleCall] using Resolved.Expr.any_and_eq_false _ _ expression valuePlain)
  obtain ⟨lowest, shapeIs⟩ := subqueryShape_scalar (tableScope state.catalog reference position table)
    { current := some 0 } value none text (some reference) subFilter
    (Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar expression]
      [(definedName (tableScope state.catalog reference position table) value).getD text]) affinity rfl
  have mainBody := resolveQueryBody_simple context.profile.dqsDml [] none
    [scalarShape affinity value.explicitCollation (value.columnCollation (tableScope state.catalog reference position table))
      lowest] [] []
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
