import Belay.Sqlite.Model.DatabaseLaws
import Belay.Sqlite.Model.Execution
import Belay.Sqlite.Model.KeysUniqueCreate
import Belay.Sqlite.Model.RowLocalAtoms

set_option doc.verso true

/-! The frame of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3, slice 3),
stated for every {lit}`RowLocalAtom` at once: which databases of an effect the theorems of the
statements are about ({lit}`Effect.Satisfies`), and the lemmas of a write that stores rows at one
position or appends one object. The theorems for each statement form use them, as the theorems of
the atom "keys unique" use {lit}`KeysUniqueFrame`. -/

namespace Belay.Sqlite.Model

/-- For the given property of a table and database: the property holds for every table of the
database. For {name}`Table.NotNull` this is {name}`Database.NotNull`, and likewise for the other
two atoms of this slice. -/
abbrev Database.EachTable (database : Database) (atom : Table → Prop) : Prop :=
  database.EveryTable fun _ table => atom table

/-- For the given property of a database: it holds for every database that a run can keep from
the effect. These are two cases:
* the effect succeeds with the database;
* the effect fails with {name}`ExecutionError.constraintFail` and carries the database, which
  keeps the rows that a FAIL write stored before the failed row.

An error with any other reason requires nothing: the run keeps the input database, or the
snapshot of a ROLLBACK, for it ({lit}`SqlState.publish`). -/
def Effect.Satisfies (property : Database → Prop) (effect : Effect) : Prop :=
  ∀ database, effect = .ok database ∨ effect = .error (.constraintFail, database) → property database

/-- For every property and effect: if the database of the effect ({name}`effectDatabase`) has
the property, the effect satisfies it ({name}`Effect.Satisfies`). Proof sketch: both databases of
{name}`Effect.Satisfies` are the database of the effect. -/
theorem Effect.satisfies_of_effectDatabase {property : Database → Prop} {effect : Effect}
    (holds : property (effectDatabase effect)) : effect.Satisfies property := by
  intro database kept
  rcases kept with same | same <;> subst same <;> exact holds

/-- For every property, effect and database: if the database has the property and the database of
the effect is the database, the effect satisfies the property. This is the case of each statement
that writes no row, and of each error that keeps the input database. Proof sketch:
{name}`Effect.satisfies_of_effectDatabase` after rewriting the database of the effect. -/
theorem Effect.satisfies_of_database {property : Database → Prop} {effect : Effect} {database : Database}
    (holds : property database) (kept : effectDatabase effect = database) : effect.Satisfies property :=
  Effect.satisfies_of_effectDatabase (kept ▸ holds)

/-- For every atom, database, position, table and rows: if every table of the database has the
atom, the database has the table at the position, and the table with the rows has the atom, then
every table of the database after {name}`Database.setRows` with the rows at the position has it.
Proof sketch: the catalog does not change; at the position the table has the new rows
({name}`Database.table_setRows`), or, for a position past the end of the row lists, the database
does not change; at every other position the table is the same
({name}`Database.table_setRows_other`). -/
theorem Database.EachTable.setRows {atom : Table → Prop} {database : Database} (every : database.EachTable atom)
    {target : Nat} {table : Table} (found : database.table target = some table) {rows : List Row}
    (stored : atom { table with rows }) : (database.setRows target rows).EachTable atom := by
  intro position other present
  by_cases same : position = target
  · subst same
    by_cases aligned : position < database.rows.length
    · rw [Database.table_setRows rows found aligned, Option.some.injEq] at present
      subst present
      exact stored
    · have unchanged : database.setRows position rows = database := by
        simp only [Database.setRows, List.set_eq_of_length_le (Nat.le_of_not_lt aligned)]
      rw [unchanged] at present
      exact every position other present
  · rw [Database.table_setRows_other database rows same] at present
    exact every position other present

/-- For every atom, database whose row lists match its catalog and object: if the atom is a
{name}`RowLocalAtom` and every table of the database has it, every table of the database with
the object and an empty row list appended has it. CREATE TABLE, CREATE INDEX and CREATE TRIGGER
append such an object. Proof sketch: a table of the new database is a table of the old one or has
no rows ({name}`Database.table_append_cases`). -/
theorem Database.EachTable.append {atom : Table → Prop} (rowLocal : RowLocalAtom atom) {database : Database}
    (every : database.EachTable atom) (aligned : database.rows.length = database.catalog.length)
    (object : CatalogObject) :
    ({ catalog := database.catalog ++ [object], rows := database.rows ++ [[]] } : Database).EachTable atom := by
  intro position table present
  rcases Database.table_append_cases aligned object present with old | empty
  · exact every position table old
  · exact rowLocal.empty table empty

end Belay.Sqlite.Model
