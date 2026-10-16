import Belay.Sqlite.Resolution.Writes
import Belay.Sqlite.Resolution.JoinUsing

set_option doc.verso true

/-! Resolution of the {lit}`FROM` of a {lit}`SELECT` (ADR 0012, amendment 2): the tables
and their names, the joins, and their {lit}`ON` conditions. The paths follow
{lit}`Syntax.Statement.select`: child 1 is the first table and child 2 the joins; in a
join, child 0 is its operator, child 1 its table, child 2 its {lit}`ON` condition and
child 3 its {lit}`USING` list. -/

namespace Belay.Sqlite

/-- Whether every column that the expression reads has a position below the bound: the
expression reads only the tables whose cells come before it in the joined row. -/
def Resolved.Expr.readsBelow (bound : Nat) : Resolved.Expr → Bool
  | .column position => position < bound
  | .literal _ => true
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .coalesce left right =>
    left.readsBelow bound && right.readsBelow bound
  | .not operand | .isNull operand _ | .cast _ operand => operand.readsBelow bound

/-- The columns of {lit}`source.*` with their expansions ({name}`Scope.starOperand`) and
their names, or SQLite's {lit}`no such table: source` when no source has the name. -/
def sourceStarColumns (scope : Scope) (source : String) : Except ValueIssue (List (Resolved.Expr × String)) :=
  match scope.source? source with
  | some (offset, columns) => .ok (columns.mapIdx fun position column =>
      ((scope.starOperand (offset + position) column).1, column.name))
  | none => .error (.prepare (.noSuchSource source))

/-- The number of tables in a join that SQLite accepts ({lit}`SQLITE_MAX_SRCLIST`). -/
def maximumJoinTables : Nat := 64

/-- The source of one table reference at {lit}`path`: the table's catalog position and the
source with its name (the alias, else the table name). A missing table is SQLite's
{lit}`no such table: %s`; one of SQLite's own tables is a model restriction, as in a
query of one table. -/
def resolveTableReference (catalog : Catalog) (path : List Nat) (reference : Syntax.TableReference) :
    Except ValueIssue (Nat × Source) :=
  match catalog.findTable reference.table with
  | some (position, table) => .ok (position, { name := reference.alias.getD reference.table, columns := table.columns })
  | none =>
    if reservedName reference.table then .error (.restriction path .systemTable)
    else .error (.prepare (.noSuchTable reference.table))

/-- The kind of a join that Lean reads from the keywords of its operator
({name}`Syntax.Join.operator`): an inner join ({lit}`,`,
{lit}`JOIN`, {lit}`INNER JOIN` or {lit}`CROSS JOIN`), or a left, right or full outer
join. -/
inductive JoinOperatorKind where
  /-- An inner join. -/
  | inner
  /-- {lit}`LEFT [OUTER] JOIN`. -/
  | left
  /-- {lit}`RIGHT [OUTER] JOIN`. -/
  | right
  /-- {lit}`FULL [OUTER] JOIN`. -/
  | full
  deriving Repr, DecidableEq

/-- The kind of a join operator and whether it has {lit}`NATURAL`, from its keywords as
written, which SQLite compares without ASCII case: {lean}`joinOperator ["Left", "OUTER"]`
is a left join without {lit}`NATURAL`. None for keywords that the model does not
describe, such as {lean}`["OUTER", "LEFT"]`, which SQLite also accepts. -/
def joinOperator (words : List String) : Option (JoinOperatorKind × Bool) :=
  let folded := words.map normalizeIdentifier
  let (natural, rest) := match folded with
    | "natural" :: rest => (true, rest)
    | rest => (false, rest)
  let kind : Option JoinOperatorKind := match rest with
    | [] | ["inner"] | ["cross"] => some .inner
    | ["left"] | ["left", "outer"] => some .left
    | ["right"] | ["right", "outer"] => some .right
    | ["full"] | ["full", "outer"] => some .full
    | _ => none
  kind.map (·, natural)

/-- The model restriction of a join form that the model does not describe, if it is one:
another join operator. -/
def joinFormIssue (item : Nat) (join : Syntax.Join) : Option ValueIssue :=
  match joinOperator join.operator with
  | none => some (.restriction [2, item, 0] .joinOperator)
  | some (.inner, _) | some (.left, _) | some (.right, _) | some (.full, _) => none

/-- Whether the join is a {lit}`RIGHT` or {lit}`FULL` join. -/
def Syntax.Join.rightOrFull (join : Syntax.Join) : Bool :=
  match joinOperator join.operator with
  | some (.right, _) | some (.full, _) => true
  | some (.inner, _) | some (.left, _) | none => false

