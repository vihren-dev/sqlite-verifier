import Belay.Sqlite.Model.RowEngineKeyState

set_option doc.verso true

/-! The foreign-key steps of one row keep the rows of the state ({lit}`oldSteps`,
{lit}`newSteps`): they change only the counter of violations, or stop as undescribed. So they
keep the invariant of the row engine for an atom (ADR 0022, D3, slices 2 and 3). -/

namespace Belay.Sqlite.Model

/-- For every catalog, state, position, row, links and flag: {name}`oldSteps` gives a state with
the rows of the state, or the undescribed stop. Proof sketch: each step of the two folds keeps
the rows (it sets only the counter) or throws {name}`KeyStop.undescribed`. -/
theorem oldSteps_rows (catalog : Catalog) (state : KeyState) (position : Nat) (row : Row)
    (children parents : List ForeignKeyLink) (ignore : Bool) :
    ResultHolds (fun next => next.rows = state.rows) (· = .undescribed)
      (oldSteps catalog state position row children parents ignore) := by
  unfold oldSteps
  refine ResultHolds.bind (good := fun next => next.rows = state.rows)
    (ResultHolds.foldlM (fun value link same => ?_) children state rfl) fun value same =>
      ResultHolds.foldlM (fun value link same => ?_) parents value same
  all_goals repeat' (first | split | dsimp only)
  all_goals first | exact same | rfl

/-- For every catalog, state, position, row, links, flag, old row and changed positions:
{name}`newSteps` gives a state with the rows of the state, or the undescribed stop. Proof
sketch: as {name}`oldSteps_rows`; the scan is skipped or is a second fold of the same kind. -/
theorem newSteps_rows (catalog : Catalog) (state : KeyState) (position : Nat) (row : Row)
    (children parents : List ForeignKeyLink) (scan : Bool) (stale : Option Row) (changed : List Nat) :
    ResultHolds (fun next => next.rows = state.rows) (· = .undescribed)
      (newSteps catalog state position row children parents scan stale changed) := by
  unfold newSteps
  refine ResultHolds.bind (good := fun next => next.rows = state.rows)
    (ResultHolds.foldlM (fun value link same => ?_) children state rfl) fun value same => ?_
  · repeat' (first | split | dsimp only)
    all_goals first | exact same | rfl
  · split
    · exact same
    · refine ResultHolds.foldlM (fun value link same => ?_) parents value same
      repeat' (first | split | dsimp only)
      all_goals first | exact same | rfl

end Belay.Sqlite.Model
