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

/-- Output names of ADD COLUMN's empty-table check. SQLite's
{lit}`sqlite3AlterFinishAddColumn` calls {lit}`sqlite3ErrorIfNotEmpty` for a
NOT NULL column without a non-NULL default. That helper compiles a SELECT
of this RAISE expression (pinned SQLite {lit}`alter.c`), whose name is exposed
even when the table is empty. Other modeled additions have no output columns. -/
def addColumnOutputNames (column : CatalogColumn) : List String :=
  if column.notNull && (readDefaultValue column).toOption == some .null then
    ["raise(ABORT,'Cannot add a NOT NULL column with default value NULL')"]
  else []

/-- Observe the literal-DML domain; unsupported output capability is explicit.
Transitions and failure status come from production advance, never a second
evaluator. A successful INSERT changes one row per VALUES row and a successful
UPDATE changes each row that its filter selects; their {lit}`RETURNING` rows are
{name}`returnedRows` of the inserted rows, or of the new values of the selected rows. A
successful DELETE changes each row that its filter selects, and its {lit}`RETURNING` rows
are {name}`returnedRows` of the old values of those rows. A write that fails a
constraint returns its {lit}`RETURNING` names and no rows. A query has its result column
names and the rows of {name}`Resolved.Query.run` over the table before it, and no
change count; a query whose table is missing has no output. A query that fails with
{lit}`integer overflow` has its column names and no rows when it has no
{lit}`GROUP BY`; with {lit}`GROUP BY`, SQLite may return the rows of other groups
before the failing one, in an order the model does not describe, so it has no output. -/
def statementOutput (statement : Resolved.Statement) (before : SqlState)
    (transition : SqlTransition) : Option StatementOutput :=
  let successful := match transition with | .next _ => true | _ => false
  let constraintFailure := match transition with
    | .halt (.failure _ .constraintViolation _) => true
    | .halt (.pending _ _ (some (_, .constraintViolation))) => true
    | _ => false
  let overflow := match transition with
    | .halt (.failure _ .integerOverflow _) => true
    | .halt (.pending _ _ (some (_, .integerOverflow))) => true
    | _ => false
  match statement with
  | .insert _ rows _ returning =>
    let names := returning.map (·.2)
    if successful then some ⟨names, returnedRows returning rows, some rows.length⟩
    else if constraintFailure then some ⟨names, [], some 0⟩ else none
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
    else if overflow && query.groupBy.isEmpty then some ⟨query.names, [], none⟩ else none
  | .addColumn _ column => some ⟨addColumnOutputNames column, [], none⟩
  | .createTable .. | .createIndex .. | .begin | .commit | .rollback | .prepareError _ =>
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
