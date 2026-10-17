import Belay.Sqlite.QueryEval

set_option doc.verso true

/-! Where a JSON function fails (ADR 0012, amendment 5, slice 6b). SQLite evaluates an
expression lazily and folds some of it away (checked on native SQLite 3.51.0): it
short-circuits {lit}`AND`, {lit}`OR` and {lit}`COALESCE`, folds {lit}`X AND 0` to 0
without evaluating {lit}`X`, and does not evaluate a row that {lit}`WHERE`, {lit}`LIMIT`
or {lit}`OFFSET` leaves out. So the model distinguishes a call that may fail when every
part of an expression is evaluated ({lit}`mayFail`) from a call whose failure SQLite
certainly reports ({lit}`mustFail`: not under {lit}`AND`, {lit}`OR` or {lit}`COALESCE`).
A JSONB argument is a failure that the model does not describe: it may fail but is never
certain. -/

namespace Belay.Sqlite.Resolved

/-- Whether a JSON function fails with an error that the model describes: malformed JSON,
a bad path or bad {lit}`json_valid` flags, not a JSONB argument. -/
def describedFailure : Except Json.JsonError Value → Bool
  | .error .malformed | .error (.badPath _) | .error .badFlags => true
  | .error .blobArgument | .ok _ => false

/-- Whether a JSON function fails at all, also on a JSONB argument. -/
def anyFailure : Except Json.JsonError Value → Bool
  | .error _ => true
  | .ok _ => false

mutual
/-- Whether some JSON call of the expression fails over the row when every part of the
expression is evaluated. -/
def Expr.mayFail (row : List Value) : Expr → Bool
  | .column _ | .literal _ => false
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .coalesce left right =>
    left.mayFail row || right.mayFail row
  | .not operand | .isNull operand _ | .cast _ operand => operand.mayFail row
  | .json function arguments => arguments.mayFail row || anyFailure (Json.apply function (arguments.eval row))
  | .arguments arguments => arguments.mayFail row

/-- Whether some argument may fail over the row ({name}`Expr.mayFail`). -/
def Arguments.mayFail (row : List Value) : Arguments → Bool
  | .nil => false
  | .cons head tail => head.mayFail row || tail.mayFail row
end

mutual
/-- Whether SQLite certainly reports a JSON failure when it evaluates the expression over
the row: a described failure of a call that is not under {lit}`AND`, {lit}`OR` or
{lit}`COALESCE`, which SQLite may skip or fold away. -/
def Expr.mustFail (row : List Value) : Expr → Bool
  | .column _ | .literal _ | .and .. | .or .. | .coalesce .. => false
  | .compare _ left right | .arithmetic _ left right => left.mustFail row || right.mustFail row
  | .not operand | .isNull operand _ | .cast _ operand => operand.mustFail row
  | .json function arguments =>
    arguments.mustFail row || describedFailure (Json.apply function (arguments.eval row))
  | .arguments arguments => arguments.mustFail row

/-- Whether some argument certainly fails over the row ({name}`Expr.mustFail`). -/
def Arguments.mustFail (row : List Value) : Arguments → Bool
  | .nil => false
  | .cons head tail => head.mustFail row || tail.mustFail row
end

mutual
/-- Whether the expression has a JSON call, for example
{lean}`(Expr.json .extract (.cons (.column 0) .nil)).callsJson`. -/
def Expr.callsJson : Expr → Bool
  | .column _ | .literal _ => false
  | .compare _ left right | .and left right | .or left right | .arithmetic _ left right | .coalesce left right =>
    left.callsJson || right.callsJson
  | .not operand | .isNull operand _ | .cast _ operand => operand.callsJson
  | .json .. => true
  | .arguments arguments => arguments.callsJson

/-- Whether some argument has a JSON call ({name}`Expr.callsJson`). -/
def Arguments.callsJson : Arguments → Bool
  | .nil => false
  | .cons head tail => head.callsJson || tail.callsJson
end

/-- Whether some JSON call of one of the expressions may fail over one of the rows. -/
def anyMayFail (rows : List (List Value)) (expressions : List Expr) : Bool :=
  rows.any fun row => expressions.any (·.mayFail row)

/-- The scalar result columns of a query. -/
def Output.scalars : Output → List Expr
  | .scalar term => [term]
  | .aggregate _ => []

/-- The operand of an aggregate result column; none for a scalar or {lit}`COUNT(*)`. -/
def Output.operands : Output → List Expr
  | .scalar _ | .aggregate .countRows => []
  | .aggregate (.count operand) | .aggregate (.min operand) | .aggregate (.max operand)
  | .aggregate (.sum operand) | .aggregate (.avg operand) => [operand]

/-- The expressions of an {lit}`ORDER BY` key: an expression, or none for a result
column, which the result columns already cover. -/
def SortKey.expressions : SortKey → List Expr
  | .expression term => [term]
  | .output _ => []

