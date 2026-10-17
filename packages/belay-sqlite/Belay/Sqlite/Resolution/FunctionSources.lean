import Belay.Sqlite.Resolution.Sources

set_option doc.verso true

/-! Resolution of the {lit}`json_each` sources of {lit}`FROM` (ADR 0012, amendment 5, slice
6d). The model describes them after the tables: a source list is the tables
({lit}`resolveTables`), then one or more {lit}`json_each` sources, each joined by a
comma, {lit}`JOIN`, {lit}`INNER JOIN` or {lit}`CROSS JOIN` with an optional {lit}`ON`
condition. The arguments of a source read the sources before it. The paths follow
{lit}`Syntax.Statement.select` as in {lit}`Sources.lean`; in a source, child 2 is the list
of its arguments. -/

namespace Belay.Sqlite

/-- The columns of {lit}`json_each` in SQLite's order, without declared types: the eight
that {lit}`*` shows, then the hidden {lit}`json` and {lit}`root`. -/
def eachColumns : List CatalogColumn :=
  ["key", "value", "type", "atom", "id", "parent", "fullkey", "path", "json", "root"].map
    fun name => { name, declaredType := none }

/-- The positions of the hidden columns {lit}`json` and {lit}`root` in
{name}`eachColumns`. -/
def eachHidden : List Nat := [8, 9]

/-- The largest number of arguments of {lit}`json_each` that SQLite accepts: the JSON and
the path ({lit}`too many arguments on json_each() - max 2`). -/
def maximumEachArguments : Nat := 2

/-- A {lit}`json_each` source of {lit}`FROM` before resolution: the path of its reference,
the reference with its arguments, and its {lit}`ON` condition with the path of that
condition. -/
structure FunctionItem where
  /-- The path of the reference: {lit}`[1]` for the first source, {lit}`[2, item, 1]` for a
  join. -/
  path : List Nat
  /-- The reference as written. -/
  reference : Syntax.TableReference
  /-- The arguments. -/
  arguments : List Syntax.Expr
  /-- The {lit}`ON` condition and its path. -/
  condition : Option (List Nat × Syntax.Expr)

/-- The function item of a reference at {lit}`path`, or the issue of a form that the
model does not describe: another function or no argument ({name}`RestrictionKind.tableFunction`),
and more than {name}`maximumEachArguments` arguments, which SQLite refuses. A table has no
item. -/
def functionItem (path : List Nat) (reference : Syntax.TableReference)
    (condition : Option (List Nat × Syntax.Expr)) : Option (Except ValueIssue FunctionItem) :=
  reference.arguments.map fun arguments =>
    if normalizeIdentifier reference.table != "json_each" || arguments.isEmpty then
      .error (.restriction path .tableFunction)
    else if arguments.length > maximumEachArguments then .error (.prepare .tooManyEachArguments)
    else .ok { path, reference, arguments, condition }

/-- The item of the join at {lit}`item` when its source is a function: an inner join
without {lit}`NATURAL` or {lit}`USING` ({name}`RestrictionKind.functionJoin`). -/
def joinItem (item : Nat) (join : Syntax.Join) : Option (Except ValueIssue FunctionItem) :=
  (functionItem [2, item, 1] join.source (join.condition.map ([2, item, 2], ·))).map fun result =>
    if joinOperator join.operator != some (.inner, false) || join.usingColumns.isSome then
      .error (.restriction [2, item, 0] .functionJoin)
    else result

