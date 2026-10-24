import Belay.Sqlite.Model.LiteralAdmittedRow
import Belay.Sqlite.Model.AdmittedAtomsExamples

set_option doc.verso true

/-! Examples of {lit}`LiteralData.rowAdmitted` (ADR 0022, slice 4, owner decision M), each checked by the
kernel: a row that is admitted, and one row for each of the four facts that it breaks. -/

namespace Belay.Sqlite.Model.LiteralAdmittedRowExamples

open Belay.Sqlite.Model AdmittedAtomsExamples

/-- The table {lit}`t(id INTEGER PRIMARY KEY, b TEXT)`: the alias is the cell 0. -/
def aliasedShape : CatalogTable :=
  { twoColumns with primaryKey := [0], rowidAlias := some 0 }

-- A row of the right width, in stored form, with the rowid in range: admitted.
example : LiteralData.rowAdmitted twoColumns { rowid := 1, values := [.integer 5, .text [97]] } = true := by
  decide +kernel
-- The alias cell is the rowid: admitted. A different integer is not.
example : LiteralData.rowAdmitted aliasedShape { rowid := 7, values := [.integer 7, .null] } = true := by
  decide +kernel
example : LiteralData.rowAdmitted aliasedShape { rowid := 7, values := [.integer 8, .null] } = false := by
  decide +kernel
-- The rowid 2 ^ 63 is out of range.
example : LiteralData.rowAdmitted twoColumns { rowid := 2 ^ 63, values := [.null, .null] } = false := by
  decide +kernel
-- A narrow row and a wide row are not admitted.
example : LiteralData.rowAdmitted twoColumns { rowid := 1, values := [.null] } = false := by decide +kernel
example : LiteralData.rowAdmitted twoColumns { rowid := 1, values := [.null, .null, .null] } = false := by
  decide +kernel
-- The text '5' in the INTEGER column is not in stored form: the column would store the integer 5.
example : LiteralData.rowAdmitted twoColumns { rowid := 1, values := [.text [53], .null] } = false := by
  decide +kernel

end Belay.Sqlite.Model.LiteralAdmittedRowExamples
