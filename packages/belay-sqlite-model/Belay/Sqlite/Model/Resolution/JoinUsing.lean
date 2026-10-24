import Belay.Sqlite.Model.Resolution.MergedLeft

set_option doc.verso true

/-! {lit}`USING` and {lit}`NATURAL` joins (ADR 0012, amendment 2, owner decision 1, and
amendment 3; slices 4b and 4d). Each is its join with a generated {lit}`ON` condition: for
each merged name {lit}`c`, {lit}`left.c = right.c`, where {lit}`left.c` is the left side
of {lit}`MergedLeft.lean`. The right column of each pair is merged
({name}`Belay.Sqlite.Model.ScopeSource.merged`), and the join's kind gives the
{name}`Belay.Sqlite.Model.MergeRule` of unqualified names. The condition is resolved from the
positions of the merged columns, with the comparison affinity that the same written
{lit}`ON` condition would have. -/

namespace Belay.Sqlite.Model

/-- A name of {lit}`USING`, as written, when it names a column of the joined source and of
the left input; else SQLite's {name}`ExprError.joinUsingColumn`. With
{lit}`coalesced` (a right or full join in the {lit}`FROM`), the name must then pass
{name}`usingReferenceChecked`. -/
def usingNameChecked (coalesced : Bool) (left : Scope) (right : ScopeSource) (name : Identifier) :
    Except ValueIssue Identifier :=
  if (columnPosition right.columns name).isSome && left.hasColumn name then
    if coalesced then usingReferenceChecked left name else .ok name
  else .error (.prepare (.joinUsingColumn name))

/-- The names that a join merges, as written: for {lit}`NATURAL`, every column of the
joined source whose name also names a column of the left input, in the joined table's
order; for {lit}`USING`, its names, each of which must name a column of both
({name}`ExprError.joinUsingColumn` otherwise). With {lit}`coalesced`, each name must
also pass {name}`usingReferenceChecked`, in order. None for a join with neither, and
SQLite's {name}`ExprError.naturalJoinCondition` for {lit}`NATURAL` with {lit}`ON` or
{lit}`USING`. -/
def mergedNames (coalesced : Bool) (left : Scope) (right : ScopeSource) (natural : Bool) (join : Syntax.Join) :
    Except ValueIssue (Option (List Identifier)) :=
  if natural then
    if join.condition.isSome || join.usingColumns.isSome then .error (.prepare .naturalJoinCondition)
    else
      let names := right.columns.filterMap fun column => if left.hasColumn column.name then some column.name else none
      if coalesced then (names.mapM (usingReferenceChecked left)).map some else .ok (some names)
  else match join.usingColumns with
    | none => .ok none
    | some names => (names.mapM (usingNameChecked coalesced left right)).map some

/-- The condition of a join before the written {lit}`ON` condition resolves: none, the
written condition with the path of its issues, or the condition of the merged names of
{lit}`USING` or {lit}`NATURAL`, which is resolved already. -/
inductive JoinCondition where
  /-- No condition: a cross join. -/
  | none
  /-- The written {lit}`ON` condition, with the path of its issues. -/
  | written (path : List Nat) (term : Syntax.Expr)
  /-- The resolved condition of the merged names ({lit}`mergedCondition`). -/
  | merged (condition : Resolved.Expr)

/-- The written {lit}`ON` condition of the join at {lit}`item`, at child 2. -/
def JoinCondition.ofWritten (item : Nat) : Option Syntax.Expr → JoinCondition
  | Option.none => .none
  | some term => .written [2, item, 2] term

/-- The condition of the merged names, or none for no name. -/
def JoinCondition.ofMerged : Option Resolved.Expr → JoinCondition
  | Option.none => .none
  | some condition => .merged condition

/-- The condition of the merged names, resolved: the conjunction, in order, of
{lit}`left = right.c` for each name {lit}`c`, with the left side of {name}`mergedLeft` and
the column of the joined source at its offset ({name}`ScopeSource.offset`), compared with their affinity
({name}`comparisonAffinity`) and the collation of the left side
({name}`Scope.namedCollation`); none for no name, which is a cross join. It is the condition
that SQLite generates, so it has the comparison rules of a written {lit}`ON` condition. -/
def mergedCondition (coalesced : Bool) (left : Scope) (right : ScopeSource) (names : List Identifier) :
    Option Resolved.Expr :=
  let equalities := names.filterMap fun name => do
    let (leftSide, affinity) ← mergedLeft coalesced left name
    let index ← columnPosition right.columns name
    some (Resolved.Expr.compare .eq (comparisonAffinity affinity (right.columnAffinity index)) leftSide
      (.column (right.offset + index)) (left.namedCollation name))
  match equalities with
  | [] => none
  | first :: rest => some (rest.foldl .and first)

