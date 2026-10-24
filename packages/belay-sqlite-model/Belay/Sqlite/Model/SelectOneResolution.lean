import Belay.Sqlite.Model.SimpleStatementResolution
import Belay.Sqlite.Model.StatementCalm

set_option doc.verso true

/-! The resolution of {lit}`SELECT 1 FROM t WHERE p` (ADR 0017, S4), the query form of "some row
satisfies {lit}`p`": for a table that the catalog has, the statement resolves to the simple query
of the first source of that table, the integer literal one, and the condition that {lit}`p`
resolves to in the scope of the table. A statement without {lit}`WHERE` has no condition. -/

namespace Belay.Sqlite.Model

/-- For every statement {lit}`SELECT 1 FROM t WHERE p` (or without {lit}`WHERE`) of a table that the
catalog of the state has at a position, without table-function arguments, whose condition resolves
in the scope of the table to a condition ({name}`FilterResolves`), resolution gives the simple query
of the first source of the table, the literal one named {lit}`"1"`, and that condition, with no
subquery, and leaves the state as it is. The source reference has no indexed query.
Proof sketch: {name}`resolveStatement_select_simple` with
the source of {name}`resolveSources_table`, the pending source of
{name}`resolvePendingSources_table` and the column of {name}`resolveColumns_one`; the only column
is not a star and calls no aggregate. -/
theorem resolveStatement_select_one_from (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (filter : Option Syntax.Expr) (position : Nat) (table : CatalogTable)
    (condition : Option Resolved.Expr) (namedSource : reference.query = none) (arguments : reference.arguments = none)
    (found : state.catalog.findTable reference.table = some (position, table))
    (resolves : FilterResolves context.profile.dqsDml
      (tableScope state.catalog reference position table) [] filter condition) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none
        none [] none false none) =
      .ok (.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition
        [.scalar (.literal (.integer 1))] ["1"]) [], state) := by
  have columns := resolveColumns_one context.profile.dqsDml (tableScope state.catalog reference position table) { later := [] }
  have simple : (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none none
      none false none).Simple :=
    ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have result := resolveStatement_select_simple context state
    (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none none none false none)
    simple rfl _ _ _ condition _ (resolveSources_table state.catalog reference position table namedSource arguments found)
    (by simp [starIssue]) columns (by simpa [resultAliases] using resolves)
    (resolvePendingSources_table context.profile.dqsDml _ position)
    (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall])
  simpa using result

/-- For every condition whose expressions are calm ({name}`Resolved.Expr.Calm`) and every position, the
statement of the query {lit}`SELECT 1 FROM t WHERE p` that resolution gives is calm
({name}`Resolved.Statement.Calm`): the literal one is calm, and the first source of a table has no
expression. Proof sketch: the expressions of the statement are the condition and the literal. -/
theorem Resolved.Statement.Calm.selectOne (position : Nat) (condition : Option Resolved.Expr)
    (calm : ∀ expression ∈ condition.toList, expression.Calm) :
    (Resolved.Statement.query (Resolved.Query.simple [Resolved.QuerySource.first position] condition
      [.scalar (.literal (.integer 1))] ["1"]) []).Calm := by
  intro expression member
  simp only [Resolved.Statement.clockExpressions, Resolved.Query.expressions, Resolved.Query.keptExpressions,
    Resolved.Query.simple, Resolved.QuerySource.first, Resolved.QuerySource.expressions, List.mem_append,
    List.mem_flatMap, List.flatMap_nil, List.append_nil, List.mem_cons, List.mem_nil_iff, or_false] at member
  have literal : (Resolved.Expr.literal (.integer 1)).Calm := by
    simp [Resolved.Expr.Calm, Resolved.Expr.any, Resolved.Expr.isFallibleCall, Resolved.Expr.readsClockHere,
      Resolved.Expr.readsCounterHere]
  simp only [Resolved.Output.scalars, Resolved.Output.operands, List.mem_singleton, List.not_mem_nil, exists_eq_left,
    List.map_nil, or_false, Option.toList_none] at member
  rcases member with member | rfl
  · exact calm expression member
  · exact literal

end Belay.Sqlite.Model
