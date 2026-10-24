import Belay.Sqlite.Model.AdmittedUpdateRows

set_option doc.verso true

/-! The table after an UPDATE and the atoms "rows wide", "rows stored" and "rows aliased" (ADR 0022, D3,
slice 4). {lit}`LiteralData.updated` keeps the rows that the filter does not select and changes the
others with {lit}`LiteralData.assign` and {lit}`LiteralData.movedRowid`, so the laws of
{lit}`AdmittedUpdateRows` for one row give the atoms for the table. "Rowids in range" is read from the
support check of the UPDATE instead. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every context, table, assignments and filter, each row of {name}`updated` is a row of the
table, or it is {name}`movedRowid` of {name}`assign` of a row of the table that the filter selects.
Proof sketch: the rows are the rows of the table, each replaced or kept by the filter. -/
theorem updated_rows_cases (context : Resolved.EvalContext) (table : Table) (assignments : List (Nat × Resolved.Expr))
    (filter : Option Resolved.Expr) :
    ∀ row ∈ (updated context table assignments filter).rows, row ∈ table.rows ∨
      ∃ old ∈ table.rows, selected context filter old = true ∧
        row = movedRowid table.shape.rowidAlias (assign context table.shape.columns assignments old) := by
  intro row member
  simp only [updated, List.mem_map] at member
  obtain ⟨old, oldMember, rfl⟩ := member
  by_cases chosen : selected context filter old = true
  · exact .inr ⟨old, oldMember, chosen, by simp [chosen]⟩
  · exact .inl (by simpa [chosen] using oldMember)

/-- For every context, table, assignments and filter: if the rows of the table are wide, the rows of
{name}`updated` are wide. Proof sketch: a changed row keeps the number of its cells
({name}`assignFrom_length`, {name}`movedRowid_values`). -/
theorem updated_wide {context : Resolved.EvalContext} {table : Table} {assignments : List (Nat × Resolved.Expr)}
    {filter : Option Resolved.Expr} (wide : table.RowsWide) : (updated context table assignments filter).RowsWide := by
  intro row member
  rcases updated_rows_cases context table assignments filter row member with old | ⟨old, oldMember, _, rfl⟩
  · exact wide row old
  · rw [movedRowid_values]
    exact (assignFrom_length context table.shape.columns assignments old.values old).trans (wide old oldMember)

/-- For every context, table, assignments and filter: if the rows of the table are stored, the rows of
{name}`updated` are stored. Proof sketch: a changed row is stored ({name}`assignFrom_stored`), and
{name}`movedRowid` keeps its cells. -/
theorem updated_stored {context : Resolved.EvalContext} {table : Table} {assignments : List (Nat × Resolved.Expr)}
    {filter : Option Resolved.Expr} (stored : table.RowsStored) : (updated context table assignments filter).RowsStored := by
  intro row member
  rcases updated_rows_cases context table assignments filter row member with old | ⟨old, oldMember, _, rfl⟩
  · exact stored row old
  · intro position column value atColumn atCell
    rw [movedRowid_values] at atCell
    exact assignFrom_stored context table.shape.columns assignments old.values (stored old oldMember) position column
      value atColumn atCell

/-- For every context, table, assignments and filter: if the rows of the table are aliased, the column of
the rowid alias is not generated, and no selected row has a refused rowid alias
({name}`updateMismatch` is false), the rows of {name}`updated` are aliased. Proof sketch: a changed row is
aliased by {name}`assign_aliased`. -/
theorem updated_aliased {context : Resolved.EvalContext} {table : Table} {assignments : List (Nat × Resolved.Expr)}
    {filter : Option Resolved.Expr} (aliased : table.RowsAliased)
    (ungenerated : ∀ position, table.shape.rowidAlias = some position →
      ∃ column, table.shape.columns[position]? = some column ∧ column.generated = none)
    (accepted : updateMismatch context table assignments filter = false) :
    (updated context table assignments filter).RowsAliased := by
  intro row member
  rcases updated_rows_cases context table assignments filter row member with old | ⟨old, oldMember, chosen, rfl⟩
  · exact aliased row old
  · exact assign_aliased (table := table) oldMember (aliased old oldMember) ungenerated accepted chosen

end LiteralData
end Belay.Sqlite.Model
