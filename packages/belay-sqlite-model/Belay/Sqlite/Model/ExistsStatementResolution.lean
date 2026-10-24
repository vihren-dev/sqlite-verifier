import Belay.Sqlite.Model.SubquerySelectResolution
import Belay.Sqlite.Model.SelectOneResolution
import Belay.Sqlite.Model.NoFromQuerySteps

set_option doc.verso true

/-! The resolution of {lit}`SELECT 1 WHERE c(EXISTS (SELECT 1 FROM t WHERE p))` (ADR 0017, S4),
the query form of "some row satisfies {lit}`p`" as a subquery: for a table that the catalog has, the statement
resolves to the simple query without source and with the condition {lit}`c`, and the one subquery, the simple
query of the first source of the table with the condition that {lit}`p` resolves to in the scope of the table. -/

namespace Belay.Sqlite.Model

/-- For every statement {lit}`SELECT 1 WHERE c` with one subquery {lit}`SELECT 1 FROM t WHERE p` of a table that
the catalog of the state has at a position, without table-function arguments, where {lit}`p` resolves in the
scope of the table to a condition, {lit}`c` resolves to a condition that has no fallible call for every shape of
the subquery that has no parent, resolution gives the simple query without source and with that condition,
the literal one named {lit}`"1"`, and the simple query of the first source of the table with the condition of
{lit}`p` as its one subquery, and leaves the state as it is. Proof sketch:
{name}`resolveStatement_select_of_resolveSelect` and {name}`resolveSelect_noFrom_one_subquery`; both
bodies resolve by {name}`resolveQueryBody_simple`, the subquery in the scope of its table
({name}`resolveSources_table`, {name}`resolvePendingSources_table`) and the statement's query in the empty
scope with the shape of the subquery. -/
theorem resolveStatement_selectOne_subquery (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (subFilter : Option Syntax.Expr) (mainFilter : Syntax.Expr)
    (position : Nat) (table : CatalogTable) (subCondition : Option Resolved.Expr) (mainCondition : Resolved.Expr)
    (arguments : reference.arguments = none) (found : state.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves context.profile.dqsDml (tableScope state.catalog reference position table) []
      subFilter subCondition { current := some 0 })
    (mainResolves : ∀ shape : SubqueryShape, shape.parent = none →
      FilterResolves context.profile.dqsDml [] [] (some mainFilter) (some mainCondition) { later := [shape] })
    (plain : mainCondition.any Resolved.Expr.isFallibleCall = false) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none
        [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
        none false none) =
      .ok (.query (Resolved.Query.simple [] (some mainCondition) [.scalar (.literal (.integer 1))] ["1"])
        [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar (.literal (.integer 1))] ["1"]], state) := by
  have simple : ∀ source filter, (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] source [] filter [] [] none none
      none none false none).Simple := fun _ _ => ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have noFeed : (([[(Resolved.Output.scalar (.literal (.integer 1)), "1", (none : Option Affinity))]] :
      List (List (Resolved.Output × String × Option Affinity))).flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false := by
    simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]
  have subBody := resolveQueryBody_simple context.profile.dqsDml (tableScope state.catalog reference position table)
    (some 0) [] [] _ (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none
      none none false none) (simple _ _) _ subCondition _
    (resolveColumns_one _ _ _) (by simpa [resultAliases] using subResolves)
    (resolvePendingSources_table _ _ position) noFeed
  have mainBody := fun shape (parentless : shape.parent = none) =>
    resolveQueryBody_simple context.profile.dqsDml [] none [shape] [] [] (Syntax.Subquery.mk [.expression (.numeric "1") none "1"]
      none [] (some mainFilter) [] [] none none none none false none) (simple _ _) _ (some mainCondition) _
    (resolveColumns_one _ _ _) (by simpa [resultAliases] using mainResolves shape parentless) (resolvePendingSources_nil _ _) noFeed
  refine resolveStatement_select_of_resolveSelect context state
    (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] none [] (some mainFilter) [] [] none none none none false none)
    _ rfl _ ?_
  refine resolveSelect_noFrom_one_subquery context state.catalog _ _ rfl rfl rfl (by simp [starIssue]) rfl rfl _ _
    (resolveSources_table state.catalog reference position table arguments found) (by simp [starIssue]) _ _
    (by simpa [resultAliases] using subBody) _ rfl _ _ (by simpa using mainBody _ rfl) ?_
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.simple, Resolved.Output.scalars,
    Resolved.Output.operands, plain, Resolved.Expr.any, Resolved.Expr.isFallibleCall]

/-- For every statement {lit}`SELECT 1 WHERE EXISTS (SELECT 1 FROM t WHERE p)` of a table that the catalog of the
state has at a position, without table-function arguments, where {lit}`p` resolves in the scope of the table to a
condition, resolution gives the simple query without source and with the condition {lit}`EXISTS` of subquery 0, and the
simple query of the first source of the table with the condition of {lit}`p` as its one subquery, and leaves the
state as it is. Proof sketch: {name}`resolveStatement_selectOne_subquery`; {lit}`EXISTS` resolves for the shape of the only
subquery ({name}`resolveOperand_exists`, {name}`SubqueryShapes.find_only`). -/
theorem resolveStatement_selectOne_exists (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (subFilter : Option Syntax.Expr) (position : Nat) (table : CatalogTable)
    (subCondition : Option Resolved.Expr) (arguments : reference.arguments = none)
    (found : state.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves context.profile.dqsDml (tableScope state.catalog reference position table) []
      subFilter subCondition { current := some 0 }) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] none [] (some (.exists 0)) [] [] none none
        [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
        none false none) =
      .ok (.query (Resolved.Query.selectOneWhere (.exists 0))
        [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar (.literal (.integer 1))] ["1"]], state) :=
  resolveStatement_selectOne_subquery context state reference subFilter (.exists 0) position table subCondition (.exists 0)
    arguments found subResolves (fun _ parentless => FilterResolves.of_term (by simp [namesAlias])
      (resolveOperand_exists (SubqueryShapes.find_only parentless)) ) (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall])

/-- For every statement {lit}`SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t WHERE p)` as in
{name}`resolveStatement_selectOne_exists`, resolution gives the simple query without source and with the condition
{lit}`NOT EXISTS` of subquery 0, and the same subquery. Proof sketch: {name}`resolveStatement_selectOne_subquery`;
{lit}`NOT` resolves its operand as a condition ({name}`resolveOperand_not`). -/
theorem resolveStatement_selectOne_notExists (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (subFilter : Option Syntax.Expr) (position : Nat) (table : CatalogTable)
    (subCondition : Option Resolved.Expr) (arguments : reference.arguments = none)
    (found : state.catalog.findTable reference.table = some (position, table))
    (subResolves : FilterResolves context.profile.dqsDml (tableScope state.catalog reference position table) []
      subFilter subCondition { current := some 0 }) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none none
        [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] subFilter [] [] none none none none false none]
        none false none) =
      .ok (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
        [Resolved.Query.simple [Resolved.QuerySource.first position] subCondition [.scalar (.literal (.integer 1))] ["1"]], state) :=
  resolveStatement_selectOne_subquery context state reference subFilter (.not (.exists 0)) position table subCondition
    (.not (.exists 0)) arguments found subResolves (fun _ parentless => FilterResolves.of_term (term := .not (.exists 0))
      (result := (.not (.exists 0), none)) (by simp [namesAlias])
      (by simp [resolveOperand_not, condition, resolveOperand_exists (SubqueryShapes.find_only parentless), Bind.bind,
        Except.bind])) (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall])

end Belay.Sqlite.Model
