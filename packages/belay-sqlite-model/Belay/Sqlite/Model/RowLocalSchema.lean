import Belay.Sqlite.Model.KeysUniqueDrop
import Belay.Sqlite.Model.RowLocalFrame
import Belay.Sqlite.Model.StatementStep

set_option doc.verso true

/-! The theorems of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3),
stated for every {lit}`RowLocalAtom`, for CREATE TABLE, CREATE INDEX, CREATE TRIGGER and DROP
without the row engine. The first three append one object and an empty row list, so every kept
table is a table of the database or has no rows. A drop keeps its tables whole, with their rows
and entries, so it keeps every such atom for every database, without a condition: the atoms read
no index and no position. {lit}`RowLocalSchemaTheorems` states them for each atom. -/

namespace Belay.Sqlite.Model

/-- For every atom, database and positions: if every table of the database has the atom, every
table of the database after {name}`Database.drop` has it. Proof sketch: a table after the drop is
a table of the database ({name}`Database.table_drop_cases`). -/
theorem Database.EachTable.drop {atom : Table → Prop} {database : Database} (every : database.EachTable atom)
    (positions : List Nat) : (database.drop positions).EachTable atom := by
  intro position table present
  obtain ⟨old, _, _, found⟩ := Database.table_drop_cases present
  exact every old table found

/-- For every atom, clock value, parameter list, CREATE TABLE and database: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, the effect of {name}`runStatement`
satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database of a success and that
of an error with {name}`ExecutionError.constraintFail` have it, and any other error requires
nothing. The new table has no rows. Proof
sketch: {name}`Database.EachTable.append`; every error keeps the database. -/
theorem runStatement_createTable_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (name : Identifier) (shape : CatalogTable) {database : Database}
    (every : database.EachTable atom) :
    (runStatement clock parameters (.createTable target name shape) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement, step]
  split
  · rename_i fits
    simp only [Bool.and_eq_true, beq_iff_eq] at fits
    exact Effect.satisfies_of_effectDatabase (every.append rowLocal fits.2 _)
  · exact Effect.satisfies_of_database every rfl

/-- For every atom, clock value, parameter list, CREATE TRIGGER and database: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, the effect of {name}`runStatement`
satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database of a success and that
of an error with {name}`ExecutionError.constraintFail` have it, and any other error requires
nothing. A trigger has no rows. Proof sketch:
{name}`Database.EachTable.append`; every error keeps the database. -/
theorem runStatement_createTrigger_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (name : Identifier) (trigger : CatalogTrigger) {database : Database}
    (every : database.EachTable atom) :
    (runStatement clock parameters (.createTrigger target name trigger) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement, step]
  split
  · rename_i fits
    simp only [Bool.and_eq_true, beq_iff_eq] at fits
    exact Effect.satisfies_of_effectDatabase (every.append rowLocal fits.2 _)
  · exact Effect.satisfies_of_database every rfl

/-- For every atom, clock value, parameter list, CREATE INDEX and database: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, the effect of {name}`runStatement`
satisfies "every table has the atom" ({name}`Effect.Satisfies`): the database of a success and that
of an error with {name}`ExecutionError.constraintFail` have it, and any other error requires
nothing. An index has no rows and changes no table. Proof sketch:
{name}`Database.EachTable.append`; every error keeps the database. -/
theorem runStatement_createIndex_rowLocal {atom : Table → Prop} (rowLocal : RowLocalAtom atom) (clock : Int)
    (parameters : List Value) (target : Nat) (name : Identifier) (index : CatalogIndex) {database : Database}
    (every : database.EachTable atom) :
    (runStatement clock parameters (.createIndex target name index) database).effect.Satisfies
      fun after => after.EachTable atom := by
  simp only [runStatement, step]
  split
  · rename_i fits
    simp only [Bool.and_eq_true, beq_iff_eq] at fits
    split
    · exact Effect.satisfies_of_database every rfl
    · split
      · exact Effect.satisfies_of_database every rfl
      · exact Effect.satisfies_of_effectDatabase (every.append rowLocal fits.2 _)
  · exact Effect.satisfies_of_database every rfl

/-- For every atom, clock value, parameter list, DROP without foreign key rules and trigger
programs ({lean}`(none : Option Resolved.WriteRules)`) and database: if every table of the database
has the atom, the effect of {name}`runStatement` satisfies "every table has the atom"
({name}`Effect.Satisfies`): the database of a success and that of an error with
{name}`ExecutionError.constraintFail` have it, and any other error requires nothing. The atom
need not be a {name}`RowLocalAtom`, and DROP has no condition. Proof sketch: the effect is the
database after {name}`Database.drop` ({name}`Database.EachTable.drop`). -/
theorem runStatement_drop_rowLocal {atom : Table → Prop} (clock : Int) (parameters : List Value)
    (positions : List Nat) {database : Database} (every : database.EachTable atom) :
    (runStatement clock parameters (.drop positions none) database).effect.Satisfies fun after => after.EachTable atom := by
  simp only [runStatement, Option.map_none, StatementRun.withKeys, step]
  exact Effect.satisfies_of_effectDatabase (every.drop positions)

end Belay.Sqlite.Model
