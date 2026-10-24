import Belay.Sqlite.Model.RunHolds
import Belay.Sqlite.Model.SqlAdvance

set_option doc.verso true

/-! The run theorem for {lit}`runSqlFrom` and {lit}`runSql` for a statement theorem that needs the
support check (ADR 0022, D3, slice 4). The five table atoms of {lit}`Database.Admitted` hold only for a
statement that stays inside what the model describes ({lit}`StatementRun.ready`), and the condition of
{lit}`StatementKeeps` does not see the clock value, the counters or the parameters on which it depends.
The statement theorem here takes the support check as a hypothesis, and the run theorem takes it from
{lit}`supportedSqlFrom`, which checks it at every statement that the run reaches. -/

namespace Belay.Sqlite.Model

/-- For the given property of databases and condition of statements: the statement theorem with the
support check holds. For every clock value, counters, parameter list, resolved statement and database, if
the database has the property, the statement meets its condition on the database, and the run passes
the support check ({name}`StatementRun.ready`), the effect of {name}`runStatement` satisfies the
property ({name}`Effect.Satisfies`): a success and a failure by a constraint (which keeps the database
that the failure leaves) have the property, and every other failure requires nothing. A theorem of {name}`StatementKeeps` is one of this form that does
not use the support check ({lit}`StatementKeeps.toReady`). -/
def StatementKeepsReady (property : Database → Prop) (condition : Resolved.Statement → Database → Prop) : Prop :=
  ∀ (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) (database : Database),
    property database → condition statement database →
      (runStatement clock counters parameters statement database).ready = true →
      (runStatement clock counters parameters statement database).effect.Satisfies property

variable {property : Database → Prop} {condition : Resolved.Statement → Database → Prop}

/-- For every property and condition: a statement theorem that does not use the support check is one
that may use it. Proof sketch: ignore the hypothesis. -/
theorem StatementKeeps.toReady (keeps : StatementKeeps property condition) : StatementKeepsReady property condition :=
  fun clock counters parameters statement database holds met _ => keeps clock counters parameters statement database holds met

/-- For every property, condition, position, statement, list of values and state: if the statement theorem
with the support check holds ({name}`StatementKeepsReady`), the state satisfies {name}`SqlState.Holds`, the
statement meets the condition on the database of the state, and the run of the statement on the state
passes the support check, the transition of {name}`advance` satisfies {name}`SqlTransition.Holds`. Proof
sketch: as {name}`advance_holds`; the run on the state passes the support check of
{name}`runStatement`, because the check of the state adds a test of the counters. -/
theorem advance_holds_ready (keeps : StatementKeepsReady property condition) (position : Nat)
    (statement : Resolved.Statement) (parameters : List Value) {state : SqlState} (holds : state.Holds property)
    (met : condition statement state.database)
    (ready : (SqlState.statementRun state (state.clock position) parameters statement).ready = true) :
    (advance position statement parameters state).Holds property :=
  SqlTransition.counted_holds _ (advanceWith_holds position statement holds
    (keeps _ _ parameters statement _ holds.1 met (Bool.and_eq_true_iff.mp ready).1))

/-- The run theorem of {name}`runSqlFrom` for a statement theorem with the support check. For every
position, script and state: if the statement theorem holds ({name}`StatementKeepsReady`), the state
satisfies {name}`SqlState.Holds` (its database, and its snapshot when a transaction is open), the script
passes the support check at every statement that the run reaches ({name}`supportedSqlFrom`) and meets
{name}`RunConditionsWith` from the position and the state, the outcome of {name}`runSqlFrom` satisfies
{name}`Outcome.Holds`. Proof sketch: induction on the script with {name}`advance_holds_ready`; the end of
the script is {name}`SqlState.finish_holds`. -/
theorem runSqlFrom_holds_ready (keeps : StatementKeepsReady property condition) :
    ∀ (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState},
      state.Holds property → supportedSqlFrom position script state = true →
        RunConditionsWith condition position script state → (runSqlFrom position script state).Holds property
  | _, [], _, holds, _, _ => SqlState.finish_holds holds holds.1
  | position, (statement, parameters) :: rest, state, holds, supported, conditions => by
    simp only [supportedSqlFrom, Bool.and_eq_true] at supported
    have step := advance_holds_ready keeps position statement parameters holds conditions.1 supported.1
    have later := conditions.2
    have supportedLater := supported.2
    unfold runSqlFrom
    unfold advance at step later supportedLater ⊢
    revert step later supportedLater
    cases advanceRun position statement state (SqlState.statementRun state (state.clock position) parameters statement) with
    | halt outcome => exact fun step _ _ => step
    | next next => exact fun step later supported =>
        runSqlFrom_holds_ready keeps (position + 1) rest step supported later

/-- The run theorem of {name}`runSql` for a statement theorem with the support check. For every script
and database: if the statement theorem holds ({name}`StatementKeepsReady`), the database has the property,
and the script passes the support check ({name}`supportedSqlFrom`) and meets {name}`RunConditionsWith`
from position 0 and the state of the database outside a transaction, the outcome of {name}`runSql`
satisfies {name}`Outcome.Holds`. Proof sketch: {name}`runSqlFrom_holds_ready` from a state without a
snapshot. -/
theorem runSql_holds_ready (keeps : StatementKeepsReady property condition)
    (script : List (Resolved.Statement × List Value)) {database : Database} (holds : property database)
    (supported : supportedSqlFrom 0 script { database } = true)
    (conditions : RunConditionsWith condition 0 script { database }) : (runSql script database).Holds property :=
  runSqlFrom_holds_ready keeps 0 script ⟨holds, fun _ same => nomatch same⟩ supported conditions

/-- For every two properties and conditions: if the statement theorem with the support check holds for each
({name}`StatementKeepsReady`), it holds for the conjunction of the properties with the conjunction of the
conditions. Proof sketch: a database that a run keeps from the effect has each property. -/
theorem StatementKeepsReady.and {other : Database → Prop} {otherCondition : Resolved.Statement → Database → Prop}
    (first : StatementKeepsReady property condition) (second : StatementKeepsReady other otherCondition) :
    StatementKeepsReady (fun database => property database ∧ other database)
      (fun statement database => condition statement database ∧ otherCondition statement database) :=
  fun clock counters parameters statement database holds met ready database' kept =>
    ⟨first clock counters parameters statement database holds.1 met.1 ready database' kept,
      second clock counters parameters statement database holds.2 met.2 ready database' kept⟩

/-- For every two properties with the first stronger than the second: a state that satisfies
{name}`SqlState.Holds` for the first satisfies it for the second. Proof sketch: apply the implication to
the database and to the snapshot. -/
theorem SqlState.Holds.mono {other : Database → Prop} {state : SqlState} (holds : state.Holds property)
    (implies : ∀ database, property database → other database) : state.Holds other :=
  ⟨implies _ holds.1, fun snapshot same => implies _ (holds.2 snapshot same)⟩

/-- For every position, script and state, the script meets {name}`RunConditionsWith` for the condition that
every statement meets on every database. Proof sketch: {name}`RunConditionsWith.of_unconditioned`. -/
theorem RunConditionsWith.always (position : Nat) (script : List (Resolved.Statement × List Value))
    (state : SqlState) : RunConditionsWith (fun _ _ => True) position script state :=
  RunConditionsWith.of_unconditioned (unconditioned := fun _ => true) (fun _ _ _ => trivial) position script state
    (by simp)

end Belay.Sqlite.Model