/-- The joined source with its merged columns and the merge rule of its join, which also
tells later expansions of {lit}`*` whether a right or full join follows, and the
join's condition: the written {lit}`ON` condition at child 2, or the condition of the merged
names ({name}`mergedCondition`) for {lit}`USING` and {lit}`NATURAL`. A merged name of an
argument column of a table-valued pragma on the left ({name}`Scope.argumentCell`) is the
restriction {name}`RestrictionKind.tableFunction`, as a name of it in an expression is. The left
input is every earlier source; {lit}`coalesced` says whether the {lit}`FROM` has a right or full
join; {lit}`item` is the join's position. -/
def mergeJoin (left : Scope) (right : ScopeSource) (natural coalesced : Bool) (rule : MergeRule) (item : Nat)
    (join : Syntax.Join) : Except ValueIssue (ScopeSource × JoinCondition) := do
  match ← mergedNames coalesced left right natural join with
  | none => .ok ({ right with mergeRule := rule }, .ofWritten item join.condition)
  | some names =>
    if names.any fun name => (left.namedPositions name).any left.argumentCell then
      .error (.restriction [2, item] .tableFunction) else
    let merged := names.filterMap (columnPosition right.columns ·)
    .ok ({ right with merged, mergeRule := rule }, .ofMerged (mergedCondition coalesced left right names))

/-- For every left scope, joined source, flag, rule, item and join that has neither
{lit}`NATURAL` nor {lit}`USING`, {name}`mergeJoin` merges no column, records the rule, and
gives the written {lit}`ON` condition, if any, at child 2: such a join resolves as in
slice 4. -/
theorem mergeJoin_written (left : Scope) (right : ScopeSource) (coalesced : Bool) (rule : MergeRule) (item : Nat)
    (join : Syntax.Join) (noUsing : join.usingColumns = none) :
    mergeJoin left right false coalesced rule item join =
      .ok ({ right with mergeRule := rule }, .ofWritten item join.condition) := by
  simp [mergeJoin, mergedNames, noUsing, bind, Except.bind]

/-- For every left scope, joined source and list of names that each name a column of
the joined source and of the left input, {name}`usingNameChecked` without
{lit}`coalesced` accepts them all, in order. Proof sketch: induction on the names; the
assumption for the first name makes its check succeed, and the assumption for the other
names gives the induction hypothesis. -/
theorem usingNames_checked (left : Scope) (right : ScopeSource) (names : List Identifier)
    (both : ∀ name ∈ names, (columnPosition right.columns name).isSome ∧ left.hasColumn name) :
    names.mapM (usingNameChecked false left right) = .ok names := by
  induction names with
  | nil => rfl
  | cons name rest ih =>
    have head := both name (by simp)
    have tail := ih (fun other member => both other (by simp [member]))
    rw [List.mapM_cons, tail]
    simp [usingNameChecked, head.1, head.2, bind, Except.bind, pure, Except.pure]

/-- For every left scope, joined source, rule, item and join with {lit}`USING` names that
each name a column of the joined source and of the left input, in a {lit}`FROM` without
right and full joins, when no cell of the left input is an argument column of a table-valued
pragma ({name}`Scope.argumentCell`), {name}`mergeJoin` merges the joined columns of those names under
the rule and gives the conjunction of their equalities with the left-most left columns
({name}`mergedCondition`), as in slice 4b. -/
theorem mergeJoin_using (left : Scope) (right : ScopeSource) (rule : MergeRule) (item : Nat) (join : Syntax.Join)
    (names : List Identifier) (written : join.usingColumns = some names)
    (both : ∀ name ∈ names, (columnPosition right.columns name).isSome ∧ left.hasColumn name)
    (plain : ∀ position, left.argumentCell position = false) :
    mergeJoin left right false false rule item join =
      .ok ({ right with merged := names.filterMap (columnPosition right.columns ·), mergeRule := rule },
        .ofMerged (mergedCondition false left right names)) := by
  unfold mergeJoin mergedNames
  simp only [Bool.false_eq_true, ite_false, written]
  rw [usingNames_checked left right names both, show left.argumentCell = fun _ => false from funext plain]
  simp [Except.map, bind, Except.bind]

/-- For every left scope, joined source, rule, item and {lit}`NATURAL` join without
{lit}`ON` and {lit}`USING`, in a {lit}`FROM` without right and full joins, when no cell of
the left input is an argument column of a table-valued pragma ({name}`Scope.argumentCell`),
{name}`mergeJoin` merges the columns of the joined source whose names the left input also has, under the
rule, and gives the conjunction of their equalities with the left-most left columns
({name}`mergedCondition`), as in slice 4b; with no common name, there is no condition, a
cross join. -/
theorem mergeJoin_natural (left : Scope) (right : ScopeSource) (rule : MergeRule) (item : Nat) (join : Syntax.Join)
    (noOn : join.condition = none) (noUsing : join.usingColumns = none)
    (plain : ∀ position, left.argumentCell position = false) :
    let names := right.columns.filterMap fun column => if left.hasColumn column.name then some column.name else none
    mergeJoin left right true false rule item join =
      .ok ({ right with merged := names.filterMap (columnPosition right.columns ·), mergeRule := rule },
        .ofMerged (mergedCondition false left right names)) := by
  simp only [mergeJoin, mergedNames, noOn, noUsing, show left.argumentCell = fun _ => false from funext plain]
  simp [bind, Except.bind]
  intro column _
  split <;> simp_all [List.any_eq_false]

end Belay.Sqlite.Model
