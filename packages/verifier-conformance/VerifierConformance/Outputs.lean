import Belay.Sqlite.SqlExecution
import Belay.Sqlite.QueryJoins

/-! ADR 0005 output comparison uses native tie groups, without evaluating SQL. -/

namespace Belay.Sqlite.Conformance

/-- Returned cells retain storage classes and exact payloads. -/
abbrev ResultRow := List Value

/-- Shape survives empty results; changes is present only for direct DML. -/
structure StatementOutput where
  columns : List String
  rows : List ResultRow
  changes : Option Nat
  deriving Repr, DecidableEq

/-- A native tie group includes all eligible rows and the requested window count. -/
structure OutputGroup where
  rows : List ResultRow
  count : Nat
  deriving Repr, DecidableEq

/-- Ordered expectations carry full eligible groups, including cut boundaries. -/
structure NativeOutput where
  result : StatementOutput
  groups : Option (List OutputGroup) := none
  deriving Repr, DecidableEq

/-- Consume each eligible occurrence once, including duplicate rows.
ponytail: quadratic within a bounded case; use counted maps if measured costly. -/
def submultiset : List ResultRow → List ResultRow → Bool
  | [], _ => true
  | row :: rest, available =>
    if available.contains row then submultiset rest (available.erase row) else false

/-- Groups have fixed order, while each group's selected rows may be permuted. -/
def matchesGroups : List OutputGroup → List ResultRow → Bool
  | [], rows => rows.isEmpty
  | group :: groups, rows =>
    0 < group.count && group.count ≤ group.rows.length && group.count ≤ rows.length &&
    submultiset (rows.take group.count) group.rows &&
    matchesGroups groups (rows.drop group.count)

/-- Reject ragged rows even when both sides carry the same malformed shape. -/
def StatementOutput.valid (output : StatementOutput) : Bool :=
  output.rows.all (fun row => row.length == output.columns.length)

/-- No ordering means bag equality (also RETURNING); groups describe ordered windows.
Validate native evidence itself before using it as the comparison authority. -/
def matchesOutput (expected actual : StatementOutput)
    (groups : Option (List OutputGroup)) : Bool :=
  expected.valid && actual.valid && expected.columns == actual.columns &&
  expected.changes == actual.changes &&
  match groups with
  | none => expected.rows.length == actual.rows.length && submultiset actual.rows expected.rows
  | some ordered =>
    ((ordered.drop 1).dropLast.all (fun group => group.count == group.rows.length)) &&
    ordered.all (fun group => group.rows.all (fun row => row.length == expected.columns.length)) &&
    matchesGroups ordered expected.rows && matchesGroups ordered actual.rows

/-- The {lit}`RETURNING` rows of a write: each {lit}`RETURNING` expression evaluated over
each written row, in order. A write without {lit}`RETURNING` returns no rows. -/
def returnedRows (returning : List (Resolved.Expr × String)) (written : List (List Value)) : List ResultRow :=
  if returning.isEmpty then [] else written.map fun row => returning.map fun (expression, _) => expression.eval row

/-- The error with which a transition stops: the reason of a failure, or the error of a
pending transaction; none for a transition that continues or succeeds. -/
def haltError : SqlTransition → Option ExecutionError
  | .next _ | .halt (.success _) => none
  | .halt (.failure _ reason _) => some reason
  | .halt (.pending _ _ error) => error.map (·.2)

/-- Whether an execution error is a failed write, whose outputs are the {lit}`RETURNING`
names, no rows and no change: a constraint failure or a rowid alias mismatch. -/
def ExecutionError.failsWrite : ExecutionError → Bool
  | .constraintViolation | .constraintFail | .constraintRollback | .datatypeMismatch => true
  | .unmodeled | .prepare _ | .transactionAlreadyActive | .noActiveTransaction | .integerOverflow
  | .functionError => false

/-- The change count of a failed INSERT with clauses or algorithms: the rows written
before the failing row for a FAIL failure, which keeps them, and zero for every other
failure or a success. -/
def keptCount : Except (ExecutionError × Table × List Row) (Table × List Row) → Nat
  | .error (reason, _, written) => if reason = .constraintFail then written.length else 0
  | .ok _ => 0

