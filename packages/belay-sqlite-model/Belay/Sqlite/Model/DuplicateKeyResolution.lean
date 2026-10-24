import Belay.Sqlite.Model.CountStatementResolution
import Belay.Sqlite.Model.DuplicateKeyQuery
import Belay.Sqlite.Model.ExistsStatementResolution
import Belay.Sqlite.Model.ScalarSubqueryResolution

set_option doc.verso true

/-! The resolution of {lit}`SELECT 1 FROM t GROUP BY k HAVING count(*) > 1` (ADR 0017, S4): the body of the query
resolves to the duplicate-key query ({name}`Belay.Sqlite.Model.Resolved.Query.duplicateKeys`) of its resolved sources,
grouping key and collation. The lemma takes the resolved sources and grouping term as hypotheses, because the catalog
is free. -/

namespace Belay.Sqlite.Model

/-- The grouping term {lit}`k` resolves ({name}`resolveGroupTerm`), for a query whose one result column is the literal
one named {lit}`"1"` and which has no alias, in a scope and with shapes of subqueries, to the key {lit}`key` under the
collation {lit}`collation`. The formula is exactly that equation of the resolver: resolution succeeds, and its result
is that key and that collation. It restricts the term only as the resolver does, so the cases are those of the
resolver: a name of a column of the scope (also under one {lit}`COLLATE`) or a qualified name resolves to the column,
and a name that is no column can resolve in the other ways that {name}`resolveOperand` allows, such as a quoted text
when the profile allows it ({lit}`dqs`) or the constants {lit}`TRUE` and {lit}`FALSE`. The collation is the
explicit one if there is one, else the collation of the column, else {lit}`BINARY`. A parameter resolves to a constant
value, and the result-column number {lit}`1` to the literal one, both with {lit}`BINARY`. A term that the resolver
rejects, such as an aggregate call, a number other than {lit}`1` or an expression, makes the equation false. -/
def GroupTermResolves (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (term : Syntax.Expr) (key : Resolved.Expr)
    (collation : Collation) : Prop :=
  resolveGroupTerm dqs scope shapes [none] [(.scalar (.literal (.integer 1)), "1", none)] [.binary] 0 term =
    .ok (key, collation)

/-- For every catalog, table reference, position, table, shapes, name and quote kind, if the table has a column of that
name at a position, the grouping term of that name resolves, in the scope of the table, to the cell of that column
under the collation of the column ({lit}`BINARY` when the column has none). The formula requires nothing of a name that
the table does not have. Proof sketch: the name resolves to the column alone ({name}`resolveName_one_source`) and the
collation is the column collation of {name}`Syntax.Expr.columnCollation_identifier_table`. -/
theorem GroupTermResolves.identifier_table {dqs : Bool} {catalog : Catalog} {reference : Syntax.TableReference}
    {position : Nat} {table : CatalogTable} {shapes : SubqueryShapes} {name : Identifier} {quote : Syntax.QuoteKind}
    {index : Nat} (found : columnPosition table.columns name = some index) :
    GroupTermResolves dqs (tableScope catalog reference position table) shapes (.identifier name quote) (.column index)
      ((table.columns[index]?.map (·.collation)).getD .binary) := by
  have resolved : (tableScope catalog reference position table).resolveName name = .found index [index] :=
    resolveName_one_source found
  have collation := Syntax.Expr.columnCollation_identifier_table (catalog := catalog) (reference := reference)
    (position := position) (quote := quote) found
  unfold GroupTermResolves resolveGroupTerm
  simp only [resolved]
  simp only [tableScope, Scope.single] at collation
  simp [tableScope, Scope.nameRead, Scope.nameOperand, Scope.single, Scope.argumentCell, Scope.triggerCell,
    Scope.columns, Syntax.Expr.collationIn, Syntax.Expr.explicitCollation, collation]
  rfl

/-- For every scope, shapes and name of a call, the condition {lit}`count(*) > 1` resolves, when the
aggregate calls of the query are the one call {lit}`count(*)`, to the comparison of the value of aggregate 0 with
the literal one, under {lit}`BINARY`, with no affinity. Proof sketch: unfold the resolver; the call is the aggregate
with index 0, and neither operand names a column. -/
theorem resolveOperand_moreThanOne (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) (name : String)
    (aggregates : shapes.aggregates = [.callStar name]) :
    resolveOperand dqs scope shapes false (.compare .gt (.callStar name) (.numeric "1")) =
      .ok (.compare .gt none (.aggregateValue 0) (.literal (.integer 1)) .binary, none) := by
  have literal : queryNumeric "1" false = .ok (.integer 1) := by rfl
  simp [resolveOperand, aggregates, Syntax.Expr.indexIn, Syntax.Expr.same, literal, truthTest, comparisonAffinity,
    comparisonCollation, Syntax.Expr.explicitCollation, Syntax.Expr.columnCollation, Bind.bind, Except.bind]
  rfl

/-- For every query {lit}`SELECT 1 FROM … GROUP BY k HAVING count(*) > 1` without join, {lit}`WHERE`, ordering and window,
whose pending sources resolve and whose grouping term resolves ({name}`GroupTermResolves`) with the aggregate call
{lit}`count(*)`, the body resolves to the duplicate-key query of its sources, key and collation
({name}`Resolved.Query.duplicateKeys`), named {lit}`"1"`, with no affinity. Proof sketch: unfold the resolver; the
query is an aggregate query whose one aggregate is the call of {lit}`HAVING`, the result column is the literal one,
{name}`resolveOperand_moreThanOne` gives {lit}`HAVING`, and every clause that the query lacks resolves to its empty
form. -/
theorem resolveQueryBody_duplicateKeys (dqs : Bool) (scope : Scope) (current : Option Nat) (later : List SubqueryShape)
    (outerAliases : List Identifier) (pending : List PendingSource) (source : Option Syntax.TableReference)
    (term : Syntax.Expr) (name : String) (count : normalizeIdentifier name = "count") (key : Resolved.Expr)
    (collation : Collation) (sources : List Resolved.QuerySource)
    (groupResolves : GroupTermResolves dqs scope { current, later, aggregates := [.callStar name] } term key collation)
    (pendingOk : resolvePendingSources dqs scope pending = .ok sources) :
    resolveQueryBody dqs scope { current, later } outerAliases pending
        (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] source [] none [term] [] none none none
          (some (.compare .gt (.callStar name) (.numeric "1"))) false none) =
      .ok (Resolved.Query.duplicateKeys sources key collation, none) := by
  have called : aggregateCall (.callStar name) = true := by simp [aggregateCall, count]
  have columns := resolveColumns_one dqs scope { current, later, aggregates := [.callStar name] }
  have havingCalls : (Syntax.Expr.compare .gt (.callStar name) (.numeric "1")).aggregateCalls = [.callStar name] := by
    simp [Syntax.Expr.aggregateCalls, aggregateCall, count]
  have oneCalls : (Syntax.Expr.numeric "1").aggregateCalls = [] := by simp [Syntax.Expr.aggregateCalls, aggregateCall]
  have calls : Syntax.Expr.distinctList [.callStar name] = [.callStar name] := by simp [Syntax.Expr.distinctList]
  have aggregates : resolveAll (fun _ call => resolveAggregateCall dqs scope { current, later, aggregates := [.callStar name] } call)
      [.callStar name] = .ok [.countRows] := by
    simp [resolveAll, resolveAllFrom, resolveAggregateCall, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have aliases : resultAliases scope [.expression (.numeric "1") none "1"] = [none] := by simp [resultAliases]
  have collations : resultCollations scope [.expression (.numeric "1") none "1"] = [.binary] := by
    simp [resultCollations, Syntax.Expr.collationIn, Syntax.Expr.explicitCollation, Syntax.Expr.columnCollation]
  have terms : resolveAll (resolveGroupTerm dqs scope { current, later, aggregates := [.callStar name] } [none]
      [(.scalar (.literal (.integer 1)), "1", none)] [.binary]) [term] = .ok [(key, collation)] := by
    simp [resolveAll, resolveAllFrom, show resolveGroupTerm dqs scope { current, later, aggregates := [.callStar name] } [none]
      [(.scalar (.literal (.integer 1)), "1", none)] [.binary] 0 term = .ok (key, collation) from groupResolves, Bind.bind,
      Except.bind, Pure.pure, Except.pure]
  have names : ∀ list, namesAlias scope list (.compare .gt (.callStar name) (.numeric "1")) = false := by
    intro list; simp [namesAlias]
  have having := resolveOperand_moreThanOne dqs scope { current, later, aggregates := [.callStar name] } name rfl
  unfold resolveQueryBody
  dsimp only
  simp only [oneCalls, havingCalls, calls, Option.toList_some, List.flatMap_cons, List.flatMap_nil, List.append_nil,
    List.isEmpty_cons, List.isEmpty_nil, List.any_cons, List.any_nil, aggregateCall, Bool.false_or, Bool.not_false, Bool.true_or, Bool.false_eq_true, ↓reduceIte, List.nil_append, Bool.not_true, Bool.and_false, Bool.false_and]
  simp only [aggregates, columns, pendingOk, aliases, collations, List.flatten_cons, List.flatten_nil, List.append_nil, terms,
    names, having, Bind.bind, Except.bind, Pure.pure, Except.pure]
  have nothing : ∀ {α β : Type} (f : Nat → α → Except ValueIssue β), resolveAll f [] = .ok [] := fun f => by
    simp [resolveAll, resolveAllFrom]
  simp [nothing, condition, groupedOutput, Resolved.Expr.grouped, windowSkipsFailure, windowValue, Resolved.Expr.any,
    Resolved.Expr.isFallibleCall, Resolved.Query.duplicateKeys]

/-- For every statement {lit}`SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM t GROUP BY k HAVING count(*) > 1)` of a table that
the catalog of the state has at a position, without table-function arguments, where {lit}`k` resolves in the scope
of the table to a key under a collation ({name}`GroupTermResolves`), resolution gives the simple query without source
and with the condition {lit}`NOT EXISTS` of subquery 0, and the duplicate-key query of the first source of the table as
its one subquery, and leaves the state as it is. Proof sketch: {name}`resolveStatement_select_of_resolveSelect` and
{name}`resolveSelect_noFrom_one_subquery`; the subquery resolves by {name}`resolveQueryBody_duplicateKeys` in the scope
of its table ({name}`resolveSources_table`, {name}`resolvePendingSources_table`), and the statement's query by
{name}`resolveQueryBody_simple` in the empty scope with the shape of the subquery, as for the other forms of
{lit}`NOT EXISTS`. -/
theorem resolveStatement_selectOne_notExists_duplicateKeys (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (term : Syntax.Expr) (name : String) (count : normalizeIdentifier name = "count")
    (position : Nat) (table : CatalogTable) (key : Resolved.Expr) (collation : Collation)
    (arguments : reference.arguments = none) (found : state.catalog.findTable reference.table = some (position, table))
    (groupResolves : GroupTermResolves context.profile.dqsDml (tableScope state.catalog reference position table)
      { current := some 0, aggregates := [.callStar name] } term key collation) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] []
        none none
        [Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] none [term] [] none none none
          (some (.compare .gt (.callStar name) (.numeric "1"))) false none] none false none) =
      .ok (.query (Resolved.Query.selectOneWhere (.not (.exists 0)))
        [Resolved.Query.duplicateKeys [Resolved.QuerySource.first position] key collation], state) := by
  have simple : ∀ source filter, (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] source [] filter [] [] none none
      none none false none).Simple := fun _ _ => ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have noFeed : (([[(Resolved.Output.scalar (.literal (.integer 1)), "1", (none : Option Affinity))]] :
      List (List (Resolved.Output × String × Option Affinity))).flatten.filterMap fun (output, _) => match output with
      | .scalar expression => some expression
      | .aggregate _ => none).any (fun expression =>
        expression.any fun node => node.isFallibleCall && node.any (· matches .aggregateValue _)) = false := by
    simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall]
  have subBody := resolveQueryBody_duplicateKeys context.profile.dqsDml (tableScope state.catalog reference position table)
    (some 0) [] [] _ (some reference) term name count key collation _ groupResolves (resolvePendingSources_table _ _ position)
  have mainResolves : ∀ shape : SubqueryShape, shape.parent = none →
      FilterResolves context.profile.dqsDml [] [] (some (.not (.exists 0))) (some (.not (.exists 0))) { later := [shape] } :=
    fun _ parentless => FilterResolves.of_term (term := .not (.exists 0)) (result := (.not (.exists 0), none))
      (by simp [namesAlias])
      (by simp [resolveOperand_not, condition, resolveOperand_exists (SubqueryShapes.find_only parentless), Bind.bind,
        Except.bind])
  have mainBody := fun shape (parentless : shape.parent = none) =>
    resolveQueryBody_simple context.profile.dqsDml [] none [shape] [] [] (Syntax.Subquery.mk [.expression (.numeric "1") none "1"]
      none [] (some (.not (.exists 0))) [] [] none none none none false none) (simple _ _) _ (some (.not (.exists 0))) _
    (resolveColumns_one _ _ _) (by simpa [resultAliases] using mainResolves shape parentless)
    (resolvePendingSources_nil _ _) noFeed
  refine resolveStatement_select_of_resolveSelect context state
    (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] none [] (some (.not (.exists 0))) [] [] none none none none false none)
    _ rfl _ ?_
  refine resolveSelect_noFrom_one_subquery context state.catalog _ _ rfl rfl rfl (by simp [starIssue]) rfl rfl _ _
    (resolveSources_table state.catalog reference position table arguments found) (by simp [starIssue]) _ _
    (by simpa [resultAliases] using subBody) _ rfl _ _ (by simpa using mainBody _ rfl) ?_
  simp [Resolved.Query.expressions, Resolved.Query.keptExpressions, Resolved.Query.simple, Resolved.Output.scalars,
    Resolved.Output.operands, Resolved.Expr.any, Resolved.Expr.isFallibleCall]

end Belay.Sqlite.Model
