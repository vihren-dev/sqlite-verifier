import Belay.Sqlite.Resolution.ErrorKinds
import Belay.Sqlite.Resolution.OperandIssues

set_option doc.verso true

/-! Laws of the INSERT rows whose cells may read the clock ({lit}`ClockRows.lean`): their
issues name no catalog object. -/

namespace Belay.Sqlite

/-- For every setting and expression, an issue of {name}`constantCell` names no catalog
object. Proof sketch: the issue is one of {name}`resolveOperand`, or a restriction. -/
theorem constantCell_issue (dqs : Bool) (expression : Syntax.Expr) (issue : ValueIssue)
    (failed : constantCell dqs expression = .error issue) : issue.namesNoObject := by
  unfold constantCell at failed
  cases h : resolveOperand dqs [] true expression with
  | error cause => rw [h] at failed; cases failed; exact resolveOperand_issue dqs [] true expression _ h
  | ok operand =>
    rw [h] at failed
    simp only [bind, Except.bind] at failed
    repeat' split at failed
    all_goals first | (cases failed; done) | (cases failed; trivial)

/-- For every column, an issue of {name}`omittedCell` names no catalog object. Proof sketch:
a time default gives no issue; any other issue is one of {name}`defaultValue`. -/
theorem omittedCell_issue (column : CatalogColumn) (issue : ValueIssue)
    (failed : omittedCell column = .error issue) : issue.namesNoObject := by
  unfold omittedCell at failed
  split at failed
  · cases failed
  · cases hdefault : defaultValue column with
    | error cause => rw [hdefault] at failed; cases failed; exact defaultValue_issue _ _ hdefault
    | ok _ => rw [hdefault] at failed; cases failed

/-- For all inputs, an issue of {name}`fullCells` names no catalog object. Proof sketch: by
{name}`resolveAll_issue`, the issue comes from one column, where only {name}`omittedCell`
can fail. -/
theorem fullCells_issue (columns : List CatalogColumn) (positions : List Nat) (row : List RowCell)
    (issue : ValueIssue) (failed : fullCells columns positions row = .error issue) : issue.namesNoObject := by
  unfold fullCells at failed
  refine resolveAll_issue _ _ _ (fun position column issue h => ?_) failed
  split at h
  · cases h
  · exact omittedCell_issue _ _ h

end Belay.Sqlite
