import Belay.Sqlite.Model.RowEngineKeyState
import Belay.Sqlite.Model.TriggerRun

set_option doc.verso true

/-! The trigger programs of a row keep the invariant of the row engine for an atom (ADR 0022, D3,
slices 2 and 3), when their nested writes keep it: a step of a program writes only through the
nested run, a SELECT and a {lit}`RAISE` keep the rows, and a FAIL or ROLLBACK {lit}`RAISE` stops
with the state. -/

namespace Belay.Sqlite.Model

/-- For the given invariant, catalog and nested run of the row engine: from every frame, work and state
that satisfies {name}`KeyState.Holds`, the nested run holds the invariant: a success
satisfies {name}`KeyState.Holds` and a stop {name}`KeyStop.Holds`. -/
def NestedRun.Keeps (invariant : Database → Prop) (catalog : Catalog) (nested : NestedRun) : Prop :=
  ∀ frame work state, state.Holds invariant catalog →
    ResultHolds (KeyState.Holds invariant catalog) (KeyStop.Holds invariant catalog) (nested frame work state)

/-- For the given invariant, catalog and result of a step of a program: a success has a state that
satisfies {name}`KeyState.Holds`, whether or not the step ended the row, and a stop
satisfies {name}`KeyStop.Holds`. -/
def ProgramResult.Holds (invariant : Database → Prop) (catalog : Catalog) (result : Except KeyStop (KeyState × Bool)) : Prop :=
  ResultHolds (fun reached : KeyState × Bool => reached.1.Holds invariant catalog) (KeyStop.Holds invariant catalog) result

/-- For every invariant, catalog, state and kind of {lit}`RAISE`: if the state satisfies
{name}`KeyState.Holds`, the result of {name}`raiseEffect` satisfies
{name}`ProgramResult.Holds`. Proof sketch: IGNORE keeps the state, ABORT keeps no state,
and FAIL and ROLLBACK stop with the state. -/
theorem raiseEffect_holds {invariant} {catalog : Catalog} {state : KeyState} (holds : state.Holds invariant catalog)
    (kind : Syntax.RaiseKind) : ProgramResult.Holds invariant catalog (raiseEffect state kind) := by
  cases kind <;> first | exact holds | trivial

/-- For every invariant, catalog, nested run, frame, cells, state and step of a program: if the nested run
keeps the invariant ({name}`NestedRun.Keeps`) and the state satisfies
{name}`KeyState.Holds`, the result of {name}`runStep` satisfies
{name}`ProgramResult.Holds`. Proof sketch: a write is the nested run, whose state
{name}`KeyState.afterStep` changes only in fields that the database does not read; a SELECT
keeps the rows or stops with an error; a {lit}`RAISE` is {name}`raiseEffect_holds`. -/
theorem runStep_holds {invariant} {catalog : Catalog} {nested : NestedRun} (keeps : nested.Keeps invariant catalog)
    (frame : RowFrame) (cells : List Value) {state : KeyState} (holds : state.Holds invariant catalog)
    (step : Resolved.Step) : ProgramResult.Holds invariant catalog (runStep catalog nested frame cells state step) := by
  cases step with
  | raise filter arms otherwise =>
    simp only [runStep]
    split
    · exact raiseEffect_holds holds _
    · exact holds
  | query query subqueries =>
    simp only [runStep]
    repeat' (first | split | dsimp only)
    all_goals first | trivial | exact holds
  | insert | update | delete =>
    simp only [runStep]
    unfold ProgramResult.Holds
    split
    · exact ResultHolds.bind (keeps _ _ _ holds) fun _ reached => reached
    · trivial

/-- For every invariant, catalog, nested run, frame, table position and state: if the nested run keeps
the invariant ({name}`NestedRun.Keeps`) and the state satisfies {name}`KeyState.Holds`, the
result of {name}`enterProgram` is a success, which holds no property, or a stop that satisfies
{name}`KeyStop.Holds`. Proof sketch: the result maps the result of the nested run of no rows,
which holds the invariant, and drops its state. -/
theorem enterProgram_holds {invariant} {catalog : Catalog} {nested : NestedRun} (keeps : nested.Keeps invariant catalog)
    (frame : RowFrame) (table : Nat) {state : KeyState} (holds : state.Holds invariant catalog) :
    ResultHolds (fun _ : Unit => True) (KeyStop.Holds invariant catalog) (enterProgram nested frame table state) :=
  ResultHolds.map (keeps frame (.delete table [] false false false) state holds) fun _ _ => trivial

/-- For every invariant, catalog, nested run, frame, cells, state and program: if the nested run keeps the
invariant ({name}`NestedRun.Keeps`) and the state satisfies {name}`KeyState.Holds`, the
result of {name}`runProgram` satisfies {name}`ProgramResult.Holds`. Proof sketch: a program
that the frame runs already, with recursive triggers off, keeps the state; otherwise the entry of
the frame ({name}`enterProgram_holds`) changes no state, a program whose condition is not true
keeps the state, each step of the fold keeps the invariant ({name}`runStep_holds`), and a step
after the end of the row keeps the state. -/
theorem runProgram_holds {invariant} {catalog : Catalog} {nested : NestedRun} (keeps : nested.Keeps invariant catalog)
    (frame : RowFrame) (cells : List Value) {state : KeyState} (holds : state.Holds invariant catalog)
    (program : Resolved.Program) : ProgramResult.Holds invariant catalog (runProgram catalog nested frame cells state program) := by
  unfold runProgram ProgramResult.Holds
  split
  · exact holds
  · refine ResultHolds.bind (enterProgram_holds keeps frame program.table holds) fun _ _ => ?_
    split
    · exact holds
    · refine ResultHolds.foldlM (good := fun reached : KeyState × Bool => reached.1.Holds invariant catalog)
        (fun reached step good => ?_) _ (state, false) holds
      obtain ⟨reachedState, ended⟩ := reached
      dsimp only
      split
      · exact good
      · exact runStep_holds keeps _ cells good step

/-- For every invariant, catalog, nested run, frame, table, time, event, cells and state: if the nested run
keeps the invariant ({name}`NestedRun.Keeps`) and the state satisfies
{name}`KeyState.Holds`, the result of {name}`runPrograms` satisfies
{name}`ProgramResult.Holds`. Proof sketch: a fold of {name}`runProgram_holds`. -/
theorem runPrograms_holds {invariant} {catalog : Catalog} {nested : NestedRun} (keeps : nested.Keeps invariant catalog)
    (frame : RowFrame) (table : Nat) (time : Syntax.TriggerTime) (event : Resolved.TriggerEvent) (cells : List Value)
    {state : KeyState} (holds : state.Holds invariant catalog) :
    ProgramResult.Holds invariant catalog (runPrograms catalog nested frame table time event cells state) := by
  unfold runPrograms
  refine ResultHolds.foldlM (good := fun reached : KeyState × Bool => reached.1.Holds invariant catalog)
    (fun reached program good => ?_) _ (state, false) holds
  obtain ⟨reachedState, ended⟩ := reached
  dsimp only
  split
  · exact good
  · exact runProgram_holds keeps frame cells good program

end Belay.Sqlite.Model