/-- Observe the literal-DML domain; unsupported output capability is explicit.
Transitions and failure status come from production advance, never a second
evaluator. A successful INSERT changes one row per VALUES row and a successful
UPDATE changes each row that its filter selects; their {lit}`RETURNING` rows are
{name}`returnedRows` of the cells of the inserted rows (with the rowid of a NULL rowid
alias), or of the new values of the selected rows. A successful INSERT with
{lit}`ON CONFLICT` clauses changes each row that it inserted or updated, and its
{lit}`RETURNING` rows are {name}`returnedRows` of those rows in row order
({name}`LiteralData.upsertRun`); skipped and deleted rows are not counted, and a FAIL
failure counts the rows before the failing one ({name}`keptCount`). A
successful DELETE changes each row that its filter selects, and its {lit}`RETURNING` rows
are {name}`returnedRows` of the old values of those rows. A write that fails a
constraint or a rowid alias ({lit}`datatype mismatch`) returns its {lit}`RETURNING` names
and no rows. A query has its result column
names and the rows of {name}`Resolved.Query.run` over the table before it, and no
change count; a query whose table is missing has no output. A query that fails with
{lit}`integer overflow` has its column names and no rows when it has no
{lit}`GROUP BY`; with {lit}`GROUP BY`, SQLite may return the rows of other groups
before the failing one, in an order the model does not describe, so it has no output. A
query whose JSON function fails, which has no {lit}`FROM` and so at most one row, has its
column names and no rows. -/
def statementOutput (statement : Resolved.Statement) (before : SqlState)
    (transition : SqlTransition) : Option StatementOutput :=
  let successful := match transition with | .next _ => true | .halt _ => false
  let constraintFailure := (haltError transition).any ExecutionError.failsWrite
  let overflow := haltError transition == some .integerOverflow
  let functionFailure := haltError transition == some .functionError
  match statement with
  | .insert at_ rows _ returning =>
    let names := returning.map (·.2)
    if successful then do
      let table ← before.database at_
      let written := ((LiteralData.inserted table rows).rows.drop table.rows.length).map (·.values)
      return ⟨names, returnedRows returning written, some rows.length⟩
    else if constraintFailure then some ⟨names, [], some 0⟩ else none
  | .upsert at_ rows clauses keys returning policy =>
    let names := returning.map (·.2)
    let run := (before.database at_).map fun table => LiteralData.upsertRun keys policy clauses table rows
    if successful then do
      let (_, written) ← (← run).toOption
      return ⟨names, returnedRows returning (written.map (·.values)), some written.length⟩
    else if constraintFailure then some ⟨names, [], some ((run.map keptCount).getD 0)⟩ else none
  | .update at_ assignments filter _ returning =>
    let names := returning.map (·.2)
    if successful then do
      let table ← before.database at_
      let chosen := table.rows.filter (LiteralData.selected filter)
      let written := chosen.map fun row => (LiteralData.assign table.shape.columns assignments row).values
      return ⟨names, returnedRows returning written,
        some chosen.length⟩
    else if constraintFailure then some ⟨names, [], some 0⟩ else none
  | .delete at_ filter returning =>
    let names := returning.map (·.2)
    if successful then do
      let table ← before.database at_
      let chosen := table.rows.filter (LiteralData.selected filter)
      return ⟨names, returnedRows returning (chosen.map (·.values)), some chosen.length⟩
    else none
  | .query query =>
    if successful then (query.source before.database).map fun rows => ⟨query.names, query.run rows, none⟩
    else if (overflow && query.groupBy.isEmpty) || functionFailure then some ⟨query.names, [], none⟩
    else none
  | .createTable .. | .createIndex .. | .addColumn .. | .begin | .commit | .rollback | .prepareError _ =>
    some ⟨[], [], none⟩

/-- Follow reached production transitions and stop at their first failure. -/
def outputTraceFrom (position : Nat) (script : List Resolved.Statement) (state : SqlState) :
    List (Option StatementOutput) :=
  match script with
  | [] => []
  | statement :: rest =>
    let transition := advance position statement state
    statementOutput statement state transition ::
      match transition with
      | .next next => outputTraceFrom (position + 1) rest next
      | .halt _ => []

end Belay.Sqlite.Conformance
