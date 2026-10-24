import Belay.Sqlite.Model.AdmittedAtomFrames
import Belay.Sqlite.Model.AdmittedCellLaws

set_option doc.verso true

/-! Examples of the statement theorems of the Admitted atoms (ADR 0022, slice 4, part 2), each
checked by the kernel: the frame lemmas of the table atoms and the cells of a written row. -/

namespace Belay.Sqlite.Model.AdmittedAtomsStatementExamples

open Belay.Sqlite.Model

/-- The column {lit}`a INTEGER`. -/
def columnA : CatalogColumn := { name := Identifier.ofString "a", declaredType := some "INTEGER" }

/-- The column {lit}`b TEXT`. -/
def columnB : CatalogColumn := { name := Identifier.ofString "b", declaredType := some "TEXT" }

/-- A table {lit}`t(a INTEGER)` with the rows of the rowids 1 and 2. -/
def twoRows : Table :=
  { shape := { columns := [columnA] }, rows := [{ rowid := 1, values := [.integer 1] }, { rowid := 2, values := [.integer 2] }] }

/-- The table {name}`twoRows` with its first row twice: its rows are rows of {name}`twoRows`, and not a sublist. -/
def repeatedRow : Table :=
  { twoRows with rows := [{ rowid := 1, values := [.integer 1] }, { rowid := 1, values := [.integer 1] }] }

/-- The table {name}`twoRows` has distinct rowids: the rowids are 1 and 2. Proof sketch: the kernel
decides {lean}`List.Nodup` of the two rowids. -/
theorem twoRows_distinct : twoRows.RowidsDistinct := by unfold Table.RowidsDistinct; decide +kernel
-- "Rowids distinct" needs a sublist: the rows of the repeated table are rows of the table, which has
-- distinct rowids, and the repeated table does not.
example : ¬ repeatedRow.RowidsDistinct := by unfold Table.RowidsDistinct; decide +kernel
example : ∀ row ∈ repeatedRow.rows, row ∈ twoRows.rows := by decide +kernel
-- A sublist keeps the atom (the frame lemma applies to the table with its second row removed).
example : ({ twoRows with rows := [{ rowid := 1, values := [.integer 1] }] } : Table).RowidsDistinct :=
  Table.RowidsDistinct.frame (table := twoRows) twoRows_distinct
    (.cons_cons _ (List.nil_sublist _))

-- The instances of the five table atoms use the same two facts: the table without rows has the atom.
example : ({ twoRows with rows := [] } : Table).RowsWide := Table.rowsWideAtom.empty _ rfl
example : ({ twoRows with rows := [] } : Table).RowsAliased := Table.rowsAliasedAtom.empty _ rfl

/-- The columns {lit}`a INTEGER, b TEXT`, none generated. -/
def plainColumns : List CatalogColumn := [columnA, columnB]

-- A table without generated columns keeps the supplied cells, and a NULL alias cell takes the new rowid.
example : LiteralData.generatedCells plainColumns [.integer 1, .text [97]] = [.integer 1, .text [97]] := by
  decide +kernel
example : (LiteralData.newCells { twoRows with shape := { columns := plainColumns, rowidAlias := some 0 } }
    [.null, .text [97]] 7) = [.integer 7, .text [97]] := by decide +kernel

end Belay.Sqlite.Model.AdmittedAtomsStatementExamples
