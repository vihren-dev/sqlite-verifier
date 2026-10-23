import Belay.Sqlite.Model.DatabaseConstraintChecks
import Belay.Sqlite.Model.DatabaseLaws
import Belay.Sqlite.Model.Upsert

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
  ({name}`LiteralData.constraints`) has the fact (an INSERT and an UPDATE store such a table).

{lit}`keysUniqueFacts` and {lit}`RowLocalAtom.facts` give the instances for the four atoms
of {lit}`Database.Valid` that are constraints. -/
structure TableFacts (fact : Catalog → Nat → Table → Prop) : Prop where
  /-- A table with the entry and a sublist of the rows of a table that has the fact has it. -/
  sublist : ∀ catalog position (table other : Table), fact catalog position table → other.shape = table.shape →
    other.rows.Sublist table.rows → fact catalog position other
  /-- A table that passes the checks of a write with the unique keys of its position has the
  fact. -/
  constraints : ∀ catalog position (table : Table),
    LiteralData.constraints (catalog.uniqueKeys position table.shape) table = true → fact catalog position table

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

end LiteralData
end Belay.Sqlite.Model
