import Belay.Sqlite.Model.AdmittedEngineLaws
import Belay.Sqlite.Model.AdmittedAtomsExamples

set_option doc.verso true

/-! Examples of the laws of the row engine for the Admitted atoms (ADR 0022, slice 4, part 2), each
checked by the kernel: the two facts of {lit}`WriteLaws` (a DELETE stores a sublist, and a write stores a
table that passed the check) for "rows shaped", "catalog supported" and "rowids distinct". -/

namespace Belay.Sqlite.Model.AdmittedAtomsEngineExamples

open Belay.Sqlite.Model AdmittedAtomsExamples Resolution.Examples

/-- The catalog {lit}`indexedCatalog` (a table and an index) with an empty row list for each object. -/
def emptyDatabase : Database := { catalog := indexedCatalog, rows := [[], []] }

/-- The database {name}`emptyDatabase` has one row list for each object and none at the index. Proof sketch:
the position 0 has a table, the position 1 is the index with an empty row list, and later positions
have no row list. -/
theorem emptyDatabase_shaped : emptyDatabase.RowsShaped := by
  refine ⟨rfl, fun position absent => ?_⟩
  rcases position with _ | _ | position
  · exact absurd absent (by decide +kernel)
  · rfl
  · simp [emptyDatabase, List.getD_eq_getElem?_getD]

-- A DELETE at a position without a table (here past the end) keeps the database shaped: the sublist law.
example : (emptyDatabase.setRows 5 ((emptyDatabase.rows.getD 5 []).filter (·.rowid != 1))).RowsShaped :=
  rowsShapedLaws.sublist emptyDatabase 5 (fun rows => rows.filter (·.rowid != 1)) emptyDatabase_shaped
    fun _ => List.filter_sublist
-- A write at the table keeps it shaped: the write law, with a table that passed the check.
example : (emptyDatabase.setRows 0 []).RowsShaped :=
  rowsShapedLaws.write emptyDatabase 0 { shape := twoColumns, rows := [] } [] emptyDatabase_shaped (by decide +kernel)
    (by decide +kernel) nofun

-- The catalog stays valid after any write, because a write keeps the catalog.
example : (emptyDatabase.setRows 0 []).catalog.Valid defaults.limits :=
  (catalogSupportedLaws defaults.limits).write emptyDatabase 0 { shape := twoColumns, rows := [] } [] (by decide +kernel)
    (by decide +kernel) (by decide +kernel) nofun

-- "Rowids distinct": a table that passed the check of a write has distinct rowids.
example : ({ shape := twoColumns, rows := [{ rowid := 1, values := [.null, .null] }] } : Table).RowidsDistinct :=
  rowidsDistinctFacts.constraints indexedCatalog 0 _ (by decide +kernel)

end Belay.Sqlite.Model.AdmittedAtomsEngineExamples
