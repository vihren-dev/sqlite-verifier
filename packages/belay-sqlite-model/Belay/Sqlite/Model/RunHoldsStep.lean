import Belay.Sqlite.Model.RowLocalFrame
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! One step of a run keeps a property of databases (ADR 0022, D3, slices 2 and 3): the database
of the connection state, and its snapshot when a transaction is open, have the property after the
step, and so does each database of an outcome at which the run halts. This module gives the
invariant of a state and of an outcome, and the theorems of the steps that are the same for every
property, up to {lit}`advanceWith`. The property is a parameter: "keys unique" and the atoms "not
null", "types fit" and "checks hold" are instances, and so is their conjunction. -/

namespace Belay.Sqlite.Model

/-- For the given property of databases and state of a run: the database of the state has the
property, and the snapshot has it when the state has one. A state without a snapshot requires
nothing of the snapshot. -/
def SqlState.Holds (property : Database → Prop) (state : SqlState) : Prop :=
  property state.database ∧ ∀ snapshot, state.snapshot = some snapshot → property snapshot

/-- For the given property of databases and outcome of a run, each database of the outcome has the
property:

* the database of a success;
* the database of a failure;
* the persisted and the visible database of a pending outcome. -/
def Outcome.Holds (property : Database → Prop) : Outcome → Prop
  | .success database | .failure _ _ database => property database
  | .pending persisted visible _ => property persisted ∧ property visible

/-- Decide {name}`Outcome.Holds` by the decision of the property for each database of the
outcome, so that the kernel can check it for a concrete run. -/
instance Outcome.decidableHolds (property : Database → Prop) [DecidablePred property] :
    (outcome : Outcome) → Decidable (outcome.Holds property)
  | .success database | .failure _ _ database => inferInstanceAs (Decidable (property database))
  | .pending persisted visible _ => inferInstanceAs (Decidable (property persisted ∧ property visible))

/-- For the given property of databases and transition: a transition that continues has a state
that satisfies {name}`SqlState.Holds`, and a halt has an outcome that satisfies
{name}`Outcome.Holds`. -/
def SqlTransition.Holds (property : Database → Prop) : SqlTransition → Prop
  | .next state => state.Holds property
  | .halt outcome => outcome.Holds property

variable {property : Database → Prop}

/-- For every property, state and outcome: if the state satisfies {name}`SqlState.Holds` and the
outcome satisfies {name}`Outcome.Holds`, the outcome of {name}`SqlState.finish` satisfies
{name}`Outcome.Holds`. Proof sketch: a pending outcome gets the snapshot as its persisted
database. -/
theorem SqlState.finish_holds {state : SqlState} (holds : state.Holds property) {outcome : Outcome}
    (kept : outcome.Holds property) : (state.finish outcome).Holds property := by
  unfold SqlState.finish
  split
  · exact kept
  · exact ⟨holds.2 _ ‹_›, kept⟩
  · exact ⟨holds.2 _ ‹_›, kept⟩
  · exact kept

/-- For every property, state, position, reason and database: if the state satisfies
{name}`SqlState.Holds` and the database has the property, the outcome of {name}`SqlState.failed`
satisfies {name}`Outcome.Holds`. Proof sketch: a rollback gives the snapshot; every other failure is
{name}`SqlState.finish_holds`. -/
theorem SqlState.failed_holds {state : SqlState} (holds : state.Holds property) (position : Nat)
    (reason : ExecutionError) {database : Database} (kept : property database) :
    (state.failed position reason database).Holds property := by
  unfold SqlState.failed
  split
  · split
    · exact holds.2 _ ‹_›
    · exact SqlState.finish_holds holds kept
  · exact SqlState.finish_holds holds kept

/-- For every property, state, position and effect: if the state satisfies
{name}`SqlState.Holds` and the effect satisfies the property ({name}`Effect.Satisfies`), the
transition of {name}`SqlState.publish` satisfies {name}`SqlTransition.Holds`. Proof sketch: a
success continues with the database of the effect; an error halts with the reached database of a
FAIL failure or with the database of the state ({name}`SqlState.failed_holds`). -/
theorem SqlState.publish_holds {state : SqlState} (holds : state.Holds property) (position : Nat)
    {effect : Effect} (kept : effect.Satisfies property) : (state.publish position effect).Holds property := by
  cases effect with
  | ok database => exact ⟨kept database (.inl rfl), holds.2⟩
  | error failure =>
    obtain ⟨reason, reached⟩ := failure
    refine SqlState.failed_holds holds position reason ?_
    split
    · subst reason
      exact kept reached (.inr rfl)
    · exact holds.1

/-- For every property, position, statement, state and effect: if the state satisfies
{name}`SqlState.Holds` and the effect satisfies the property ({name}`Effect.Satisfies`), the
transition of {name}`advanceWith` satisfies {name}`SqlTransition.Holds`. Proof sketch: BEGIN copies
the database into the snapshot, COMMIT drops the snapshot, ROLLBACK restores it, a failure of
them is {name}`SqlState.finish_holds`, and every other statement is
{name}`SqlState.publish_holds`. -/
theorem advanceWith_holds (position : Nat) (statement : Resolved.Statement) {state : SqlState}
    (holds : state.Holds property) {effect : Effect} (kept : effect.Satisfies property) :
    (advanceWith position statement state effect).Holds property := by
  cases statement with
  | begin =>
    dsimp only [advanceWith]
    split
    · exact SqlState.finish_holds holds holds.1
    · exact ⟨holds.1, fun _ same => Option.some.inj same ▸ holds.1⟩
  | commit =>
    dsimp only [advanceWith]
    split
    · exact holds.1
    · exact ⟨holds.1, fun _ same => nomatch same⟩
  | rollback =>
    dsimp only [advanceWith]
    split
    · exact holds.1
    · exact ⟨holds.2 _ ‹_›, fun _ same => nomatch same⟩
  | createTable | createIndex | createTrigger | addColumn | drop | insert | upsert | update | delete
  | prepareError | query | setting => exact SqlState.publish_holds holds position kept

/-- For every property, counts and transition that satisfies {name}`SqlTransition.Holds`, the
transition with the counts applied ({name}`SqlTransition.counted`) satisfies it too. Proof sketch:
the counters are no part of the database or the snapshot. -/
theorem SqlTransition.counted_holds (counts : Counts) {transition : SqlTransition}
    (holds : transition.Holds property) : (transition.counted counts).Holds property := by
  cases transition <;> exact holds

end Belay.Sqlite.Model
