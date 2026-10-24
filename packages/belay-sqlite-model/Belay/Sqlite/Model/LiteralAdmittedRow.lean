import Belay.Sqlite.Model.LiteralData

set_option doc.verso true

/-! The test of a row that the row engine writes (ADR 0022, D3, slice 4, owner decision M of the
status file, finding 16). A row that fails the test is not written: the engine ends the statement as
not described. The test is one Boolean, and a lemma says that it holds exactly when the row has the
four facts that the Admitted atoms "rowids in range", "rows wide", "rows stored" and "rows aliased"
need of a row. -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- Whether a row that is written to a table with the catalog entry is admitted: its rowid is in the
signed 64-bit range ({name}`boundedInteger`), it has one cell for each column, each cell is in the
stored form of its column ({name}`storedForm`), and the cell of the rowid alias, when the entry has
one, is the integer rowid. -/
def rowAdmitted (shape : CatalogTable) (row : Row) : Bool :=
  boundedInteger row.rowid && row.values.length == shape.columns.length &&
    (shape.columns.zip row.values).all (fun (column, value) => storedForm column.affinity value) &&
    shape.rowidAlias.all fun position => row.values[position]? == some (.integer row.rowid)

/-- For every entry and row, {name}`rowAdmitted` is {lean}`true` exactly when the rowid is valid
({name}`validRowid`), the row has as many cells as the entry has columns, the row is
{name}`Row.Stored` for the columns, and the row is {name}`Row.Aliased` for the alias of the
entry. Proof sketch: each conjunct of the check is the fact in Boolean form; the zipped pairs are
the positions that have both a column and a cell. -/
theorem rowAdmitted_iff (shape : CatalogTable) (row : Row) :
    rowAdmitted shape row = true ↔ validRowid row.rowid ∧ row.values.length = shape.columns.length ∧
      row.Stored shape.columns ∧ row.Aliased shape.rowidAlias := by
  have stored : ((shape.columns.zip row.values).all fun (column, value) => storedForm column.affinity value) = true ↔
      row.Stored shape.columns := by
    simp only [List.all_eq_true, Row.Stored, storedForm, beq_iff_eq, List.mem_iff_getElem?, List.getElem?_zip_eq_some]
    constructor
    · intro all position column value found cell
      exact all (column, value) ⟨position, found, cell⟩
    · rintro every ⟨column, value⟩ ⟨position, found, cell⟩
      exact every position column value found cell
  have aliased : (shape.rowidAlias.all fun position => row.values[position]? == some (.integer row.rowid)) = true ↔
      row.Aliased shape.rowidAlias := by
    simp only [Row.Aliased]
    cases shape.rowidAlias <;> simp
  simp only [rowAdmitted, Bool.and_eq_true, beq_iff_eq, stored, aliased, boundedInteger, decide_eq_true_eq, validRowid]
  simp only [and_assoc]

end LiteralData
end Belay.Sqlite.Model
