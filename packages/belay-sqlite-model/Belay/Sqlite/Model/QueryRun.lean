import Belay.Sqlite.Model.QueryResults
import Belay.Sqlite.Model.QueryWindow
import Belay.Sqlite.Model.CompoundRun
import Belay.Sqlite.Model.Resolution.ExprAny

set_option doc.verso true

/-! A query over its source rows: its result rows, whether SQLite stops it with
{lit}`integer overflow`, and whether a JSON function of it fails (ADR 0013, D2). SQLite
does not evaluate a row that {lit}`WHERE`, {lit}`LIMIT` or {lit}`OFFSET` leaves out, and
evaluates a constant {lit}`WHERE` term once before it reads the rows; the fault of a query
follows these rules from the faults of its expressions ({lit}`Expr.evaluate`). -/

namespace Belay.Sqlite.Model.Resolved

/-- Whether some JSON call of one of the expressions may fail over one of the rows. -/
def anyMayFail (context : EvalContext) (rows : List (List Value)) (expressions : List Expr) : Bool :=
  rows.any fun row => expressions.any (·.mayFailOn context row)

/-- The scalar result columns of a query. -/
def Output.scalars : Output → List Expr
  | .scalar term => [term]
  | .aggregate _ => []

/-- The expressions that an aggregate result column evaluates over each row; none for a
scalar or {lit}`COUNT(*)`. A value of {lit}`json_group_array` or {lit}`json_group_object` is
written as {lit}`json_array` writes it, so it is the call {lit}`json_array(value)`, whose fault
is that of writing the value (a BLOB is JSONB, which the model does not describe). -/
def Output.operands : Output → List Expr
  | .scalar _ | .aggregate .countRows => []
  | .aggregate (.count operand) | .aggregate (.min operand _) | .aggregate (.max operand _)
  | .aggregate (.sum operand) | .aggregate (.avg operand) => [operand]
  | .aggregate (.jsonGroupArray operand _) => [.json .array (.cons operand .nil)]
  | .aggregate (.jsonGroupObject label value _) => [label, .json .array (.cons value .nil)]
  | .aggregate (.groupConcat operand separator) => operand :: separator.toList
  | .aggregate (.total operand) => [operand]

/-- The expressions of an {lit}`ORDER BY` key: an expression, or none for a result
column, which the result columns already cover. -/
def SortKey.expressions : SortKey → List Expr
  | .expression term => [term]
  | .output _ => []

/-- The expressions that a query evaluates over each row that passes {lit}`WHERE`: the
result columns, the aggregate operands, also of the aggregates that its expressions name, the
{lit}`GROUP BY` and {lit}`ORDER BY` keys, and {lit}`HAVING`. -/
def Query.keptExpressions (query : Query) : List Expr :=
  query.columns.flatMap Output.scalars ++ query.columns.flatMap Output.operands ++
    query.aggregates.flatMap (Output.aggregate · |>.operands) ++ query.groupBy.map Prod.fst ++
    query.orderBy.flatMap (·.key.expressions) ++ query.having.toList

/-- The expressions of a source of {lit}`FROM`: the arguments of a {lit}`json_each` source,
and the {lit}`ON` condition. -/
def QuerySource.expressions (join : QuerySource) : List Expr :=
  (match join.source with
    | .each json path => json :: path.toList
    | .table _ | .subquery .. | .pragma _ => []) ++ join.condition.toList

/-- Whether the query joins sources: it has more than one, or a {lit}`json_each` source. -/
def Query.joined (query : Query) : Bool :=
  query.sources.length > 1 || query.sources.any (·.source.isEach)

/-- Every expression of a query: {lit}`WHERE`, the expressions of its sources
({name}`QuerySource.expressions`) and {name}`Query.keptExpressions`. -/
def Query.expressions (query : Query) : List Expr :=
  query.filter.toList ++ query.sources.flatMap QuerySource.expressions ++ query.keptExpressions

/-- Whether some fallible call of the query ({name}`Expr.isFallibleCall`: a JSON call or a
function that can fail) may fail over its source rows. The row with no cells, {lit}`[]`,
reads NULL in every column. A query that joins sources ({name}`Query.joined`) and has a
fallible call may fail, because SQLite may evaluate a condition over a part of
a joined row. The failures of {lit}`json_each` itself are not JSON calls of an
expression; {lit}`Query.source` gives their fault. Otherwise, and also for a joined query,
whose subqueries can give a value that the model does not describe:
* {lit}`WHERE` over every source row and over {lit}`[]`, because SQLite evaluates a
  constant term once before it reads the rows (checked: {lit}`DELETE FROM t WHERE
  json_extract('x', '$')` fails over an empty table);
* the result columns, aggregate operands, and {lit}`GROUP BY` and {lit}`ORDER BY` keys
  over every row that passes {lit}`WHERE`, and in an aggregate query also over {lit}`[]`,
  because SQLite evaluates the result row of an empty group over NULL cells. -/
