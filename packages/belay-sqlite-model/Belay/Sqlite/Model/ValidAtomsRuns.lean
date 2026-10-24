import Belay.Sqlite.Model.ValidAtomsStatement
import Belay.Sqlite.Model.RunHolds

set_option doc.verso true

/-! The run theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3)
for {lit}`runSqlFrom` and {lit}`runSql`: a run from a state whose database and snapshot have the atom
gives an outcome whose databases have it, when each ADD COLUMN that the run reaches meets the condition
of the atom on the database at that point. They are the run theorems of {lit}`RunHolds` for the
statement theorems of {lit}`ValidAtomsStatement`. The theorems for {lit}`runScriptFrom` are in
{lit}`ScriptRunConstraints`: slice 4 proved the resolver facts that give the conditions, so those theorems
have no hypothesis on the statements. -/

namespace Belay.Sqlite.Model

/-- The statement theorem of "not null" in the form of {name}`StatementKeeps`, for the condition of
{name}`Resolved.Statement.NotNullCondition`. For every clock value, counters, parameter list, resolved statement
and database: if the database satisfies {name}`Database.NotNull` and the statement meets its condition
on the database, the effect of {name}`runStatement` satisfies {name}`Database.NotNull`
({name}`Effect.Satisfies`): the database of a success, and the database that an error with
{name}`ExecutionError.constraintFail` carries, satisfy it. An error with any other reason requires
nothing. Proof sketch: {name}`runStatement_notNull`. -/
theorem notNull_statementKeeps : StatementKeeps Database.NotNull fun statement database => statement.NotNullCondition database :=
  fun clock counters parameters statement _ holds condition => runStatement_notNull clock counters parameters statement holds condition

