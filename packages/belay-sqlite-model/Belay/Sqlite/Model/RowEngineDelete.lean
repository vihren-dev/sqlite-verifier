import Belay.Sqlite.Model.RowEngineKeySteps
import Belay.Sqlite.Model.RowEngineTriggers
import Belay.Sqlite.Model.ForeignKeyRows

set_option doc.verso true

/-! The deletion of a row and the foreign-key actions keep the invariant of the row engine for
an atom (ADR 0022, D3, slices 2 and 3): a delete stores a sublist of the rows, and an action is a
nested write. -/

namespace Belay.Sqlite.Model

variable {invariant : Database → Prop}

/-- For every invariant, catalog, run of the nested writes, link, action, position, old row, new row and
state: if the run keeps the invariant of the row engine from each state that satisfies
{name}`KeyState.Holds`, and the state satisfies it, the result of {name}`runAction` keeps
the invariant (a success satisfies {name}`KeyState.Holds` and a stop
{name}`KeyStop.Holds`). Proof sketch: each branch keeps the state, fails without a state, or
is the nested run with the changed tables noted. -/
theorem runAction_holds {catalog : Catalog} {run : RowWork → KeyState → Except KeyStop KeyState}
    (keeps : ∀ work state, state.Holds invariant catalog →
      ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog) (run work state))
    (link : ForeignKeyLink) (action : Syntax.ForeignKeyAction) (position : Nat) (old : Row) (new : Option Row)
    {state : KeyState} (holds : state.Holds invariant catalog) :
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
      (runAction catalog run link action position old new state) := by
  unfold runAction
  repeat' (first | split | dsimp only)
  all_goals first | exact holds | trivial | exact ResultHolds.map (keeps _ _ holds) fun _ reached => reached

/-- For every invariant with {name}`WriteLaws`, catalog, links, nested run, frame, position, flags, state and rowid: if the nested
run keeps the invariant ({name}`NestedRun.Keeps`) and the state satisfies
{name}`KeyState.Holds`, the result of {name}`deleteRow` keeps the invariant. Proof sketch:
the programs before and after the delete keep it ({name}`runPrograms_holds`), the foreign-key
steps keep the rows ({name}`oldSteps_rows`), the delete stores a sublist of the rows
({name}`KeyState.holds_changeRows_sublist`), and each action keeps it
({name}`runAction_holds`). -/
theorem deleteRow_holds (laws : WriteLaws invariant) {catalog : Catalog} {links : List ForeignKeyLink} {nested : NestedRun}
    (keeps : nested.Keeps invariant catalog) (frame : RowFrame) (position : Nat) (record ignore fire : Bool)
    {state : KeyState} (holds : state.Holds invariant catalog) (rowid : Int) :
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog)
      (deleteRow catalog links nested frame position record ignore fire state rowid) := by
  unfold deleteRow
  split
  · dsimp only
    split <;> refine ResultHolds.bind (good := fun reached : KeyState × Bool => reached.1.Holds invariant catalog) ?_
      fun reached good => ?_
    all_goals first | exact runPrograms_holds keeps _ _ _ _ _ holds | exact holds | skip
    all_goals
      obtain ⟨reachedState, ended⟩ := reached
      dsimp only
      split
      · exact good
      · split
        · refine ResultHolds.bind ((oldSteps_rows _ _ _ _ _ _ _).holds_of_rows good) fun checked same => ?_
          have removed := KeyState.holds_changeRows_sublist laws same (position := position)
            (change := fun rows => rows.filter (·.rowid != rowid)) fun rows => List.filter_sublist
          refine ResultHolds.bind (ResultHolds.foldlM (fun acted link good =>
            runAction_holds (keeps frame.action) link _ position _ none good) _ _ removed) fun acted good => ?_
          first
            | exact good
            | exact ResultHolds.bind (runPrograms_holds keeps _ _ _ _ _ good) fun _ reached => reached
        · exact good
  · exact holds
