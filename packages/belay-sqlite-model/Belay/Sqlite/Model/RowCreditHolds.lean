import Belay.Sqlite.Model.RowEngineTriggers
import Belay.Sqlite.Model.RowCredit

set_option doc.verso true

/-! The counts of the row engine keep its invariant for an atom (ADR 0022, D3; ADR 0024, D2): the
counts of a state are no rows, so a change of the counts of a result keeps the invariant, and so
does {lit}`NestedRun.credited` of a nested run that keeps it. -/

namespace Belay.Sqlite.Model

variable {fact : Catalog → Nat → Table → Prop}

/-- For every fact, catalog, change of states and result of the row engine: if the change keeps the
rows of a state, and the result keeps the invariant of the row engine (a success satisfies
{name}`KeyState.Holds` and a stop {name}`KeyStop.Holds`), then {name}`KeyResult.mapState` of the
result keeps it. Proof sketch: a success and a stop that keeps its rows carry the state with the same
rows ({name}`KeyState.holds_of_rows`), and a stop with an error or without a state requires nothing. -/
theorem KeyResult.mapState_holds {catalog : Catalog} {change : KeyState → KeyState}
    (rowsKept : ∀ state, (change state).rows = state.rows) {result : Except KeyStop KeyState}
    (holds : ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog) result) :
    ResultHolds (KeyState.Holds fact catalog) (KeyStop.Holds fact catalog) (KeyResult.mapState change result) := by
  cases result with
  | ok state => exact KeyState.holds_of_rows (rowsKept state) holds
  | error stop =>
    cases stop with
    | error reason state => trivial
    | stopped algorithm state => exact KeyState.holds_of_rows (rowsKept state) holds
    | undescribed => trivial

/-- For every fact, catalog and nested run: if the nested run keeps the invariant
({name}`NestedRun.Keeps`), so does {name}`NestedRun.credited` of it. Proof sketch: the counts of a
state are no rows, so the nested run starts in a state with the rows of the state around it
({name}`KeyState.holds_of_rows`), and its result keeps them ({name}`KeyResult.mapState_holds`). -/
theorem NestedRun.credited_keeps {catalog : Catalog} {nested : NestedRun} (keeps : nested.Keeps fact catalog) :
    (NestedRun.credited nested).Keeps fact catalog := fun frame work state holds => by
  have ran := keeps frame work { state with own := 0 } (KeyState.holds_of_rows rfl holds)
  unfold NestedRun.credited
  dsimp only
  cases result : nested frame work { state with own := 0 } with
  | error stop =>
    rw [result] at ran
    exact KeyResult.mapState_holds (change := fun reached : KeyState =>
      { reached with own := state.own, inserted := state.inserted }) (fun _ => rfl) ran
  | ok reached =>
    rw [result] at ran
    exact KeyState.holds_of_rows rfl ran

end Belay.Sqlite.Model