/-- For the given position, script and state, each statement that {name}`runSqlFrom` reaches meets
its condition for "not null" ({name}`Resolved.Statement.NotNullCondition`) on the database of the state
before it ({name}`RunConditionsWith`). The only statement with a condition is ADD COLUMN: the rows of the table at its target are wide ({name}`Database.RowsWideAt`; a target without a table requires nothing).
The empty script requires nothing, and a halt requires nothing of the rest of the script. -/
abbrev NotNullRunConditions (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Prop :=
  RunConditionsWith (fun statement database => statement.NotNullCondition database) position script state

/-- The run theorem of "not null" for {name}`runSqlFrom`. For every position, script and state: if the
state satisfies {name}`SqlState.Holds` for {name}`Database.NotNull` (its database, and its snapshot when a
transaction is open) and the script meets {name}`NotNullRunConditions` from the position and the state,
the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for {name}`Database.NotNull`: the database of a
success or a failure, and the persisted and the visible database of a pending outcome. It assumes
nothing about the other atoms. Proof sketch: {name}`runSqlFrom_holds` for
{name}`notNull_statementKeeps`. -/
theorem runSqlFrom_notNull (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.NotNull) (conditions : NotNullRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.NotNull :=
  runSqlFrom_holds notNull_statementKeeps position script holds conditions

/-- The run theorem of "not null" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.NotNull` and the script meets {name}`NotNullRunConditions` from position 0 and the state of
the database outside a transaction, the outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for
{name}`Database.NotNull`. It assumes nothing about the other atoms. Proof sketch: {name}`runSql_holds` for
{name}`notNull_statementKeeps`. -/
theorem runSql_notNull (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.NotNull database) (conditions : NotNullRunConditions 0 script { database }) :
    (runSql script database).Holds Database.NotNull :=
  runSql_holds notNull_statementKeeps script holds conditions

/-- The statement theorem of "types fit" in the form of {name}`StatementKeeps`, for the condition of
{name}`Resolved.Statement.TypesFitCondition`. For every clock value, counters, parameter list, resolved statement
and database: if the database satisfies {name}`Database.TypesFit` and the statement meets its condition
on the database, the effect of {name}`runStatement` satisfies {name}`Database.TypesFit`
({name}`Effect.Satisfies`): the database of a success, and the database that an error with
{name}`ExecutionError.constraintFail` carries, satisfy it. An error with any other reason requires
nothing. Proof sketch: {name}`runStatement_typesFit`. -/
theorem typesFit_statementKeeps : StatementKeeps Database.TypesFit fun statement database => statement.TypesFitCondition database :=
  fun clock counters parameters statement _ holds condition => runStatement_typesFit clock counters parameters statement holds condition

/-- For the given position, script and state, each statement that {name}`runSqlFrom` reaches meets
its condition for "types fit" ({name}`Resolved.Statement.TypesFitCondition`) on the database of the state
before it ({name}`RunConditionsWith`). The only statement with a condition is ADD COLUMN: the rows of the table at its target are wide ({name}`Database.RowsWideAt`; a target without a table requires nothing), and, when the target holds a table with rows, the stored default of the new column fits its strict type ({name}`Database.StrictDefaultFitsAt`; a target without a table, or a table without rows, requires nothing of the default).
The empty script requires nothing, and a halt requires nothing of the rest of the script. -/
abbrev TypesFitRunConditions (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Prop :=
  RunConditionsWith (fun statement database => statement.TypesFitCondition database) position script state

/-- The run theorem of "types fit" for {name}`runSqlFrom`. For every position, script and state: if the
state satisfies {name}`SqlState.Holds` for {name}`Database.TypesFit` (its database, and its snapshot when a
transaction is open) and the script meets {name}`TypesFitRunConditions` from the position and the state,
the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for {name}`Database.TypesFit`: the database of a
success or a failure, and the persisted and the visible database of a pending outcome. It assumes
nothing about the other atoms. Proof sketch: {name}`runSqlFrom_holds` for
{name}`typesFit_statementKeeps`. -/
theorem runSqlFrom_typesFit (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.TypesFit) (conditions : TypesFitRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.TypesFit :=
  runSqlFrom_holds typesFit_statementKeeps position script holds conditions

/-- The run theorem of "types fit" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.TypesFit` and the script meets {name}`TypesFitRunConditions` from position 0 and the state of
the database outside a transaction, the outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for
{name}`Database.TypesFit`. It assumes nothing about the other atoms. Proof sketch: {name}`runSql_holds` for
{name}`typesFit_statementKeeps`. -/
theorem runSql_typesFit (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.TypesFit database) (conditions : TypesFitRunConditions 0 script { database }) :
    (runSql script database).Holds Database.TypesFit :=
  runSql_holds typesFit_statementKeeps script holds conditions

/-- The statement theorem of "checks hold" in the form of {name}`StatementKeeps`, for the condition of
{name}`Resolved.Statement.ChecksHoldCondition`. For every clock value, counters, parameter list, resolved statement
and database: if the database satisfies {name}`Database.ChecksHold` and the statement meets its condition
on the database, the effect of {name}`runStatement` satisfies {name}`Database.ChecksHold`
({name}`Effect.Satisfies`): the database of a success, and the database that an error with
{name}`ExecutionError.constraintFail` carries, satisfy it. An error with any other reason requires
nothing. Proof sketch: {name}`runStatement_checksHold`. -/
theorem checksHold_statementKeeps : StatementKeeps Database.ChecksHold fun statement database => statement.ChecksHoldCondition database :=
  fun clock counters parameters statement _ holds condition => runStatement_checksHold clock counters parameters statement holds condition

/-- For the given position, script and state, each statement that {name}`runSqlFrom` reaches meets
its condition for "checks hold" ({name}`Resolved.Statement.ChecksHoldCondition`) on the database of the state
before it ({name}`RunConditionsWith`). The only statement with a condition is ADD COLUMN: the rows of the table at its target are wide ({name}`Database.RowsWideAt`; a target without a table requires nothing), and, when the target holds a table, each CHECK constraint of the table reads only columns below its width ({name}`Database.ChecksReadBelowAt`).
The empty script requires nothing, and a halt requires nothing of the rest of the script. -/
abbrev ChecksHoldRunConditions (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Prop :=
  RunConditionsWith (fun statement database => statement.ChecksHoldCondition database) position script state

/-- The run theorem of "checks hold" for {name}`runSqlFrom`. For every position, script and state: if the
state satisfies {name}`SqlState.Holds` for {name}`Database.ChecksHold` (its database, and its snapshot when a
transaction is open) and the script meets {name}`ChecksHoldRunConditions` from the position and the state,
the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for {name}`Database.ChecksHold`: the database of a
success or a failure, and the persisted and the visible database of a pending outcome. It assumes
nothing about the other atoms. Proof sketch: {name}`runSqlFrom_holds` for
{name}`checksHold_statementKeeps`. -/
theorem runSqlFrom_checksHold (position : Nat) (script : List (Resolved.Statement × List Value)) {state : SqlState}
    (holds : state.Holds Database.ChecksHold) (conditions : ChecksHoldRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.ChecksHold :=
  runSqlFrom_holds checksHold_statementKeeps position script holds conditions

/-- The run theorem of "checks hold" for {name}`runSql`. For every script and database: if the database
satisfies {name}`Database.ChecksHold` and the script meets {name}`ChecksHoldRunConditions` from position 0 and the state of
the database outside a transaction, the outcome of {name}`runSql` satisfies {name}`Outcome.Holds` for
{name}`Database.ChecksHold`. It assumes nothing about the other atoms. Proof sketch: {name}`runSql_holds` for
{name}`checksHold_statementKeeps`. -/
theorem runSql_checksHold (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : Database.ChecksHold database) (conditions : ChecksHoldRunConditions 0 script { database }) :
    (runSql script database).Holds Database.ChecksHold :=
  runSql_holds checksHold_statementKeeps script holds conditions

end Belay.Sqlite.Model
