import Belay.Sqlite.Model.ValidAtomsStatement
import Belay.Sqlite.Model.KeysUniqueScriptRun

set_option doc.verso true

/-! The four constraint atoms of {lit}`Database.Valid` together (ADR 0022, D3, slice 3): the
statement theorem and the run theorems for the conjunction of "not null", "types fit", "checks hold"
and "keys unique", when each reached statement meets all their conditions. The ADR 0017 surface (S4)
uses this form: a run of the bundled database over a database with the four atoms gives a database
with the four atoms. The theorems are the instances of {lit}`RunHolds` and {lit}`ScriptRunHolds` for
the conjunction, whose statement theorem is the four statement theorems. -/

namespace Belay.Sqlite.Model

/-- For the given database: it satisfies the four constraint atoms of {name}`Database.Valid`, each
for its own reading: {name}`Database.NotNull`, {name}`Database.TypesFit`, {name}`Database.ChecksHold`
and {name}`Database.KeysUnique`. It leaves out the facts of {name}`Database.Admitted`. -/
def Database.ConstraintAtoms (database : Database) : Prop :=
  database.NotNull ∧ database.TypesFit ∧ database.ChecksHold ∧ database.KeysUnique

/-- For every profile and database: a valid database ({name}`Database.Valid`) satisfies
{name}`Database.ConstraintAtoms`. Proof sketch: the four fields of the structure. -/
theorem Database.Valid.constraintAtoms {profile : Profile} {database : Database} (valid : database.Valid profile) :
    database.ConstraintAtoms :=
  ⟨valid.notNull, valid.typesFit, valid.check, valid.unique⟩

/-- The condition of a statement on the database for the four atoms together: the run condition of
"keys unique" ({name}`Resolved.Statement.RunCondition`: CREATE INDEX, ADD COLUMN and DROP) and the
conditions of "not null", "types fit" and "checks hold" for ADD COLUMN. All four hold. -/
def Resolved.Statement.AtomsCondition (database : Database) (statement : Resolved.Statement) : Prop :=
  statement.RunCondition database ∧ statement.NotNullCondition database ∧ statement.TypesFitCondition database ∧
    statement.ChecksHoldCondition database

/-- For every database and statement: if the statement has no run condition
({name}`Resolved.Statement.unconditioned`: it is not CREATE INDEX, ADD COLUMN or DROP), it meets
{name}`Resolved.Statement.AtomsCondition` on the database. Proof sketch: a case split on the
statement; each remaining case has four conditions that are {lit}`True`. -/
theorem Resolved.Statement.atomsCondition_of_unconditioned {database : Database} :
    ∀ {statement : Resolved.Statement}, statement.unconditioned = true → statement.AtomsCondition database := by
  intro statement unconditioned
  cases statement <;> first | exact ⟨trivial, trivial, trivial, trivial⟩ | exact nomatch unconditioned

/-- For every four properties of an effect: if the effect satisfies each of them
({name}`Effect.Satisfies`), it satisfies their conjunction. Proof sketch: a database that a run keeps
from the effect has each property. -/
theorem Effect.satisfies_and {first second third fourth : Database → Prop} {effect : Effect}
    (one : effect.Satisfies first) (two : effect.Satisfies second) (three : effect.Satisfies third)
    (four : effect.Satisfies fourth) : effect.Satisfies fun database => first database ∧ second database ∧
      third database ∧ fourth database :=
  fun database kept => ⟨one database kept, two database kept, three database kept, four database kept⟩

/-- The statement theorem of the four atoms together, in the form of {name}`StatementKeeps`, for the
condition {name}`Resolved.Statement.AtomsCondition`. For every clock value, parameter list,
resolved statement and database: if the database satisfies {name}`Database.ConstraintAtoms` and the
statement meets its condition on the database, the effect of {name}`runStatement` satisfies
{name}`Database.ConstraintAtoms` ({name}`Effect.Satisfies`): the database of a success, and the
database that an error with {name}`ExecutionError.constraintFail` carries, satisfy it. An error with
any other reason requires nothing. Proof sketch: {name}`Effect.satisfies_and` of
{name}`runStatement_notNull`, {name}`runStatement_typesFit`, {name}`runStatement_checksHold` and
{name}`runStatement_keysUnique`. -/
theorem constraintAtoms_statementKeeps :
    StatementKeeps Database.ConstraintAtoms fun statement database => statement.AtomsCondition database :=
  fun clock parameters statement _ atoms condition =>
    Effect.satisfies_and (runStatement_notNull clock parameters statement atoms.1 condition.2.1)
      (runStatement_typesFit clock parameters statement atoms.2.1 condition.2.2.1)
      (runStatement_checksHold clock parameters statement atoms.2.2.1 condition.2.2.2)
      (runStatement_keysUnique clock parameters statement atoms.2.2.2
        (Resolved.Statement.keysCondition_of_runCondition condition.1))

