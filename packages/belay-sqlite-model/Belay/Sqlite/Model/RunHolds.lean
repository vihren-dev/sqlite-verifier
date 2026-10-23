import Belay.Sqlite.Model.RunHoldsStep

set_option doc.verso true

/-! The run theorem for {lit}`runSqlFrom` and {lit}`runSql`, for every property of databases
(ADR 0022, D3, slices 2 and 3): if the statement theorem of the property holds for the statements
of a script, a run from a state whose database and snapshot have the property gives an outcome
whose databases have it, when each statement that the run reaches meets its condition. The
statement theorem and the condition are parameters: the theorems of each atom are instances. -/

namespace Belay.Sqlite.Model

/-- For the given property of databases and condition of statements: the statement theorem
holds. For every clock value, parameter list, resolved statement and database, if the database has
the property and the statement meets its condition on the database, the effect of
{name}`runStatement` satisfies the property ({name}`Effect.Satisfies`): the database of a success,
and the database that an error with {name}`ExecutionError.constraintFail` carries, have it. An error
with any other reason requires nothing of its database: the run keeps the input database, or the
snapshot of a ROLLBACK, for it. -/
def StatementKeeps (property : Database → Prop) (condition : Resolved.Statement → Database → Prop) : Prop :=
  ∀ (clock : Int) (parameters : List Value) (statement : Resolved.Statement) (database : Database),
    property database → condition statement database →
      (runStatement clock parameters statement database).effect.Satisfies property

/-- For the given condition of statements on a database, position, script and state, each
statement that {name}`runSqlFrom` reaches meets the condition on the database of the state
before it:

* the empty script requires nothing;
* a script with a first statement requires the condition of that statement on the database of
  the state, and, when {name}`advance` of the statement continues with a next state, the
  conditions of the rest of the script from the next position and the next state. A halt
  requires nothing of the rest. -/
def RunConditionsWith (condition : Resolved.Statement → Database → Prop) (position : Nat) :
    List (Resolved.Statement × List Value) → SqlState → Prop
  | [], _ => True
  | (statement, parameters) :: rest, state =>
    condition statement state.database ∧
      match advance position statement parameters state with
      | .halt _ => True
      | .next next => RunConditionsWith condition (position + 1) rest next

/-- For every condition of statements, test of statements without a condition, position, script
and state: if a statement that the test accepts meets the condition on every database, and each
statement of the script is accepted, the script meets {name}`RunConditionsWith` from the position
and the state. Proof sketch: induction on the script. -/
theorem RunConditionsWith.of_unconditioned {condition : Resolved.Statement → Database → Prop}
    {unconditioned : Resolved.Statement → Bool}
    (free : ∀ statement database, unconditioned statement = true → condition statement database) :
    ∀ (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState),
      (script.all fun item => unconditioned item.1) = true → RunConditionsWith condition position script state
  | _, [], _, _ => trivial
  | position, (statement, parameters) :: rest, state, all => by
    simp only [List.all_cons, Bool.and_eq_true] at all
    refine ⟨free _ _ all.1, ?_⟩
    cases advance position statement parameters state with
    | halt _ => trivial
    | next next => exact RunConditionsWith.of_unconditioned free (position + 1) rest next all.2

variable {property : Database → Prop} {condition : Resolved.Statement → Database → Prop}

/-- For every property, condition, position, statement, list of values and state: if the statement
theorem holds ({name}`StatementKeeps`), the state satisfies {name}`SqlState.Holds` and the
statement meets the condition on the database of the state, the transition of {name}`advance`
satisfies {name}`SqlTransition.Holds`. Proof sketch: {name}`advanceWith_holds` of the effect of
the statement theorem. -/
theorem advance_holds (keeps : StatementKeeps property condition) (position : Nat) (statement : Resolved.Statement)
    (parameters : List Value) {state : SqlState} (holds : state.Holds property)
    (met : condition statement state.database) : (advance position statement parameters state).Holds property :=
  advanceWith_holds position statement holds (keeps _ parameters statement _ holds.1 met)

/-- The run theorem of {name}`runSqlFrom`, for every property and condition. For every position,
script and state: if the statement theorem holds ({name}`StatementKeeps`), the state satisfies
{name}`SqlState.Holds` (its database, and its snapshot when a transaction is open) and the script
meets {name}`RunConditionsWith` from the position and the state, the outcome of {name}`runSqlFrom`
satisfies {name}`Outcome.Holds`: the database of a success or a failure, and the persisted and the
visible database of a pending outcome. Proof sketch: induction on the script with
{name}`advance_holds`; the end of the script is {name}`SqlState.finish_holds`. -/
theorem runSqlFrom_holds (keeps : StatementKeeps property condition) :
    ∀ (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState},
      state.Holds property → RunConditionsWith condition position script state →
        (runSqlFrom position script state).Holds property
  | _, [], _, holds, _ => SqlState.finish_holds holds holds.1
  | position, (statement, parameters) :: rest, state, holds, conditions => by
    have step := advance_holds keeps position statement parameters holds conditions.1
    have later := conditions.2
    unfold runSqlFrom
    revert step later
    cases advance position statement parameters state with
    | halt outcome => exact fun step _ => step
    | next next => exact fun step later => runSqlFrom_holds keeps (position + 1) rest step later

/-- The run theorem of {name}`runSql`, for every property and condition. For every script and
database: if the statement theorem holds ({name}`StatementKeeps`), the database has the property
and the script meets {name}`RunConditionsWith` from position 0 and the state of the database
outside a transaction, the outcome of {name}`runSql` satisfies {name}`Outcome.Holds`. Proof sketch:
{name}`runSqlFrom_holds` from a state without a snapshot. -/
theorem runSql_holds (keeps : StatementKeeps property condition) (script : List (Resolved.Statement × List Value))
    {database : Database} (holds : property database) (conditions : RunConditionsWith condition 0 script { database }) :
    (runSql script database).Holds property :=
  runSqlFrom_holds keeps 0 script ⟨holds, fun _ same => nomatch same⟩ conditions

end Belay.Sqlite.Model
