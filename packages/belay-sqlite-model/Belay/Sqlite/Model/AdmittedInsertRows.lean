import Belay.Sqlite.Model.AdmittedCellLaws
import Belay.Sqlite.Model.DatabaseFacts
import Belay.Sqlite.Model.RowLocalWrites

set_option doc.verso true

/-! The rows of a plain INSERT (ADR 0022, D3, slice 4): what {lit}`LiteralData.inserted` keeps of
the atoms "rows wide", "rows stored" and "rows aliased". The table after the INSERT has the rows of
the table and one new row for each supplied row of cells. The cells of a new row are
{lit}`LiteralData.newCells` of the supplied cells and the rowid of the new row, so the cell laws of
{lit}`AdmittedCellLaws` give the atoms. "Rowids in range" is not here: the support check of the
INSERT reads it from the table after the INSERT. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every table and supplied rows, each row of {name}`inserted` is a row of the table, or its
cells are {name}`newCells` of some supplied row of cells and the rowid of the row. Proof sketch:
induction on the supplied rows; one {name}`insertRow` appends a row of that form to the rows and
changes no other part of the table, and {name}`newCells` reads only the entry of the table. -/
theorem inserted_rows_cases (table : Table) (rows : List (List Value)) :
    ∀ row ∈ (inserted table rows).rows,
      row ∈ table.rows ∨ ∃ values ∈ rows, row.values = newCells table values row.rowid := by
  induction rows generalizing table with
  | nil => intro row member; exact .inl member
  | cons first rest induction =>
    intro row member
    rcases induction (insertRow table first) row member with old | ⟨values, supplied, cells⟩
    · rcases List.mem_append.mp old with old | appended
      · exact .inl old
      · obtain rfl := List.mem_singleton.mp appended
        exact .inr ⟨first, List.mem_cons_self .., rfl⟩
    · exact .inr ⟨values, List.mem_cons_of_mem _ supplied, cells⟩

/-- For every table and supplied rows: if the rows of the table are wide, and each supplied row has
one cell for each column, the rows of {name}`inserted` are wide. Proof sketch: a new row has as many
cells as the supplied row ({name}`newCells_length`). -/
theorem inserted_wide {table : Table} {rows : List (List Value)} (wide : table.RowsWide)
    (supplied : ∀ values ∈ rows, values.length = table.shape.columns.length) : (inserted table rows).RowsWide := by
  intro row member
  rw [inserted_shape]
  rcases inserted_rows_cases table rows row member with old | ⟨values, mem, cells⟩
  · exact wide row old
  · rw [cells, newCells_length]
    exact supplied values mem

/-- For every table and supplied rows: if the rows of the table are stored, the table passes
{name}`aliasReady`, and each supplied row is stored for the columns, the rows of {name}`inserted`
are stored. Proof sketch: {name}`newCells_stored` for a new row. -/
theorem inserted_stored {table : Table} {rows : List (List Value)} (stored : table.RowsStored)
    (ready : aliasReady table.shape = true)
    (supplied : ∀ values ∈ rows, ∀ (position : Nat) (column : CatalogColumn) (value : Value),
      table.shape.columns[position]? = some column → values[position]? = some value →
        Value.store column.affinity value = value) :
    (inserted table rows).RowsStored := by
  intro row member
  rw [inserted_shape]
  rcases inserted_rows_cases table rows row member with old | ⟨values, mem, cells⟩
  · exact stored row old
  · intro position column value atColumn atCell
    rw [cells] at atCell
    exact newCells_stored ready (supplied values mem) position column value atColumn atCell

/-- For every table and supplied rows: if the rows of the table are aliased, the column of the rowid
alias is not generated, and each supplied row has one cell for each column, the rows of
{name}`inserted` are aliased. Proof sketch: {name}`newCells_aliased` for a new row. -/
theorem inserted_aliased {table : Table} {rows : List (List Value)} (aliased : table.RowsAliased)
    (ungenerated : ∀ position, table.shape.rowidAlias = some position →
      ∃ column, table.shape.columns[position]? = some column ∧ column.generated = none)
    (supplied : ∀ values ∈ rows, values.length = table.shape.columns.length) :
    (inserted table rows).RowsAliased := by
  intro row member
  rw [inserted_shape]
  rcases inserted_rows_cases table rows row member with old | ⟨values, mem, cells⟩
  · exact aliased row old
  · intro position alias
    rw [cells]
    exact newCells_aliased ungenerated (supplied values mem) position alias

end LiteralData
end Belay.Sqlite.Model