/-- Split the sources of {lit}`FROM` into the tables, which {name}`resolveTables` resolves,
and the function items after them. A first source that is a function makes every source
a function; a table after a function is {name}`RestrictionKind.tableAfterFunction`. -/
def splitSources (source : Option Syntax.TableReference) (joins : List Syntax.Join) :
    Except ValueIssue (Option Syntax.TableReference × List Syntax.Join × List FunctionItem) := do
  let tableCount := match source.bind (functionItem [1] · none) with
    | some _ => 0
    | none => (joins.takeWhile (·.source.arguments.isNone)).length
  let first ← match source.bind (functionItem [1] · none) with
    | some result => (fun item => [item]) <$> result
    | none => pure []
  let rest ← resolveAllFrom (fun item join => match joinItem item join with
    | some result => result
    | none => .error (.restriction [2, item, 1] .tableAfterFunction)) tableCount (joins.drop tableCount)
  let tables := if first.isEmpty then source else none
  .ok (tables, joins.take tableCount, first ++ rest)

/-- For every table reference and joins whose sources are all tables (no arguments),
{name}`splitSources` gives the reference and all joins as tables and no function item.
Proof sketch: by induction on the joins, {lit}`takeWhile` keeps every join, so no join is
left for the function items; then {name}`splitSources` simplifies to its result. -/
theorem splitSources_tables (source : Syntax.TableReference) (joins : List Syntax.Join)
    (table : source.arguments = none) (tables : joins.all (·.source.arguments.isNone) = true) :
    splitSources (some source) joins = .ok (some source, joins, []) := by
  have whole : joins.takeWhile (·.source.arguments.isNone) = joins := by
    induction joins with
    | nil => rfl
    | cons join rest ih =>
      simp only [List.all_cons, Bool.and_eq_true] at tables
      simp [tables.1, ih tables.2]
  simp [splitSources, functionItem, table, whole, resolveAllFrom, pure, Except.pure, bind, Except.bind]

/-- The source in scope of a function item: its name (the alias, else the function name
as written) and the columns of {lit}`json_each`, two of them hidden. -/
def FunctionItem.source (item : FunctionItem) : Source :=
  { name := item.reference.alias.getD item.reference.table, columns := eachColumns, hidden := eachHidden }

/-- Resolve the function items over the whole scope, in which they are the last sources:
each argument must read only the sources before its function
({name}`RestrictionKind.laterSourceInArguments`), and each {lit}`ON` condition only the
sources up to its function ({name}`resolveJoinCondition`). -/
def resolveFunctions (dqs : Bool) (scope : Scope) (items : List FunctionItem) :
    Except ValueIssue (List Resolved.EachSource) :=
  let firstFunction := scope.length - items.length
  resolveAll (fun index item => do
    let bound := (scope.take (firstFunction + index)).foldl (fun width source => width + source.columns.length) 0
    let arguments ← resolveAll (fun position argument => do
      let (resolved, _) ← (resolveOperand dqs scope true argument).mapError (·.under (item.path ++ [2, position]))
      if resolved.readsBelow bound then .ok resolved
      else .error (.restriction (item.path ++ [2, position]) .laterSourceInArguments)) item.arguments
    let condition ← resolveJoinCondition dqs scope (firstFunction + index - 1) item.condition
    match arguments with
    | json :: path => .ok { json, path := path.head?, condition }
    | [] => .error (.restriction item.path .tableFunction)) items

/-- Resolve the sources of {lit}`FROM`: the tables ({name}`resolveTables`), then the scope
with the function items after them; two sources with the same folded name are a model
restriction, as for tables. -/
def resolveSources (catalog : Catalog) (source : Option Syntax.TableReference) (joins : List Syntax.Join) :
    Except ValueIssue (Option Nat × List (Nat × Option (List Nat × Syntax.Expr)) × Scope × List FunctionItem) := do
  let (tables, tableJoins, items) ← splitSources source joins
  let (first, joined, scope) ← resolveTables catalog tables tableJoins
  let full := scope ++ items.map FunctionItem.source
  if let some item := items.zipIdx.find? fun (item, index) => (full.take (scope.length + index)).any fun earlier =>
      normalizeIdentifier earlier.name == normalizeIdentifier item.source.name then
    throw (.restriction item.1.path .duplicateSource)
  .ok (first, joined, full, items)

end Belay.Sqlite
