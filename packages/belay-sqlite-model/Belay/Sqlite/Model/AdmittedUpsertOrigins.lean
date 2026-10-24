import Belay.Sqlite.Model.AdmittedUpsertSummary

set_option doc.verso true

/-! The cells of an upsert row and the atoms "rows wide", "rows stored" and "rows aliased" (ADR 0022,
D3, slice 4). A row of the table after an upsert row has one of three origins
({lit}`LiteralData.UpsertOrigin`): a row of the table, the proposed row, or the changed row of a
{lit}`DO UPDATE`. The laws of {lit}`AdmittedCellLaws` and {lit}`AdmittedUpdateRows` give each atom for
each origin. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every context, clauses, table, supplied cells and row: if the rows of the table are wide, the
supplied cells have one cell for each column, and the row comes from the table, the proposed row or a
{lit}`DO UPDATE` ({name}`UpsertOrigin`), the row is wide. Proof sketch: the proposed row has the
cells of {name}`newCells` ({name}`newCells_length`); a changed row keeps the width of the row that it
changes ({name}`assignFrom_length`, {name}`movedRowid_values`). -/
theorem upsertOrigin_wide {context : Resolved.EvalContext} {clauses : List Resolved.ConflictClause} {table : Table}
    {values : List Value} {row : Row} (wide : table.RowsWide) (supplied : values.length = table.shape.columns.length)
    (origin : UpsertOrigin context clauses table (proposedRow table values) row) :
    row.values.length = table.shape.columns.length := by
  rcases origin with old | rfl | ⟨existing, member, assignments, _, rfl, _⟩
  · exact wide row old
  · rw [proposedRow, newCells_length]
    exact supplied
  · rw [movedRowid_values, assignFrom_length]
    exact wide existing member

/-- For every context, clauses, table, supplied cells and row: if the rows of the table are stored, the
table passes {name}`aliasReady`, the supplied cells are stored for the columns, and the row comes from the
table, the proposed row or a {lit}`DO UPDATE` ({name}`UpsertOrigin`), the row is stored. Proof sketch: the
proposed row has the cells of {name}`newCells` ({name}`newCells_stored`); a changed row is stored
({name}`assignFrom_stored`), and {name}`movedRowid` keeps its cells. -/
theorem upsertOrigin_stored {context : Resolved.EvalContext} {clauses : List Resolved.ConflictClause} {table : Table}
    {values : List Value} {row : Row} (stored : table.RowsStored) (ready : aliasReady table.shape = true)
    (supplied : ∀ (position : Nat) (column : CatalogColumn) (value : Value),
      table.shape.columns[position]? = some column → values[position]? = some value →
        Value.store column.affinity value = value)
    (origin : UpsertOrigin context clauses table (proposedRow table values) row) :
    row.Stored table.shape.columns := by
  rcases origin with old | rfl | ⟨existing, member, assignments, _, rfl, _⟩
  · exact stored row old
  · intro position column value atColumn atCell
    rw [proposedRow] at atCell
    exact newCells_stored ready supplied position column value atColumn atCell
  · intro position column value atColumn atCell
    rw [movedRowid_values] at atCell
    exact assignFrom_stored context table.shape.columns assignments (existing.values ++ (proposedRow table values).values)
      (stored existing member) position column value atColumn atCell

/-- For every context, clauses, table, supplied cells and row: if the rows of the table are aliased, the
column of the rowid alias is not generated, the supplied cells have one cell for each column, and the row
comes from the table, the proposed row or a {lit}`DO UPDATE` ({name}`UpsertOrigin`), the row is aliased.
Proof sketch: the proposed row has the rowid of its alias cell ({name}`newCells_aliased`); a changed row
has no refused alias cell, so {name}`movedRowid_aliased_of_accepted` applies. -/
theorem upsertOrigin_aliased {context : Resolved.EvalContext} {clauses : List Resolved.ConflictClause} {table : Table}
    {values : List Value} {row : Row} (aliased : table.RowsAliased)
    (ungenerated : ∀ position, table.shape.rowidAlias = some position →
      ∃ column, table.shape.columns[position]? = some column ∧ column.generated = none)
    (supplied : values.length = table.shape.columns.length)
    (origin : UpsertOrigin context clauses table (proposedRow table values) row) :
    row.Aliased table.shape.rowidAlias := by
  rcases origin with old | rfl | ⟨existing, member, assignments, _, rfl, accepted⟩
  · exact aliased row old
  · intro position alias
    rw [proposedRow]
    exact newCells_aliased ungenerated supplied position alias
  · exact movedRowid_aliased_of_accepted _ _ accepted

end LiteralData
end Belay.Sqlite.Model
