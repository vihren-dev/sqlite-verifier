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

end SqliteVerifier.Conformance