def Query.mayFail (context : EvalContext) (query : Query) (rows : List (List Value)) : Bool :=
  (query.joined && query.expressions.any (·.any Expr.isFallibleCall)) ||
    let kept := filtered context query rows ++ if query.aggregate then [[]] else []
    anyMayFail context ([] :: rows) query.filter.toList ||
    anyMayFail context kept query.keptExpressions

/-- Whether SQLite certainly reports a JSON failure of the query over its source rows,
which the model describes only for a query without {lit}`FROM` (no source) and without {lit}`LIMIT 0` (checked natively): its {lit}`WHERE`
fails on the one row; or the row passes {lit}`WHERE` and an aggregate operand fails, also
with {lit}`OFFSET`; or the row passes, no {lit}`OFFSET` skips it, and a scalar result column
fails. -/
def Query.mustFail (context : EvalContext) (query : Query) (rows : List (List Value)) : Bool :=
  query.sources.isEmpty && query.limit != some 0 && rows.any fun row =>
    query.filter.any (·.mustFailOn context row) ||
    (query.filter.all (fun condition => truthy (condition.eval context row)) &&
      ((query.columns.flatMap Output.operands).any (·.mustFailOn context row) ||
        (query.offset == 0 && (query.columns.flatMap Output.scalars).any (·.mustFailOn context row))))

/-- Whether a query fails over its source rows, so that SQLite stops the statement with the
{lit}`integer overflow` error: an aggregate query without {lit}`LIMIT 0` in which an
aggregate of a result column, or one that its expressions name, fails ({name}`Aggregate.fails`)
for some group. With
{lit}`LIMIT 0`, SQLite skips the evaluation and returns no rows. -/
def Query.fails (context : EvalContext) (query : Query) (rows : List (List Value)) : Bool :=
  query.aggregate && query.limit != some 0 && (queryGroups context query (filtered context query rows)).any fun group =>
    query.aggregates.any (·.fails context group) || query.columns.any fun
      | .aggregate aggregate => aggregate.fails context group
      | .scalar _ => false

/-- A query run over its source rows: the result rows, the fault of its JSON calls, whether an
aggregate overflows, and whether a value of its window is not an integer. -/
structure QueryRun where
  /-- The result rows ({name}`Query.results`). -/
  rows : List (List Value)
  /-- {lean}`Fault.must` when SQLite certainly reports a JSON failure ({name}`Query.mustFail`),
  else {lean}`Fault.may` when a JSON call may fail ({name}`Query.mayFail`) or when
  {lit}`SELECT DISTINCT` keeps rows that SQLite's plan chooses ({name}`Query.distinctCertain`),
  else {lean}`Fault.none`. -/
  fault : Fault
  /-- Whether SQLite stops the query with {lit}`integer overflow` ({name}`Query.fails`). -/
  overflow : Bool
  /-- Whether SQLite stops the query with {lit}`datatype mismatch` before it reads a row, because
  a value bound to {lit}`LIMIT ?` or {lit}`OFFSET ?` is not an integer ({name}`Query.bindWindow`). -/
  mismatch : Bool

/-- The run of a compound query for an outer row: the rows of the bound query
({name}`Query.results`), none for a window value that is not an integer, and the end of the
compound ({name}`Compound.ending`) as the fault, the overflow and the mismatch of the run. A run
that ends without a failure has the fault {lean}`Fault.may` when an operator keeps rows that
SQLite's plan chooses ({name}`Compound.combined`). -/
def Query.compoundRun (context : EvalContext) (query : Query) (compound : Compound) (rows : List (List Value)) :
    QueryRun :=
  let outer := rows.headD []
  let ending := compound.ending context query outer
  { rows := ((query.bindWindow context.parameters).map (·.results context rows)).getD [],
    fault := match ending with
      | .done => if (compound.combined context outer).2 then .none else .may
      | .may => .may
      | .function => .must
      | .overflow _ | .mismatch => .none,
    overflow := match ending with
      | .overflow _ => true
      | .done | .may | .function | .mismatch => false,
    mismatch := ending == .mismatch }

/-- Run the query over its source rows ({lit}`Query.source`) with its window bound to the values
of the context ({name}`Query.bindWindow`): the result rows, the fault (also {lean}`Fault.may` for
an uncertain {lit}`SELECT DISTINCT`) and the overflow of the bound query. When a bound value is
not an integer, the run has no rows, no fault and no overflow, and it is a mismatch. A compound
query runs as {name}`Query.compoundRun`. -/
def Query.run (context : EvalContext) (query : Query) (rows : List (List Value)) : QueryRun :=
  match query.compound with
  | some compound => query.compoundRun context compound rows
  | none => match query.bindWindow context.parameters with
    | none => { rows := [], fault := .none, overflow := false, mismatch := true }
    | some bound =>
      { rows := bound.results context rows,
        fault := if bound.mustFail context rows then .must
          else if bound.mayFail context rows || !bound.distinctCertain context rows then .may else .none,
        overflow := bound.fails context rows, mismatch := false }

end Belay.Sqlite.Model.Resolved
