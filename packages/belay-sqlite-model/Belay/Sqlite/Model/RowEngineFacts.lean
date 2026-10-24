import Belay.Sqlite.Model.DatabaseConstraintChecks
import Belay.Sqlite.Model.DatabaseLaws
import Belay.Sqlite.Model.Upsert
import Belay.Sqlite.Model.LiteralAdmittedRow

set_option doc.verso true

/-! The facts of an atom that the proofs about the row engine use (ADR 0022, D3, slices 2 and
3). The row engine writes a table in three ways: it deletes rows (a sublist), it replaces a row,
and it appends a row, and the two last write a table that passed {lit}`LiteralData.constraints`.
So an atom that says a fact of each table, from the catalog and the table's position, is kept by
the engine when it has two facts: {lit}`TableFacts`. "Keys unique" and the three atoms of slice 3
("not null", "types fit", "checks hold") have them, so the proofs of the engine are written
once, for any such atom. -/

namespace Belay.Sqlite.Model

/-- The facts of an atom that says a fact of each table of a database from the catalog, the
position and the table. Two facts:
* a table with the same catalog entry and a sublist of the rows of a table that has the fact has
  it (a DELETE stores such a table);
* a table that passes the checks of a write with the unique keys of its position
  ({name}`LiteralData.constraints`) and has distinct rowids ({name}`LiteralData.rowidsDistinct`) has
  the fact (an INSERT and an UPDATE store such a table).

{lit}`keysUniqueFacts` and {lit}`RowLocalAtom.facts` give the instances for the four atoms
of {lit}`Database.Valid` that are constraints. -/
structure TableFacts (fact : Catalog → Nat → Table → Prop) : Prop where
  /-- A table with the entry and a sublist of the rows of a table that has the fact has it. -/
  sublist : ∀ catalog position (table other : Table), fact catalog position table → other.shape = table.shape →
    other.rows.Sublist table.rows → fact catalog position other
  /-- A table that passes the checks of a write with the unique keys of its position, and has
  distinct rowids, has the fact. -/
  constraints : ∀ catalog position (table : Table),
    (LiteralData.constraints (catalog.uniqueKeys position table.shape) table &&
      LiteralData.rowidsDistinct table) = true → fact catalog position table

/-- The facts of a property of databases that the row engine needs to keep it: the engine changes the
rows of one position in two ways. Two facts:
* a DELETE, which keeps a sublist of the rows at a position, keeps the property;
* the write of a table that passes the checks of a write ({name}`LiteralData.constraints` with the unique
  keys of its position, and {name}`LiteralData.rowidsDistinct`), and whose rows are rows of the old table or
  admitted rows ({name}`LiteralData.rowAdmitted`), keeps the property, when the database has a table at
  the position.

{lit}`TableFacts.laws` gives the instance for a fact of each table, and the properties
"rows shaped" and "catalog supported" have their own. -/
structure WriteLaws (invariant : Database → Prop) : Prop where
  /-- For every database with the property, position and function of row lists that returns a
  sublist of every row list: the database after {name}`Database.setRows` at the position with the
  function applied to the rows there has the property. -/
  sublist : ∀ (database : Database) (position : Nat) (change : List Row → List Row), invariant database →
    (∀ rows, (change rows).Sublist rows) → invariant (database.setRows position (change (database.rows.getD position [])))
  /-- For every database with the property, position, table of the database at the position and rows:
  if the table with the rows passes the checks of a write, and each of the rows is a row of the table or
  is admitted ({name}`LiteralData.rowAdmitted` for the entry of the table), the database after
  {name}`Database.setRows` with the rows at the position has the property. Without a table at the
  position, for rows that fail the checks, and for a row that is neither, the law requires nothing. -/
  write : ∀ (database : Database) (position : Nat) (table : Table) (rows : List Row), invariant database →
    database.table position = some table →
    (LiteralData.constraints (database.catalog.uniqueKeys position table.shape) { table with rows } &&
      LiteralData.rowidsDistinct { table with rows }) = true →
    (∀ row ∈ rows, row ∈ table.rows ∨ LiteralData.rowAdmitted table.shape row = true) →
    invariant (database.setRows position rows)

/-- For the given fact of a table and database: every table of the database has the fact, with
the catalog of the database. -/
abbrev Database.Every (fact : Catalog → Nat → Table → Prop) (database : Database) : Prop :=
  database.EveryTable fun position table => fact database.catalog position table

