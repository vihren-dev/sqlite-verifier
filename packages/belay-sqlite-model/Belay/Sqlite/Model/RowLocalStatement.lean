import Belay.Sqlite.Model.RowEngineWrites
import Belay.Sqlite.Model.RowLocalAddColumnTheorems
import Belay.Sqlite.Model.RowLocalSchema
import Belay.Sqlite.Model.RowLocalUpsert
import Belay.Sqlite.Model.RowLocalWrites

set_option doc.verso true

/-! The statement theorem of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3,
slice 3), stated for every {lit}`RowLocalAtom` at once, for every constructor of
{lit}`Resolved.Statement`: the writes without rules are the theorems of part 1, the writes with
foreign key rules and trigger programs are writes of the row engine ({lit}`RowEngineWrites`), and
ADD COLUMN takes the condition of the atom as a hypothesis. {lit}`ValidAtomsStatement` gives the
three instances. -/

namespace Belay.Sqlite.Model

/-- For every atom, rules, clock value, target, work, database, flag and algorithm: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, the effect of {name}`rowsKeys`
satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database of a success, and
the database that an error with {name}`ExecutionError.constraintFail` carries, have the atom in every
table. An error with any other reason requires nothing. Proof sketch:
{name}`rowsKeys_holds` for the facts of the atom ({name}`RowLocalAtom.facts`). -/
theorem rowsKeys_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (rules : Resolved.WriteRules)
    (clock : Int) (target : Nat) (work : RowWork) {database : Database} (every : database.EachTable atom)
    (plain : Bool) (algorithm : Option ConflictAlgorithm) :
    (rowsKeys rules clock target work database plain algorithm).effect.Satisfies fun after => after.EachTable atom :=
  Effect.satisfies_of_effectDatabase
    (rowsKeys_holds rowLocal.facts rules clock target work (fact := fun _ _ table => atom table) every plain algorithm)

/-- The statement theorem for every atom. For every atom, clock value, counters, parameter list, resolved
statement and database: if the atom is a {name}`RowLocalAtom`, every table of the database has it,
and, when the statement is ADD COLUMN at a target with a column, the table at the target with the
column and every added cell ({name}`AddedCell`) appended has the atom, the effect of
{name}`runStatement` satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database
of a success and that of an error with {name}`ExecutionError.constraintFail` have it, and any other
error requires nothing. It has no condition on the connection, the support check or the clock.
Proof sketch: a case for each statement form; a write without rules is the theorem of its form
from part 1, a write with rules is a write of the row engine ({name}`rowsKeys_rowLocal`,
{name}`dropKeys_holds`), ADD COLUMN is {name}`runStatement_addColumn_rowLocal`, and a missing
table keeps the database. -/
theorem runStatement_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) {database : Database}
    (every : database.EachTable atom)
    (appended : ∀ target column, statement = .addColumn target column → ∀ table value,
      database.table target = some table → AddedCell table column value →
        atom (table.appendColumns [(column, value)])) :
    (runStatement clock counters parameters statement database).effect.Satisfies fun after => after.EachTable atom := by
  cases statement with
  | createTable target name shape => exact runStatement_createTable_rowLocal rowLocal clock counters parameters target name shape every
  | createIndex target name index => exact runStatement_createIndex_rowLocal rowLocal clock counters parameters target name index every
  | createTrigger target name trigger =>
    exact runStatement_createTrigger_rowLocal rowLocal clock counters parameters target name trigger every
  | addColumn target column =>
    exact runStatement_addColumn_rowLocal clock counters parameters target column every (appended target column rfl)
  | drop positions rules =>
    cases rules with
    | none => exact runStatement_drop_rowLocal clock counters parameters positions every
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      exact Effect.satisfies_of_effectDatabase
        (dropKeys_holds rowLocal.facts rules clock positions (fact := fun _ _ table => atom table) every
          fun _ _ kept => Database.EachTable.drop kept positions)
  | begin => exact runStatement_writesNone_rowLocal clock counters parameters every _ (by simp)
  | commit => exact runStatement_writesNone_rowLocal clock counters parameters every _ (by simp)
  | rollback => exact runStatement_writesNone_rowLocal clock counters parameters every _ (by simp)
  | prepareError error => exact runStatement_writesNone_rowLocal clock counters parameters every _ (by simp)
  | query query subqueries => exact runStatement_writesNone_rowLocal clock counters parameters every _ (by simp)
  | setting setting on => exact runStatement_writesNone_rowLocal clock counters parameters every _ (by simp)
  | insert target rows returning subqueries rules =>
    cases rules with
    | none => exact runStatement_insert_rowLocal rowLocal clock counters parameters target rows returning subqueries every
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database every rfl
      · exact rowsKeys_rowLocal rowLocal rules clock target _ every _ _
  | update target assignments filter returning subqueries rules =>
    cases rules with
    | none =>
      exact runStatement_update_rowLocal rowLocal clock counters parameters target assignments filter returning subqueries every
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database every rfl
      · exact rowsKeys_rowLocal rowLocal rules _ target _ every _ _
  | upsert target rows clauses returning algorithm subqueries rules =>
    cases rules with
    | none =>
      exact Effect.satisfies_of_effectDatabase
        (runStatement_upsert_rowLocal rowLocal clock counters parameters target rows clauses returning algorithm subqueries every)
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database every rfl
      · exact rowsKeys_rowLocal rowLocal rules clock target _ every _ _
  | delete target filter returning subqueries rules =>
    cases rules with
    | none => exact runStatement_delete_rowLocal rowLocal clock counters parameters target filter returning subqueries every
    | some rules =>
      simp only [runStatement, Option.map_some, StatementRun.withKeys]
      split
      · exact Effect.satisfies_of_database every rfl
      · exact rowsKeys_rowLocal rowLocal rules _ target _ every _ _

end Belay.Sqlite.Model
