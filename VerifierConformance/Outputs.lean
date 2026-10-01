import SqliteVerifier

/-! ADR 0005 output comparison uses native tie groups, without evaluating SQL. -/

namespace SqliteVerifier.Conformance

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
    group.count ≤ group.rows.length && group.count ≤ rows.length &&
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
    ordered.all (fun group => group.rows.all (fun row => row.length == expected.columns.length)) &&
    matchesGroups ordered expected.rows && matchesGroups ordered actual.rows

/-- Observe the existing literal-DML domain; unsupported output capability is explicit.
Transitions and failure status come from production advance, never a second evaluator. -/
def statementOutput (statement : Statement) (before : SqlState)
    (transition : SqlTransition) : Option StatementOutput :=
  let successful := match transition with | .next _ => true | _ => false
  let constraintFailure := match transition with
    | .halt (.failure _ .constraintViolation _) => true
    | .halt (.pending _ _ (some (_, .constraintViolation))) => true
    | _ => false
  match statement with
  | .insert .. =>
    if successful then some ⟨[], [], some 1⟩
    else if constraintFailure then some ⟨[], [], some 0⟩ else none
  | .update name _ _ key equals =>
    if successful then do
      let table ← before.database name
      return ⟨[], [], some (table.rows.filter (fun row =>
        LiteralData.matchesKey table row key equals)).length⟩
    else if constraintFailure then some ⟨[], [], some 0⟩ else none
  | _ => some ⟨[], [], none⟩

/-- Follow reached production transitions and stop at their first failure. -/
def outputTraceFrom (position : Nat) (script : List Statement) (state : SqlState) :
    List (Option StatementOutput) :=
  match script with
  | [] => []
  | statement :: rest =>
    let transition := advance position statement state
    statementOutput statement state transition ::
      match transition with
      | .next next => outputTraceFrom (position + 1) rest next
      | .halt _ => []

end SqliteVerifier.Conformance
