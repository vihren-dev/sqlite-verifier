import Belay.Sqlite.Model.RowLocalStatement

set_option doc.verso true

/-! The statement theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3,
slice 3): every resolved statement keeps the atom on the databases that a run keeps from its effect,
when it meets its condition. Only ADD COLUMN has a condition. The theorems are the instances of
{lit}`runStatement_rowLocal`; each assumes only its own atom. -/

namespace Belay.Sqlite.Model

/-- The condition of a statement on the database for the atom "not null":
* ADD COLUMN: the rows of the table at its target are wide ({name}`Database.RowsWideAt`);
* every other statement: nothing. -/
def Resolved.Statement.NotNullCondition (database : Database) : Resolved.Statement → Prop
  | .addColumn target _ => database.RowsWideAt target
  | .createTable .. | .createIndex .. | .createTrigger .. | .drop .. | .begin | .commit | .rollback | .insert ..
  | .update .. | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => True

/-- The condition of a statement on the database for the atom "types fit":
* ADD COLUMN: the rows of the table at its target are wide ({name}`Database.RowsWideAt`), and the
  stored default of its column fits the strict type when the table has rows
  ({name}`Database.StrictDefaultFitsAt`);
* every other statement: nothing. -/
def Resolved.Statement.TypesFitCondition (database : Database) : Resolved.Statement → Prop
  | .addColumn target column => database.RowsWideAt target ∧ database.StrictDefaultFitsAt target column
  | .createTable .. | .createIndex .. | .createTrigger .. | .drop .. | .begin | .commit | .rollback | .insert ..
  | .update .. | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => True

/-- The condition of a statement on the database for the atom "checks hold":
* ADD COLUMN: the rows of the table at its target are wide ({name}`Database.RowsWideAt`), and each
  CHECK constraint of the table reads only columns below its width
  ({name}`Database.ChecksReadBelowAt`);
* every other statement: nothing. -/
def Resolved.Statement.ChecksHoldCondition (database : Database) : Resolved.Statement → Prop
  | .addColumn target _ => database.RowsWideAt target ∧ database.ChecksReadBelowAt target
  | .createTable .. | .createIndex .. | .createTrigger .. | .drop .. | .begin | .commit | .rollback | .insert ..
  | .update .. | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => True

/-- The statement theorem of "not null". For every clock value, parameter list, resolved statement
and database: if the database satisfies {name}`Database.NotNull` and the statement meets its
condition on the database ({name}`Resolved.Statement.NotNullCondition`), the effect of
{name}`runStatement` satisfies {name}`Database.NotNull` ({name}`Effect.Satisfies`): the database of
a success, and the database that an error with {name}`ExecutionError.constraintFail` carries,
satisfy it. An error with any other reason requires nothing. It assumes nothing about the
connection, the support check ({lit}`ready`), the clock or the other atoms. Proof sketch: {name}`runStatement_rowLocal` for {name}`Table.notNullAtom`, with
{name}`Table.NotNull.appendColumn` for ADD COLUMN. -/
theorem runStatement_notNull (clock : Int) (parameters : List Value) (statement : Resolved.Statement)
    {database : Database} (notNull : database.NotNull) (condition : statement.NotNullCondition database) :
    (runStatement clock parameters statement database).effect.Satisfies Database.NotNull :=
  runStatement_rowLocal Table.notNullAtom clock parameters statement notNull
    fun _ column same table _ found added => by
      subst same
      exact (notNull _ table found).appendColumn (condition table found) added

/-- The statement theorem of "types fit". For every clock value, parameter list, resolved statement
and database: if the database satisfies {name}`Database.TypesFit` and the statement meets its
condition on the database ({name}`Resolved.Statement.TypesFitCondition`), the effect of
{name}`runStatement` satisfies {name}`Database.TypesFit` ({name}`Effect.Satisfies`): the database of
a success, and the database that an error with {name}`ExecutionError.constraintFail` carries,
satisfy it. An error with any other reason requires nothing. It assumes nothing about the
connection, the support check ({lit}`ready`), the clock or the other atoms. Proof sketch: {name}`runStatement_rowLocal` for {name}`Table.typesFitAtom`, with
{name}`Table.TypesFit.appendColumn` for ADD COLUMN. -/
theorem runStatement_typesFit (clock : Int) (parameters : List Value) (statement : Resolved.Statement)
    {database : Database} (fits : database.TypesFit) (condition : statement.TypesFitCondition database) :
    (runStatement clock parameters statement database).effect.Satisfies Database.TypesFit :=
  runStatement_rowLocal Table.typesFitAtom clock parameters statement fits
    fun _ column same table _ found added => by
      subst same
      exact (fits _ table found).appendColumn (condition.1 table found) (condition.2 table found) added

/-- The statement theorem of "checks hold". For every clock value, parameter list, resolved
statement and database: if the database satisfies {name}`Database.ChecksHold` and the statement
meets its condition on the database ({name}`Resolved.Statement.ChecksHoldCondition`), the effect of
{name}`runStatement` satisfies {name}`Database.ChecksHold` ({name}`Effect.Satisfies`): the database
of a success, and the database that an error with {name}`ExecutionError.constraintFail` carries,
satisfy it. An error with any other reason requires nothing. It assumes nothing about the
connection, the support check ({lit}`ready`), the clock or the other atoms. Proof sketch: {name}`runStatement_rowLocal` for {name}`Table.checksHoldAtom`, with
{name}`Table.ChecksHold.appendColumn` for ADD COLUMN. -/
theorem runStatement_checksHold (clock : Int) (parameters : List Value) (statement : Resolved.Statement)
    {database : Database} (holds : database.ChecksHold) (condition : statement.ChecksHoldCondition database) :
    (runStatement clock parameters statement database).effect.Satisfies Database.ChecksHold :=
  runStatement_rowLocal Table.checksHoldAtom clock parameters statement holds
    fun _ column same table _ found added => by
      subst same
      exact (holds _ table found).appendColumn (condition.1 table found) (condition.2 table found) added

end Belay.Sqlite.Model
