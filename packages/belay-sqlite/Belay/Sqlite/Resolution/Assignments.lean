import Belay.Sqlite.Resolution.Returning

set_option doc.verso true

/-! The {lit}`SET` assignments of UPDATE and of {lit}`ON CONFLICT DO UPDATE`: each value
is an expression over the sources in scope, resolved as in {lit}`SELECT`, and a value
that names no column folds to the literal of its stored value. -/

namespace Belay.Sqlite

/-- Resolve the items in order from a starting position, and stop at the first issue. -/
def resolveAllFrom (resolveOne : Nat → α → Except ValueIssue β) (start : Nat) :
    List α → Except ValueIssue (List β)
  | [] => .ok []
  | item :: rest => do
    let value ← resolveOne start item
    let values ← resolveAllFrom resolveOne (start + 1) rest
    return value :: values

/-- Resolve a list in order from position zero, and stop at the first issue. -/
def resolveAll (resolveOne : Nat → α → Except ValueIssue β) (items : List α) : Except ValueIssue (List β) :=
  resolveAllFrom resolveOne 0 items

/-- The resolved value of one {lit}`SET` assignment for the column at
{lit}`position`: the literal of its stored value ({name}`storeValue`) when the
expression names no column, otherwise the expression, which the execution evaluates on
the old row and stores. -/
def assignedExpression (scope : Scope) (position : Nat) (expression : Syntax.Expr)
    (resolved : Resolved.Expr) : Resolved.Expr :=
  if mentionsColumn scope expression then resolved
  else .literal (storeValue (columnAffinity scope.columns position) (resolved.eval []))

/-- Resolve one {lit}`SET` assignment at item {lit}`item`, in SQLite's order
({lit}`sqlite3Update`): the expression first, then the column name. The column name
must name a column of the table ({lit}`no such column: %s`). A value that reads the
row for a column of a unique key ({lit}`keyColumns`) is a model restriction, and so is a
value that names no column and whose JSON function may fail. Paths are
relative to the assignment list. -/
def resolveAssignment (dqs : Bool) (scope : Scope) (keyColumns : List Nat) (item : Nat) :
    String × Syntax.Expr → Except ValueIssue (Nat × Resolved.Expr)
  | (name, value) =>
    (resolveOperand dqs scope true value).mapError (·.under [item, 1]) >>= fun operand =>
    (match columnPosition scope.columns name with
      | some position => .ok position
      | none => .error (.prepare (.noSuchColumn name))) >>= fun position =>
    if mentionsColumn scope value && keyColumns.contains position then
      .error (.restriction [item, 1] .rowDependentKey)
    else if !mentionsColumn scope value && operand.1.mayFail [] then
      .error (.restriction [item, 1] .constantFunctionError)
    else .ok (position, assignedExpression scope position value operand.1)

end Belay.Sqlite
