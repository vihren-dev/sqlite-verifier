import Belay.Sqlite.Model.AdmittedAtomFrames
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The statement theorems of the five table atoms of {lit}`Database.Admitted` (ADR 0022, D3, slice 4)
for the statements that change the schema without the row engine: CREATE TABLE, CREATE INDEX,
CREATE TRIGGER and DROP. The three CREATE statements append one object and an empty row list, so
every table of the result is a table of the database or has no rows. DROP keeps its tables whole.
ADD COLUMN is in {lit}`AdmittedAddColumnLaws` with one law for each atom. -/

namespace Belay.Sqlite.Model

/-- For every property of tables that is a {name}`TableAtom`, clock value, counters, parameter list,
database and statement that is CREATE TABLE, CREATE INDEX or CREATE TRIGGER: if every table of the
database has the property, the effect of {name}`runStatement` satisfies "every table has the
property" ({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have it, and any other error requires nothing. It assumes
nothing about the support check. Proof sketch: a success appends one object and an empty row list
({name}`Database.EachTable.appendEmpty`), and every error keeps the database. -/
theorem runStatement_create_tableAtom {atom : Table → Prop} (tableAtom : TableAtom atom) (clock : Int)
    (counters : Counters) (parameters : List Value) (statement : Resolved.Statement) {database : Database}
    (every : database.EachTable atom)
    (create : (∃ target name shape, statement = .createTable target name shape) ∨
      (∃ target name index, statement = .createIndex target name index) ∨
      (∃ target name trigger, statement = .createTrigger target name trigger)) :
    (runStatement clock counters parameters statement database).effect.Satisfies fun after => after.EachTable atom := by
  rcases create with ⟨target, name, shape, rfl⟩ | ⟨target, name, index, rfl⟩ | ⟨target, name, trigger, rfl⟩
  · simp only [runStatement, step]
    split
    · rename_i fits
      simp only [Bool.and_eq_true, beq_iff_eq] at fits
      exact Effect.satisfies_of_effectDatabase (every.appendEmpty tableAtom fits.2 _)
    · exact Effect.satisfies_of_database every rfl
  · simp only [runStatement, step]
    split
    · rename_i fits
      simp only [Bool.and_eq_true, beq_iff_eq] at fits
      split
      · exact Effect.satisfies_of_database every rfl
      · split
        · exact Effect.satisfies_of_database every rfl
        · exact Effect.satisfies_of_effectDatabase (every.appendEmpty tableAtom fits.2 _)
    · exact Effect.satisfies_of_database every rfl
  · simp only [runStatement, step]
    split
    · rename_i fits
      simp only [Bool.and_eq_true, beq_iff_eq] at fits
      exact Effect.satisfies_of_effectDatabase (every.appendEmpty tableAtom fits.2 _)
    · exact Effect.satisfies_of_database every rfl

end Belay.Sqlite.Model
