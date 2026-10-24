import Belay.Sqlite.Model.KeysUniqueRowEngine
import Belay.Sqlite.Model.KeysUniqueWrites
import Belay.Sqlite.Model.KeysUniqueUpsert
import Belay.Sqlite.Model.KeysUniqueCreate
import Belay.Sqlite.Model.KeysUniqueAddColumn

set_option doc.verso true

/-! The statement theorem of the atom "keys unique" (ADR 0022, D3, slice 2): every resolved
statement keeps {lit}`Database.KeysUnique` on the databases that a run keeps from its effect,
when it meets its condition ({lit}`Resolved.Statement.KeysCondition`). It covers the writes with
and without foreign keys and trigger programs, and has no hypothesis on the support check. -/

namespace Belay.Sqlite.Model

/-- The condition of the statement on the database for the atom "keys unique":
* ADD COLUMN: {name}`Database.AddColumnCondition` at its table;
* DROP: {name}`Catalog.DropCondition` of the catalog at its positions;
* every other statement: nothing. -/
def Resolved.Statement.KeysCondition (database : Database) : Resolved.Statement → Prop
  | .addColumn target _ => database.AddColumnCondition target
  | .drop positions _ => database.catalog.DropCondition positions
  | .createTable .. | .createIndex .. | .createTrigger .. | .begin | .commit | .rollback | .insert .. | .update ..
  | .upsert .. | .delete .. | .prepareError _ | .query .. | .setting _ _ => True

/-- For every rules, clock value, target, work, database, flag and algorithm: if the database
satisfies {name}`Database.KeysUnique`, the effect of {name}`rowsKeys` satisfies
{name}`Effect.KeysUnique`. Proof sketch: {name}`rowsKeys_keysUnique`. -/
theorem rowsKeys_effect_keysUnique (rules : Resolved.WriteRules) (clock : Int) (target : Nat) (work : RowWork)
    {database : Database} (unique : database.KeysUnique) (plain : Bool) (algorithm : Option ConflictAlgorithm) :
    (rowsKeys rules clock target work database plain algorithm).effect.KeysUnique :=
  Effect.keysUnique_of_effectDatabase (rowsKeys_keysUnique rules clock target work unique plain algorithm)

/-- The statement theorem. For every clock value, counters, parameter list, resolved statement and
database: if the database satisfies {name}`Database.KeysUnique` and the statement meets its
condition on the database ({name}`Resolved.Statement.KeysCondition`), the effect of
{name}`runStatement` satisfies {name}`Effect.KeysUnique`: the database of a success, and the
database that an error with {name}`ExecutionError.constraintFail` carries, satisfy
{name}`Database.KeysUnique`. It assumes nothing about the connection or the support check
({lit}`ready`). Proof sketch: a case for each statement form; a write without rules is the
theorem of its form, a write with rules is a write of the row engine
({name}`rowsKeys_keysUnique`, {name}`dropKeys_keysUnique`), and a missing table keeps the
database. -/
theorem runStatement_keysUnique (clock : Int) (counters : Counters) (parameters : List Value) (statement : Resolved.Statement)
    {database : Database} (unique : database.KeysUnique) (condition : statement.KeysCondition database) :
    (runStatement clock counters parameters statement database).effect.KeysUnique := by
  cases statement with
  | createTable target name shape => exact runStatement_createTable_keysUnique clock counters parameters target name shape unique
  | createIndex target name index => exact runStatement_createIndex_keysUnique clock counters parameters target name index unique
  | createTrigger target name trigger =>
    exact runStatement_createTrigger_keysUnique clock counters parameters target name trigger unique
  | addColumn target column => exact runStatement_addColumn_keysUnique clock counters parameters target column unique condition
  | drop positions rules =>
    cases rules with
    | none => exact runStatement_drop_keysUnique clock counters parameters positions unique condition
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      exact Effect.keysUnique_of_effectDatabase (dropKeys_keysUnique rules clock positions unique condition)
  | begin => exact runStatement_writesNone_keysUnique clock counters parameters unique _ (by simp)
  | commit => exact runStatement_writesNone_keysUnique clock counters parameters unique _ (by simp)
  | rollback => exact runStatement_writesNone_keysUnique clock counters parameters unique _ (by simp)
  | prepareError error => exact runStatement_writesNone_keysUnique clock counters parameters unique _ (by simp)
  | query query subqueries => exact runStatement_writesNone_keysUnique clock counters parameters unique _ (by simp)
  | setting setting on => exact runStatement_writesNone_keysUnique clock counters parameters unique _ (by simp)
  | insert target rows returning subqueries rules =>
    cases rules with
    | none => exact runStatement_insert_keysUnique clock counters parameters target rows returning subqueries unique
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.keysUnique_of_database unique rfl
      · exact rowsKeys_effect_keysUnique rules clock target _ unique _ _
  | update target assignments filter returning subqueries rules =>
    cases rules with
    | none => exact runStatement_update_keysUnique clock counters parameters target assignments filter returning subqueries unique
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.keysUnique_of_database unique rfl
      · exact rowsKeys_effect_keysUnique rules _ target _ unique _ _
  | upsert target rows clauses returning algorithm subqueries rules =>
    cases rules with
    | none =>
      exact Effect.keysUnique_of_effectDatabase
        (runStatement_upsert_keysUnique clock counters parameters target rows clauses returning algorithm subqueries unique)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.keysUnique_of_database unique rfl
      · exact rowsKeys_effect_keysUnique rules clock target _ unique _ _
  | delete target filter returning subqueries rules =>
    cases rules with
    | none => exact runStatement_delete_keysUnique clock counters parameters target filter returning subqueries unique
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.keysUnique_of_database unique rfl
      · exact rowsKeys_effect_keysUnique rules _ target _ unique _ _

end Belay.Sqlite.Model
