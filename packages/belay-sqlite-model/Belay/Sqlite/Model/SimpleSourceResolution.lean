import Belay.Sqlite.Model.SimpleSelectResolution

set_option doc.verso true

/-! The resolution of the {lit}`FROM` clause of a query of one table and of the literal result column
{lit}`1` (ADR 0017, S4), as lemmas about {lit}`resolveSources`, {lit}`resolvePendingSources` and
{lit}`resolveColumns_one` for a catalog that has the table: the scope of the table, the one source on its
catalog position, and the resolved column. The catalog may be any catalog. -/

namespace Belay.Sqlite.Model

/-- The scope of a query of one table that the catalog has at a position: one source with the alias
of the reference, or else the name that the catalog gives the table, the columns of the table, and
whether it has a rowid. -/
def tableScope (catalog : Catalog) (reference : Syntax.TableReference) (position : Nat) (table : CatalogTable) : Scope :=
  Scope.single (reference.alias.getD ((catalog[position]?.map (·.name)).getD reference.table)) table.columns
    (!table.withoutRowid)

/-- A {lit}`FROM` clause that names one table, with no table-function arguments and no joins, resolves
when the catalog has the table: it gives one inner source on the catalog position of the table, and one
scope of the table ({name}`tableScope`). The catalog may be any catalog.

Proof sketch: unfold {name}`resolveSources` and the table lookup, and rewrite with the two hypotheses. -/
theorem resolveSources_table (catalog : Catalog) (reference : Syntax.TableReference) (position : Nat) (table : CatalogTable)
    (arguments : reference.arguments = none) (found : catalog.findTable reference.table = some (position, table)) :
    resolveSources catalog (some reference) [] = .ok ([{ item := .table position, kind := .inner, condition := .none }],
      tableScope catalog reference position table) := by
  simp [resolveSources, resolveReference, arguments, resolveTableReference, found, maximumJoinTables, Scope.place, mergeJoins, resolveAll, resolveAllFrom, Bind.bind, Except.bind, liftM, monadLift, MonadLift.monadLift, Except.mapError, joinOperator, Scope.single, tableScope, Functor.map, Except.map]

/-- No pending source resolves to no source, for any scope and quote setting. Proof sketch: there is no
condition and no argument to resolve. -/
theorem resolvePendingSources_nil (dqs : Bool) (scope : Scope) : resolvePendingSources dqs scope [] = .ok [] := by
  simp [resolvePendingSources, resolveAll, resolveAllFrom, resolveEachArguments, Bind.bind, Except.bind, Pure.pure, Except.pure]

/-- The one inner source without a condition, which {name}`resolveSources_table` gives, resolves to the
first source of the table, {name}`Resolved.QuerySource.first`, for any scope and quote setting.

Proof sketch: unfold the resolver and the join condition check; there is no condition to resolve. -/
theorem resolvePendingSources_table (dqs : Bool) (scope : Scope) (position : Nat) :
    resolvePendingSources dqs scope [{ item := .table position, kind := .inner, condition := .none }] =
      .ok [Resolved.QuerySource.first position] := by
  simp [resolvePendingSources, resolveJoinCondition, resolveAll, resolveAllFrom, Bind.bind, Except.bind, Pure.pure, Except.pure,
    Resolved.QuerySource.first]

/-- The result column {lit}`1` resolves, in any scope and with any shapes of subqueries, to the integer
literal one with the name {lit}`"1"` and no affinity.

Proof sketch: unfold the resolver; a numeric literal needs no scope. -/
theorem resolveColumns_one (dqs : Bool) (scope : Scope) (shapes : SubqueryShapes) :
    resolveAll (resolveResultColumn dqs scope shapes) [.expression (.numeric "1") none "1"] =
      .ok [[(.scalar (.literal (.integer 1)), "1", none)]] := by
  simp [resolveAll, resolveAllFrom, resolveResultColumn, resolveOperand, Bind.bind, Except.bind, Pure.pure, Except.pure]
  rfl

end Belay.Sqlite.Model