/-- For the given position, script and state, each statement that {name}`runSqlFrom` reaches meets
the conditions of the four atoms ({name}`Resolved.Statement.AtomsCondition`) on the database of the
state before it ({name}`RunConditionsWith`). The empty script requires nothing, and a halt requires
nothing of the rest of the script. -/
abbrev AtomsRunConditions (position : Nat) (script : List (Resolved.Statement × List Value)) (state : SqlState) : Prop :=
  RunConditionsWith (fun statement database => statement.AtomsCondition database) position script state

/-- For the given context, clock, index, connection and statements with their values, each statement
that {name}`runScriptFrom` resolves meets the conditions of the four atoms
({name}`Resolved.Statement.AtomsCondition`) on the database of the connection before it
({name}`ScriptConditionsWith`). The empty list requires nothing. A statement that does not resolve
requires no condition. A statement at which the run ends requires nothing of the rest of the
statements; the conditions of the rest apply only when the run continues. -/
abbrev AtomsScriptConditions (context : ResolveContext) (clock : Option Clock) (index : Nat) (connection : Connection)
    (script : List (Syntax.Statement × List Value)) : Prop :=
  ScriptConditionsWith (fun statement database => statement.AtomsCondition database) context clock index connection script

/-- The run theorem of the four atoms for {name}`runSqlFrom`. For every position, script and state:
if the state satisfies {name}`SqlState.Holds` for {name}`Database.ConstraintAtoms` (its database,
and its snapshot when a transaction is open) and the script meets {name}`AtomsRunConditions` from the
position and the state, the outcome of {name}`runSqlFrom` satisfies {name}`Outcome.Holds` for
{name}`Database.ConstraintAtoms`. Proof sketch: {name}`runSqlFrom_holds` for
{name}`constraintAtoms_statementKeeps`. -/
theorem runSqlFrom_constraintAtoms (position : Nat) (script : List (Resolved.Statement × List Value))
    {state : SqlState} (holds : state.Holds Database.ConstraintAtoms)
    (conditions : AtomsRunConditions position script state) :
    (runSqlFrom position script state).Holds Database.ConstraintAtoms :=
  runSqlFrom_holds constraintAtoms_statementKeeps position script holds conditions

/-- The run theorem of the four atoms for {name}`runSql`. For every script and database: if the
database satisfies {name}`Database.ConstraintAtoms` and the script meets {name}`AtomsRunConditions`
from position 0 and the state of the database outside a transaction, the outcome of {name}`runSql`
satisfies {name}`Outcome.Holds` for {name}`Database.ConstraintAtoms`. Proof sketch:
{name}`runSql_holds` for {name}`constraintAtoms_statementKeeps`. -/
theorem runSql_constraintAtoms (script : List (Resolved.Statement × List Value)) {database : Database}
    (holds : database.ConstraintAtoms) (conditions : AtomsRunConditions 0 script { database }) :
    (runSql script database).Holds Database.ConstraintAtoms :=
  runSql_holds constraintAtoms_statementKeeps script holds conditions

/-- The run theorem of the four atoms for {name}`runScriptFrom`. For every context, clock, index,
connection and statements with their values: if the state of the connection satisfies
{name}`SqlState.Holds` for {name}`Database.ConstraintAtoms` (its database, and its snapshot when a
transaction is open) and the statements meet {name}`AtomsScriptConditions` from the index and the
connection, the state of the connection of the run ({lit}`connection.state`) satisfies
{name}`SqlState.Holds` for {name}`Database.ConstraintAtoms`. Proof sketch:
{name}`runScriptFrom_holds` for {name}`constraintAtoms_statementKeeps`. -/
theorem runScriptFrom_constraintAtoms (context : ResolveContext) (clock : Option Clock) (index : Nat)
    {connection : Connection} (script : List (Syntax.Statement × List Value))
    (holds : connection.state.Holds Database.ConstraintAtoms)
    (conditions : AtomsScriptConditions context clock index connection script) :
    (runScriptFrom context clock index connection script).connection.state.Holds Database.ConstraintAtoms :=
  runScriptFrom_holds constraintAtoms_statementKeeps context clock index script holds conditions

end Belay.Sqlite.Model
