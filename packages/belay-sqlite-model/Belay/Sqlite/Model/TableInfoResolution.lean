import Belay.Sqlite.Model.SimpleStatementResolution
import Belay.Sqlite.Model.Resolution.FunctionSources

set_option doc.verso true

/-! The resolution of the source {lit}`pragma_table_info('t')` (ADR 0017, S4): when the catalog has no table of the
name of the function, the source resolves to the one pragma source with the rows of {lit}`Catalog.tableInfoRows` for the
table {lit}`t`, and the scope of its columns and its two hidden cells. -/

namespace Belay.Sqlite.Model

/-- For every name that is the keyword {lit}`pragma_table_info` without ASCII case, the lowercase name starts with
{lit}`pragma_`, which is the test of {name}`resolveReference` for a table-valued pragma. Proof sketch: the lowercase
name is the keyword ({name}`equalsKeyword`), which starts with {lit}`pragma_` by computation. -/
theorem Identifier.pragma_prefix_of_isKeyword (name : Identifier)
    (isFunction : name.isKeyword (bytes! "pragma_table_info") = true) :
    (bytes! "pragma_").isPrefixOf name.folded = true := by
  have folded : name.folded = bytes! "pragma_table_info" := by
    simpa [Identifier.isKeyword, equalsKeyword, Identifier.folded] using isFunction
  rw [folded]
  decide

/-- The scope of the source {lit}`pragma_table_info('t')` with the rows of the table: the eight cells of
{name}`pragmaSource`, the six columns of the pragma and the two hidden cells, under the alias of the reference or
else the name of the function. -/
def tableInfoScope (reference : Syntax.TableReference) (argument : List UInt8) (rows : List (List Value)) : Scope :=
  Scope.place [(pragmaSource reference argument tableInfoNames rows).2] 0

/-- For every catalog, reference to the function {lit}`pragma_table_info` with one text argument, when the catalog has no
table with the name of the function and has rows for the table of the argument, a {lit}`FROM` clause of that reference alone
resolves to the one inner pragma source with those rows, and the scope of {name}`tableInfoScope`. Proof sketch: unfold
{name}`resolveSources` and {name}`pragmaReference`; the reference has arguments and the prefix {lit}`pragma_`, so
{name}`resolveReference` takes the pragma branch, and the scope of one source is placed at offset 0. -/
theorem resolveSources_tableInfo (catalog : Catalog) (reference : Syntax.TableReference) (argument : List UInt8)
    (rows : List (List Value)) (arguments : reference.arguments = some [.string argument])
    (isFunction : reference.table.isKeyword (bytes! "pragma_table_info") = true)
    (notTable : catalog.findTable reference.table = none)
    (info : catalog.tableInfoRows ⟨argument⟩ = some rows) :
    resolveSources catalog (some reference) [] = .ok ([{
        item := .pragma (pragmaSource reference argument tableInfoNames rows).1, kind := .inner, condition := .none }],
      tableInfoScope reference argument rows) := by
  have prefixed := Identifier.pragma_prefix_of_isKeyword _ isFunction
  simp [resolveSources, resolveReference, arguments, prefixed, pragmaReference, notTable, isFunction, info, maximumJoinTables,
    mergeJoins, resolveAll, resolveAllFrom, Bind.bind, Except.bind, liftM, monadLift, MonadLift.monadLift, Except.mapError,
    joinOperator, tableInfoScope, Functor.map, Except.map, Scope.place]

/-- The first source of a query that is a pragma with the rows of the pragma, as an inner join without a condition. -/
def Resolved.QuerySource.pragma (rows : Resolved.PragmaRows) : Resolved.QuerySource :=
  { kind := .inner, source := .pragma rows, condition := none }

/-- The one inner pragma source without a condition, which {name}`resolveSources_tableInfo` gives, resolves to the
source {name}`Resolved.QuerySource.pragma`, for any scope and quote setting. Proof sketch: unfold the resolver and the
join condition check; there is no condition to resolve. -/
theorem resolvePendingSources_pragma (dqs : Bool) (scope : Scope) (rows : Resolved.PragmaRows) :
    resolvePendingSources dqs scope [{ item := .pragma rows, kind := .inner, condition := .none }] =
      .ok [Resolved.QuerySource.pragma rows] := by
  simp [resolvePendingSources, resolveJoinCondition, resolveAll, resolveAllFrom, Bind.bind, Except.bind, Pure.pure,
    Except.pure, Resolved.QuerySource.pragma]

/-- For every statement {lit}`SELECT 1 FROM pragma_table_info('t') WHERE p` (or without {lit}`WHERE`) whose reference
is as in {name}`resolveSources_tableInfo` and whose condition resolves in the scope of the pragma
({name}`tableInfoScope`) to a condition ({name}`FilterResolves`), resolution gives the simple query of the pragma
source with the rows of {name}`resolveSources_tableInfo`, the literal one named {lit}`"1"`, and that condition, with no
subquery, and leaves the state as it is. Proof sketch: {name}`resolveStatement_select_simple` with the source of
{name}`resolveSources_tableInfo`, the pending source of {name}`resolvePendingSources_pragma` and the column of
{name}`resolveColumns_one`; the only column is not a star and calls no aggregate. -/
theorem resolveStatement_select_one_tableInfo (context : ResolveContext) (state : ResolveState)
    (reference : Syntax.TableReference) (argument : List UInt8) (rows : List (List Value)) (filter : Option Syntax.Expr)
    (condition : Option Resolved.Expr) (arguments : reference.arguments = some [.string argument])
    (isFunction : reference.table.isKeyword (bytes! "pragma_table_info") = true)
    (notTable : state.catalog.findTable reference.table = none)
    (info : state.catalog.tableInfoRows ⟨argument⟩ = some rows)
    (resolves : FilterResolves context.profile.dqsDml (tableInfoScope reference argument rows) [] filter condition) :
    resolveStatement context state (.select [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none
        none [] none false none) =
      .ok (.query (Resolved.Query.simple [Resolved.QuerySource.pragma (pragmaSource reference argument tableInfoNames rows).1]
        condition [.scalar (.literal (.integer 1))] ["1"]) [], state) := by
  have columns := resolveColumns_one context.profile.dqsDml (tableInfoScope reference argument rows) { later := [] }
  have simple : (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none none
      none false none).Simple :=
    ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  have result := resolveStatement_select_simple context state
    (Syntax.Subquery.mk [.expression (.numeric "1") none "1"] (some reference) [] filter [] [] none none none none false none)
    simple rfl _ _ _ condition _ (resolveSources_tableInfo state.catalog reference argument rows arguments isFunction notTable info)
    (by simp [starIssue]) columns (by simpa [resultAliases] using resolves)
    (resolvePendingSources_pragma context.profile.dqsDml _ _)
    (by simp [Resolved.Expr.any, Resolved.Expr.isFallibleCall])
  simpa using result

end Belay.Sqlite.Model