/-- The rule by which the join changes an unqualified name of a column that it merges:
an inner or left join keeps the left result, a right join takes its own column, and a
full join coalesces them. -/
def Syntax.Join.mergeRule (join : Syntax.Join) : MergeRule :=
  match joinOperator join.operator with
  | some (.right, _) => .takeRight
  | some (.full, _) => .coalesce
  | some (.inner, _) | some (.left, _) | none => .keepLeft

/-- The joined sources of the joins in order, with their merged columns and merge rules,
and the condition of each join with its path ({name}`mergeJoin`), after the sources of
{lit}`left`; {lit}`coalesced` says whether the {lit}`FROM` has a right or full join;
{lit}`item` is the position of the first join. A join form that the model does not
describe ({name}`joinFormIssue`) is a model restriction, checked before the join's
{lit}`USING` and {lit}`NATURAL` errors. -/
def mergeJoins (coalesced : Bool) (left : Scope) (item : Nat) :
    List (Syntax.Join × Source) → Except ValueIssue (Scope × List (Option (List Nat × Syntax.Expr)))
  | [] => .ok (left, [])
  | (join, right) :: rest => do
    if let some issue := joinFormIssue item join then throw issue
    let natural := (joinOperator join.operator).any (·.2)
    let (merged, condition) ← mergeJoin left right natural coalesced join.mergeRule item join
    let (scope, conditions) ← mergeJoins coalesced (left ++ [merged]) (item + 1) rest
    .ok (scope, condition :: conditions)

/-- The kind of a resolved join, from its operator. {name}`joinFormIssue` refuses an
operator that the model does not describe before the kind is used, so its kind here is
never read. -/
def Syntax.Join.resolvedKind (join : Syntax.Join) : Resolved.JoinKind :=
  match joinOperator join.operator with
  | some (.left, _) => .left
  | some (.right, _) => .right
  | some (.full, _) => .full
  | some (.inner, _) | none => .inner

/-- Resolve the tables of {lit}`FROM`: the first table's position, the positions of the
joined tables with the condition of each join and its path, and the scope of all
sources, in order. As in SQLite, every table resolves before the forms of the joins:
more than {name}`maximumJoinTables` tables is SQLite's
{lit}`at most 64 tables in a join`, then a missing table is {lit}`no such table`; two
sources with the same folded name are a model restriction; then each join in order
({name}`mergeJoins`), whose generated conditions coalesce the left columns when any join
is a right or full join. -/
def resolveTables (catalog : Catalog) (source : Option Syntax.TableReference) (joins : List Syntax.Join) :
    Except ValueIssue (Option Nat × List (Nat × Option (List Nat × Syntax.Expr)) × Scope) := do
  let some source := source | .ok (none, [], [])
  if joins.length + 1 > maximumJoinTables then throw (.prepare .tooManyTables)
  let (first, firstSource) ← resolveTableReference catalog [1] source
  let joined ← resolveAll (fun item (join : Syntax.Join) => resolveTableReference catalog [2, item, 1] join.source) joins
  let sources := firstSource :: joined.map Prod.snd
  if let some (item, _) := findPosition (fun (item, source) => sources.take item |>.any fun earlier =>
      normalizeIdentifier earlier.name == normalizeIdentifier source.name) (sources.mapIdx fun item source => (item, source)) then
    throw (.restriction (if item == 0 then [1] else [2, item - 1, 1]) .duplicateSource)
  let (scope, conditions) ← mergeJoins (joins.any Syntax.Join.rightOrFull) [firstSource] 0 (joins.zip (joined.map Prod.snd))
  .ok (some first, (joined.map Prod.fst).zip conditions, scope)

/-- Resolve the condition of the join at {lit}`item`, written or generated, with the path
of its issues, over the whole scope, as SQLite does; then require that it reads only the
tables up to the joined one, which the model evaluates while it joins
({name}`RestrictionKind.laterTableInOn`). -/
def resolveJoinCondition (dqs : Bool) (scope : Scope) (item : Nat) :
    Option (List Nat × Syntax.Expr) → Except ValueIssue (Option Resolved.Expr)
  | none => .ok none
  | some (path, term) => do
    let resolved ← condition path (resolveOperand dqs scope true term)
    let bound := (scope.take (item + 2)).foldl (fun width source => width + source.columns.length) 0
    if resolved.readsBelow bound then .ok (some resolved)
    else throw (.restriction path .laterTableInOn)

end Belay.Sqlite
