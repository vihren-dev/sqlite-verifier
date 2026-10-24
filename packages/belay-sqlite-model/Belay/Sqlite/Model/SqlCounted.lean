import Belay.Sqlite.Model.SqlState

set_option doc.verso true

/-! The counters after a transition (ADR 0024, D2): a transition that continues takes the
counters after the counts of its statement. -/
namespace Belay.Sqlite.Model

/-- The transition of a statement with the counts it gives the counters: a transition that
continues takes the counters after the counts ({name}`Counters.apply`); a halt stays. -/
def SqlTransition.counted (counts : Counts) : SqlTransition → SqlTransition
  | .next state => .next { state with counters := state.counters.apply counts }
  | .halt outcome => .halt outcome

/-- For every transition, counting the counts of a statement that leaves the counters gives the
same transition. Proof sketch: a halt stays, and a state keeps its counters
({name}`Counters.apply_default`). -/
@[simp] theorem SqlTransition.counted_default (transition : SqlTransition) : transition.counted {} = transition := by
  cases transition <;> simp [SqlTransition.counted]

/-- For every transition, counts and outcome, the transition with the counts applied halts with the
outcome exactly when the transition halts with it. Proof sketch: case analysis on the
transition. -/
@[simp] theorem SqlTransition.counted_eq_halt {counts : Counts} {transition : SqlTransition} {outcome : Outcome} :
    transition.counted counts = .halt outcome ↔ transition = .halt outcome := by
  cases transition <;> simp [SqlTransition.counted]

/-- For every transition, counts and state, the transition with the counts applied continues with
the state exactly when the transition continues with a state whose counters, after the counts,
are the counters of the state, and which is otherwise the same. Proof sketch: case analysis on the
transition. -/
theorem SqlTransition.counted_eq_next {counts : Counts} {transition : SqlTransition} {next : SqlState} :
    transition.counted counts = .next next ↔
      ∃ state, transition = .next state ∧ next = { state with counters := state.counters.apply counts } := by
  cases transition <;> simp [SqlTransition.counted, eq_comm]

end Belay.Sqlite.Model
