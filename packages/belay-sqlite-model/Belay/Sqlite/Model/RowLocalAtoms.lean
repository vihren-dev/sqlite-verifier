import Belay.Sqlite.Model.DatabaseConstraintChecks
import Belay.Sqlite.Model.RowEngineFacts

set_option doc.verso true

/-! The frame lemmas of the atoms "not null", "types fit" and "checks hold" (ADR 0022, D3,
slice 3), and what the three share. Each atom says a fact of each row with the catalog entry of
its table, so a table whose rows are rows of a table that satisfies the atom, with the same
columns (or the same CHECK constraints), satisfies it. {lit}`RowLocalAtom` collects the three
facts that the proofs about statements use, so one argument serves the three atoms; the theorems
of the statements stay one for each atom. -/

namespace Belay.Sqlite.Model

/-- The frame lemma of {name}`Table.NotNull`, for every two tables: if the first satisfies it,
each row of the second is a row of the first, and the second has the same columns, the second
satisfies it. The CHECK constraints and the keys of the entries can differ. Proof sketch: a cell
of a row of the second at a NOT NULL column is the cell of the same row of the first. -/
theorem Table.NotNull.frame {table other : Table} (notNull : table.NotNull)
    (rows : ∀ row ∈ other.rows, row ∈ table.rows) (columns : other.shape.columns = table.shape.columns) :
    other.NotNull :=
  fun row member position column value atColumn atValue flagged =>
    notNull row (rows row member) position column value (columns ▸ atColumn) atValue flagged

/-- The frame lemma of {name}`Table.TypesFit`, for every two tables: if the first satisfies it,
each row of the second is a row of the first, and the second has the same columns, the second
satisfies it. Proof sketch: a cell of a row of the second at a column is the cell of the same row
of the first at the same column. -/
theorem Table.TypesFit.frame {table other : Table} (fits : table.TypesFit)
    (rows : ∀ row ∈ other.rows, row ∈ table.rows) (columns : other.shape.columns = table.shape.columns) :
    other.TypesFit :=
  fun row member position column value atColumn atValue =>
    fits row (rows row member) position column value (columns ▸ atColumn) atValue

/-- The frame lemma of {name}`Table.ChecksHold`, for every two tables: if the first satisfies
it, each row of the second is a row of the first, and the second has the same CHECK constraints
({name}`CatalogTable.allChecks`), the second satisfies it. The columns can differ in what the
CHECK constraints do not read. Proof sketch: each CHECK of the second is a CHECK of the first,
and holds on the same row. -/
theorem Table.ChecksHold.frame {table other : Table} (holds : table.ChecksHold)
    (rows : ∀ row ∈ other.rows, row ∈ table.rows) (checks : other.shape.allChecks = table.shape.allChecks) :
    other.ChecksHold :=
  fun row member check inChecks => holds row (rows row member) check (checks ▸ inChecks)

/-- A property of a table that behaves like the three atoms of this slice: what the proofs about
statements need of an atom that reads one row at a time. Three facts:
* a table without rows has it;
* a table with the same catalog entry as a table that has it, and a sublist of its rows, has it
  (a DELETE stores such a table);
* a table that passes the checks of a write ({name}`LiteralData.constraints`) has it, for every
  keys.

{lit}`Table.notNullAtom`, {lit}`Table.typesFitAtom` and {lit}`Table.checksHoldAtom` are the
instances. -/
structure RowLocalAtom (atom : Table → Prop) : Prop where
  /-- A table without rows has the property. -/
  empty : ∀ table, table.rows = [] → atom table
  /-- A table with the same entry and a sublist of the rows of a table that has the property has
  it. -/
  sublist : ∀ table other, atom table → other.shape = table.shape → other.rows.Sublist table.rows → atom other
  /-- A table that passes the checks of a write for some keys has the property. -/
  constraints : ∀ keys table, LiteralData.constraints keys table = true → atom table

/-- A {name}`RowLocalAtom` gives the facts of {name}`TableFacts` for the fact that ignores the catalog
and the position: the row engine keeps it. Proof sketch: the sublist and constraints facts of the
atom. -/
theorem RowLocalAtom.facts {atom : Table → Prop} (rowLocal : RowLocalAtom atom) :
    TableFacts fun _ _ table => atom table where
  sublist _ _ table other holds same sub := rowLocal.sublist table other holds same sub
  constraints _ _ table passed := rowLocal.constraints _ table passed

/-- "Not null" is a {name}`RowLocalAtom`. Proof sketch: no rows leave nothing to check; the frame
lemma gives the sublist; {name}`Table.constraints_iff` gives the writes. -/
theorem Table.notNullAtom : RowLocalAtom Table.NotNull where
  empty table none := fun row member => by simp [none] at member
  sublist _ _ notNull same sub := notNull.frame (fun _ member => sub.subset member) (by rw [same])
  constraints keys table passed := ((Table.constraints_iff keys table).mp passed).1

/-- "Types fit" is a {name}`RowLocalAtom`. Proof sketch: as {name}`Table.notNullAtom`, with
{name}`Table.TypesFit.frame`. -/
theorem Table.typesFitAtom : RowLocalAtom Table.TypesFit where
  empty table none := fun row member => by simp [none] at member
  sublist _ _ fits same sub := fits.frame (fun _ member => sub.subset member) (by rw [same])
  constraints keys table passed := ((Table.constraints_iff keys table).mp passed).2.1

/-- "Checks hold" is a {name}`RowLocalAtom`. Proof sketch: as {name}`Table.notNullAtom`, with
{name}`Table.ChecksHold.frame`. -/
theorem Table.checksHoldAtom : RowLocalAtom Table.ChecksHold where
  empty table none := fun row member => by simp [none] at member
  sublist _ _ holds same sub := holds.frame (fun _ member => sub.subset member) (by rw [same])
  constraints keys table passed := ((Table.constraints_iff keys table).mp passed).2.2.1

end Belay.Sqlite.Model