/-- The expressions that a query evaluates over each row that passes {lit}`WHERE`: the
result columns, the aggregate operands, and the {lit}`GROUP BY` and {lit}`ORDER BY`
keys. -/
def Query.keptExpressions (query : Query) : List Expr :=
  query.columns.flatMap Output.scalars ++ query.columns.flatMap Output.operands ++ query.groupBy ++
    query.orderBy.flatMap (·.1.expressions)

/-- The expressions of a {lit}`json_each` source: its arguments and its {lit}`ON`
condition. -/
def EachSource.expressions (each : EachSource) : List Expr :=
  each.json :: each.path.toList ++ each.condition.toList

/-- Every expression of a query: {lit}`WHERE`, the {lit}`ON` conditions, the expressions of
its {lit}`json_each` sources and {name}`Query.keptExpressions`. -/
def Query.expressions (query : Query) : List Expr :=
  query.filter.toList ++ query.joins.filterMap (·.condition) ++ query.functions.flatMap EachSource.expressions ++
    query.keptExpressions

/-- Whether some JSON call of the query may fail over its source rows. The row with no
cells, {lit}`[]`, reads NULL in every column. A query with joins or {lit}`json_each`
sources and a JSON call may fail, because SQLite may evaluate a condition over a part of
a joined row. The failures of {lit}`json_each` itself are not JSON calls of an
expression; {lit}`JsonReady.lean` checks them. Otherwise:

* {lit}`WHERE` over every source row and over {lit}`[]`, because SQLite evaluates a
  constant term once before it reads the rows (checked: {lit}`DELETE FROM t WHERE
  json_extract('x', '$')` fails over an empty table);
* the result columns, aggregate operands, and {lit}`GROUP BY` and {lit}`ORDER BY` keys
  over every row that passes {lit}`WHERE`, and in an aggregate query also over {lit}`[]`,
  because SQLite evaluates the result row of an empty group over NULL cells. -/
def Query.mayFail (query : Query) (rows : List (List Value)) : Bool :=
  if !query.joins.isEmpty || !query.functions.isEmpty then query.expressions.any Expr.callsJson
  else
    let kept := filtered query rows ++ if query.aggregate then [[]] else []
    anyMayFail ([] :: rows) query.filter.toList ||
    anyMayFail kept query.keptExpressions

/-- For every row and expression without a JSON call ({name}`Expr.callsJson`), no JSON
call of it may fail over the row ({name}`Expr.mayFail`). Proof sketch: induction over
the mutual expression and argument types. -/
theorem Expr.mayFail_of_callsJson (row : List Value) (expression : Expr)
    (plain : expression.callsJson = false) : expression.mayFail row = false := by
  induction expression using Expr.rec
    (motive_2 := fun arguments => arguments.callsJson = false → arguments.mayFail row = false) <;>
    simp_all [Expr.callsJson, Expr.mayFail, Arguments.callsJson, Arguments.mayFail]

/-- For all rows and every query without a JSON call in any of its expressions
({name}`Query.expressions`), no JSON call of the query may fail over the rows
({name}`Query.mayFail`). Proof sketch: each expression that {name}`Query.mayFail`
evaluates is one of {name}`Query.expressions`, so {name}`Expr.mayFail_of_callsJson`
applies to it. -/
theorem Query.mayFail_of_callsJson (query : Query) (rows : List (List Value))
    (plain : query.expressions.all (!·.callsJson) = true) : query.mayFail rows = false := by
  simp only [List.all_eq_true, Bool.not_eq_true'] at plain
  unfold Query.mayFail anyMayFail
  split
  · simpa using plain
  · simp only [Bool.or_eq_false_iff, List.any_eq_false, Bool.not_eq_true]
    refine ⟨fun _ _ expression member => ?_, fun _ _ expression member => ?_⟩ <;>
      exact Expr.mayFail_of_callsJson _ _ (plain _ (by simp_all [Query.expressions]))

/-- Whether SQLite certainly reports a JSON failure of the query over its source rows,
which the model describes only for a query without {lit}`FROM` (no table and no
{lit}`json_each` source) and without {lit}`LIMIT 0` (checked natively): its {lit}`WHERE` fails on the one row; or the row passes
{lit}`WHERE` and an aggregate operand fails, also with {lit}`OFFSET`; or the row passes,
no {lit}`OFFSET` skips it, and a scalar result column fails. -/
def Query.mustFail (query : Query) (rows : List (List Value)) : Bool :=
  query.table.isNone && query.functions.isEmpty && query.limit != some 0 && rows.any fun row =>
    query.filter.any (·.mustFail row) ||
    (query.filter.all (fun condition => truthy (condition.eval row)) &&
      ((query.columns.flatMap Output.operands).any (·.mustFail row) ||
        (query.offset == 0 && (query.columns.flatMap Output.scalars).any (·.mustFail row))))

end Belay.Sqlite.Resolved
