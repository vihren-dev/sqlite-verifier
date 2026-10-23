import Belay.Sqlite.Model.KeysUniqueRunStep

set_option doc.verso true

/-! The run theorem of the atom "keys unique" for {lit}`runSqlFrom` and {lit}`runSql`
(ADR 0022, D3, slice 2): a run from a state whose database and snapshot keep the keys unique
gives an outcome whose databases keep them, when each statement that the run reaches meets its
condition. It is the run theorem of {lit}`RunHolds` for the statement theorem of the atom. The
hypothesis is necessary: finding 1 of the keys-unique status file ({lit}`KeysUniqueExamples.lean`)
is a run of resolved statements without it whose outcome breaks the atom. -/

namespace Belay.Sqlite.Model

/-- For the given position, script and state, each statement that {name}`runSqlFrom` reaches
meets its run condition ({name}`Resolved.Statement.RunCondition`) on the database of the state
before it:

* the empty script requires nothing;
* a script with a first statement requires the condition of that statement on the database of
  the state, and, when {name}`advance` of the statement continues with a next state, the
  conditions of the rest of the script from the next position and the next state. A halt
  requires nothing of the rest. -/
abbrev RunConditions (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Prop :=
  RunConditionsWith (fun statement database => statement.RunCondition database) position script state

/-- For every position, script and state: if each statement of the script has no run condition
({name}`Resolved.Statement.unconditioned`), the script meets {name}`RunConditions` from the
position and the state. Proof sketch: {name}`RunConditionsWith.of_unconditioned` with
{name}`Resolved.Statement.runCondition_of_unconditioned`. -/
theorem RunConditions.of_unconditioned (position : Nat) (script : List (Resolved.Statement × List Value))
    (state : SqlState) (all : (script.all fun item => item.1.unconditioned) = true) :
    RunConditions position script state :=
  RunConditionsWith.of_unconditioned (fun _ _ => Resolved.Statement.runCondition_of_unconditioned) position script
    state all

/-- The statement theorem of "keys unique" in the form of {name}`StatementKeeps`, for the run
condition of a statement. For every clock value, parameter list, resolved statement and database:
if the database satisfies {name}`Database.KeysUnique` and the statement meets its run condition
({name}`Resolved.Statement.RunCondition`) on the database, the effect of {name}`runStatement`
satisfies {name}`Database.KeysUnique` ({name}`Effect.Satisfies`): the database of a success, and
the database that an error with {name}`ExecutionError.constraintFail` carries, satisfy it. An error
with any other reason requires nothing. Proof sketch: {name}`runStatement_keysUnique` with
{name}`Resolved.Statement.keysCondition_of_runCondition`. -/
theorem keysUnique_statementKeeps :
    StatementKeeps Database.KeysUnique fun statement database => statement.RunCondition database :=
  fun clock parameters statement _ unique condition =>
    runStatement_keysUnique clock parameters statement unique
      (Resolved.Statement.keysCondition_of_runCondition condition)

/-- The run theorem of {name}`runSqlFrom`. For every position, script and state: if the state
satisfies {name}`SqlState.KeysUnique` (its database, and its snapshot when a transaction is
open) and the script meets {name}`RunConditions` from the position and the state, the outcome
of {name}`runSqlFrom` satisfies {name}`Outcome.KeysUnique`: the database of a success or a
failure, and the persisted and the visible database of a pending outcome. Proof sketch:
{name}`runSqlFrom_holds` for {name}`keysUnique_statementKeeps`. -/
theorem runSqlFrom_keysUnique (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (unique : state.KeysUnique) (conditions : RunConditions position script state) :
    (runSqlFrom position script state).KeysUnique :=
  runSqlFrom_holds keysUnique_statementKeeps position script unique conditions

/-- The run theorem of {name}`runSql`, the run that ADR 0022, D3 names. For every script and
database: if the database satisfies {name}`Database.KeysUnique` and the script meets
{name}`RunConditions` from position 0 and the state of the database outside a transaction, the
outcome of {name}`runSql` satisfies {name}`Outcome.KeysUnique`. Proof sketch:
{name}`runSql_holds` for {name}`keysUnique_statementKeeps`. -/
theorem runSql_keysUnique (script : List (Resolved.Statement × List Value)) {database : Database}
    (unique : database.KeysUnique) (conditions : RunConditions 0 script { database }) :
    (runSql script database).KeysUnique :=
  runSql_holds keysUnique_statementKeeps script unique conditions

end Belay.Sqlite.Model
