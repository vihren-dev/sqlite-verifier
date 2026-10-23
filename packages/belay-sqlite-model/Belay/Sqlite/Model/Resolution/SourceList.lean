import Belay.Sqlite.Model.Resolution.FunctionSources

set_option doc.verso true

/-! Resolution of the sources of {lit}`FROM` in written order (ADR 0013, D5): tables,
{lit}`json_each` sources and table-valued pragmas in any order, each joined to the sources before it. As in
SQLite, every reference resolves before the forms of the joins, and the {lit}`ON`
conditions and the {lit}`json_each` arguments resolve after {lit}`WHERE`
({lit}`resolveSelect`). The paths follow {lit}`Syntax.Statement.select`: child 1 is the
first source and child 2 the joins; in a join, child 0 is its operator and child 1 its
source. -/

namespace Belay.Sqlite.Model

/-- A source of {lit}`FROM` whose reference is resolved: a table at its catalog position,
{lit}`json_each` with the path of its reference and its arguments as written, which
resolve after the scope is complete ({name}`resolveEachArguments`), or the rows of a
table-valued pragma ({name}`pragmaReference`). -/
inductive SourceItem where
  /-- A table at its position in the catalog. -/
  | table (position : Nat)
  /-- A {lit}`json_each` source: the path of its reference and its arguments. -/
  | each (path : List Nat) (arguments : List Syntax.Expr)
  /-- A table-valued pragma with its rows. -/
  | pragma (rows : Resolved.PragmaRows)

/-- A source of {lit}`FROM` before its expressions resolve: the source, the kind of its
join with the sources before it, and its condition. -/
structure PendingSource where
  /-- The table or {lit}`json_each` source. -/
  item : SourceItem
  /-- The kind of the join; an inner join for the first source. -/
  kind : Resolved.JoinKind
  /-- The condition of the join; none for the first source. -/
  condition : JoinCondition

/-- The item and the source in scope of the reference at {lit}`path`: a table
({name}`resolveTableReference`), a table-valued pragma, whose name starts with
{lit}`pragma_` ({name}`pragmaReference`), or {lit}`json_each` ({name}`eachReference`). -/
def resolveReference (catalog : Catalog) (path : List Nat) (reference : Syntax.TableReference) :
    Except SourceIssue (SourceItem × ScopeSource) :=
  match reference.arguments with
  | none => (fun (position, source) => (.table position, source)) <$> resolveTableReference catalog path reference
  | some arguments =>
    if (bytes! "pragma_").isPrefixOf reference.table.folded then
      (fun (rows, source) => (.pragma rows, source)) <$> (pragmaReference catalog path reference arguments).mapError .value
    else (fun source => (.each path arguments, source)) <$> (eachReference path reference arguments).mapError .value

/-- Whether the model refuses the join at {lit}`item` for a {lit}`json_each` source
({name}`RestrictionKind.functionJoin`): its source is {lit}`json_each` as the right operand
of a right or full join, or with {lit}`USING` or {lit}`NATURAL`; or it is {lit}`NATURAL` and
an earlier source is {lit}`json_each` ({lit}`afterFunction`), whose hidden columns SQLite
skips. An operator that SQLite refuses is left to {name}`mergeJoins`. -/
def functionJoinChecked (afterFunction : Bool) (item : Nat) (join : Syntax.Join)
    (operator : Option (Resolved.JoinKind × Bool)) : Except ValueIssue Unit :=
  let natural := operator.any (·.2)
  if join.source.arguments.isSome && (rightOrFull operator || join.usingColumns.isSome || natural)
      || afterFunction && natural then
    .error (.restriction [2, item, 0] .functionJoin)
  else .ok ()

/-- Resolve the sources of {lit}`FROM` in written order: the pending sources and the scope
of all of them. More than {name}`maximumJoinTables` sources is SQLite's
{lit}`at most 64 tables in a join`; then each reference resolves in order
({name}`resolveReference`, {name}`functionJoinChecked`); then each join in order ({name}`mergeJoins`), whose
generated conditions coalesce the left columns when any join is a right or full join. No
{lit}`FROM` gives no source and the empty scope. The first cell is at {lit}`start`: 0 for a
statement's query, after the outer cells for a subquery. -/
def resolveSources (catalog : Catalog) (source : Option Syntax.TableReference) (joins : List Syntax.Join)
    (start : Nat := 0) : Except SourceIssue (List PendingSource × Scope) := do
  let some source := source | .ok ([], [])
  if joins.length + 1 > maximumJoinTables then throw (.value (.prepare .tooManyTables))
  let (firstItem, firstSource) ← resolveReference catalog [1] source
  let operators := joins.map (joinOperator ·.operator)
  let joined ← resolveAll (fun item ((join : Syntax.Join), operator) => do
    let resolved ← resolveReference catalog [2, item, 1] join.source
    let earlier := source :: (joins.take item).map (·.source)
    functionJoinChecked (earlier.any (·.arguments.isSome)) item join operator
    .ok resolved) (joins.zip operators)
  let placed := Scope.place (firstSource :: joined.map Prod.snd) start
  let (scope, conditions) ← mergeJoins (operators.any rightOrFull) (placed.take 1) 0
    (joins.zip (operators.zip (placed.drop 1)))
  let first : PendingSource := { item := firstItem, kind := .inner, condition := .none }
  .ok (first :: ((joined.map Prod.fst).zip conditions).map fun (item, kind, condition) => { item, kind, condition },
    scope)

/-- Resolve the expressions of the pending sources over the complete scope: first every
{lit}`ON` condition in order ({name}`resolveJoinCondition`), then the arguments of every
{lit}`json_each` source in order ({name}`resolveEachArguments`), as SQLite resolves them
after {lit}`WHERE`. -/
def resolvePendingSources (dqs : Bool) (scope : Scope) (sources : List PendingSource) :
    Except ValueIssue (List Resolved.QuerySource) := do
  let conditions ← resolveAll (fun index (source : PendingSource) => resolveJoinCondition dqs scope index source.condition)
    sources
  resolveAll (fun index ((source : PendingSource), condition) => do
    let resolved ← match source.item with
      | .table position => pure (Resolved.Source.table position)
      | .each path arguments => resolveEachArguments dqs scope index path arguments
      | .pragma rows => pure (Resolved.Source.pragma rows)
    .ok { kind := source.kind, source := resolved, condition }) (sources.zip conditions)

end Belay.Sqlite.Model