/-- For every fact, database, position, table and rows: if every table of the database has the
fact, the database has the table at the position, and the table with the rows has the fact over
the catalog, then every table of the database after {name}`Database.setRows` with the rows at
the position has it. Proof sketch: the catalog does not change; at the position the table has the
new rows ({name}`Database.table_setRows`), or, for a position past the end of the row lists, the
database does not change; at every other position the table is the same
({name}`Database.table_setRows_other`). -/
theorem Database.Every.setRows {fact : Catalog → Nat → Table → Prop} {database : Database}
    (every : database.Every fact) {target : Nat} {table : Table} (found : database.table target = some table)
    {rows : List Row} (stored : fact database.catalog target { table with rows }) :
    (database.setRows target rows).Every fact := by
  intro position other present
  by_cases same : position = target
  · subst same
    by_cases aligned : position < database.rows.length
    · rw [Database.table_setRows rows found aligned, Option.some.injEq] at present
      subst present
      exact stored
    · have unchanged : database.setRows position rows = database := by
        simp only [Database.setRows, List.set_eq_of_length_le (Nat.le_of_not_lt aligned)]
      rw [unchanged] at present ⊢
      exact every position other present
  · rw [Database.table_setRows_other database rows same] at present
    exact every position other present

/-- For every database and position: if the database has a table at the position, its rows are the
rows of the database there. Proof sketch: the definition of {name}`Database.table`. -/
theorem Database.table_rows_eq {database : Database} {position : Nat} {table : Table}
    (found : database.table position = some table) : table.rows = database.rows.getD position [] := by
  obtain ⟨_, _, same⟩ := Option.map_eq_some_iff.mp found
  rw [← same]

/-- For every fact, database, position and change of rows: if every table of the database has the fact,
and the table at the position (when there is one) with the changed rows has the fact for the position,
then every table of the database after {name}`Database.setRows` with the changed rows has it. A position
without a table requires nothing. Proof sketch: {name}`Database.Every.setRows` at the table; without a
table, every table of the database is the same ({name}`Database.table_setRows_other`). -/
theorem Database.Every.change {fact : Catalog → Nat → Table → Prop} {database : Database}
    (every : database.Every fact) {position : Nat} {change : List Row → List Row}
    (stored : ∀ table, database.table position = some table →
      fact database.catalog position { table with rows := change (database.rows.getD position []) }) :
    (database.setRows position (change (database.rows.getD position []))).Every fact := by
  cases found : database.table position with
  | some table => exact every.setRows found (stored table found)
  | none =>
    intro other table present
    by_cases same : other = position
    · subst same
      simp [Database.table, Database.setRows] at found present
      simp_all
    · rw [Database.table_setRows_other _ _ same] at present
      exact every other table present

/-- A fact of each table that has the facts of {name}`TableFacts` gives the facts of
{name}`WriteLaws` for "every table has the fact". Proof sketch: {name}`Database.Every.change` with the
two facts of the fact; the rows of the table at the position are the rows of the database
({name}`Database.table_rows_eq`). -/
theorem TableFacts.laws {fact : Catalog → Nat → Table → Prop} (facts : TableFacts fact) :
    WriteLaws (Database.Every fact) where
  sublist database position change every sub :=
    every.change fun table found => facts.sublist database.catalog position table _ (every position table found) rfl
      (by rw [Database.table_rows_eq found]; exact sub _)
  write database position table rows every found passed _ :=
    every.setRows found (facts.constraints database.catalog position { table with rows } passed)

namespace LiteralData

/-- For every keys, two tables and rows: if {name}`checkedRow` of the next table succeeds with a
table, that table is the next table and passed {name}`constraints` for the keys. Proof sketch:
{name}`checkedRow` stores its input table after the check. -/
theorem checkedRow_constraints {keys : List UniqueKey} {next stored : Table} {written : Row} {row : Option Row}
    (ok : checkedRow keys next written = .ok (stored, row)) : stored = next ∧ constraints keys next = true := by
  unfold checkedRow at ok
  split at ok
  · rename_i passed
    simp only [Except.ok.injEq, Prod.mk.injEq] at ok
    exact ⟨ok.1.symm, (Bool.and_eq_true _ _ ▸ passed).1⟩
  · simp at ok

/-- For every keys, two tables, row and optional row: if {name}`checkedRow` succeeds, the stored
table is the next table, and the next table passed {name}`constraints` and {name}`rowidsDistinct`.
Proof sketch: {name}`checkedRow` stores its input after the check. -/
theorem checkedRow_passed {keys : List UniqueKey} {next stored : Table} {written : Row} {row : Option Row}
    (ok : checkedRow keys next written = .ok (stored, row)) :
    stored = next ∧ (constraints keys next && rowidsDistinct next) = true := by
  unfold checkedRow at ok
  split at ok
  · rename_i passed
    simp only [Except.ok.injEq, Prod.mk.injEq] at ok
    exact ⟨ok.1.symm, passed⟩
  · simp at ok

end LiteralData
end Belay.Sqlite.Model
