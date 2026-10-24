import Belay.Sqlite.Model.AdmittedAtomsEngineExamples
import Belay.Sqlite.Model.AdmittedCatalogStatement
import Belay.Sqlite.Model.AdmittedRangeWideStatements
import Belay.Sqlite.Model.AdmittedShapedStatement
import Belay.Sqlite.Model.AdmittedStoredAliasedStatements

set_option doc.verso true

/-! Examples of the statement theorems of the Admitted atoms (ADR 0022, slice 4, part 2), each checked
by the kernel: {lit}`Database.RowsOnlyAt`, and the theorems of "rows shaped", "catalog supported" and
the four atoms that need the support check, applied to a statement, with a DROP whose
condition on the catalog fails. -/

namespace Belay.Sqlite.Model.AdmittedAtomsTheoremExamples

open Belay.Sqlite.Model AdmittedAtomsExamples AdmittedAtomsEngineExamples Resolution.Examples

/-- Write rules with the foreign key check on. -/
def someRules : Resolved.WriteRules := { depth := 1, keys := true }

-- A write that stores the rows of the table at its target is {name}`Database.RowsOnlyAt` the database.
example : emptyDatabase.RowsOnlyAt 0 (emptyDatabase.setRows 0 []) := .setRows (table := { shape := twoColumns, rows := [] }) rfl []
-- A write that fails keeps the database.
example : emptyDatabase.RowsOnlyAt 0 emptyDatabase := .inl rfl
-- A change of the rows at the index, which holds no table, is not allowed: the catalog position 1 is an index.
example : ¬ emptyDatabase.RowsOnlyAt 1 (emptyDatabase.setRows 1 [{ rowid := 1, values := [] }]) := by
  rintro (same | ⟨table, _, found, _⟩)
  · exact absurd (congrArg Database.rows same) (by decide +kernel)
  · have none : emptyDatabase.table 1 = none := by decide +kernel
    rw [none] at found
    cases found

-- The theorems of the four atoms that need the support check cover a statement with rules: a DROP of
-- the index with the rules {name}`someRules` is a write of the row engine.
example : (runStatement 0 {} [] (.drop [1] (some someRules)) emptyDatabase).effect.Satisfies Database.RowsWide :=
  runStatement_rowsWide 0 {} [] _ (by decide +kernel) (by decide +kernel)
example : (runStatement 0 {} [] (.drop [1] (some someRules)) emptyDatabase).effect.Satisfies Database.RowidsInRange :=
  runStatement_rowidsInRange 0 {} [] _ (by decide +kernel) (by decide +kernel)
-- BEGIN keeps the database shaped, with no condition on the connection or on the support check.
example : (runStatement 0 {} [] .begin emptyDatabase).effect.Satisfies Database.RowsShaped :=
  runStatement_rowsShaped 0 {} [] .begin emptyDatabase_shaped
-- DROP of the index keeps it shaped, and the catalog after it is valid, which the theorem of
-- "catalog supported" asks for.
example : (runStatement 0 {} [] (.drop [1] none) emptyDatabase).effect.Satisfies Database.RowsShaped :=
  runStatement_rowsShaped 0 {} [] _ emptyDatabase_shaped
example : (runStatement 0 {} [] (.drop [1] none) emptyDatabase).effect.Satisfies
    fun after => after.catalog.Valid defaults.limits :=
  runStatement_catalogSupported defaults.limits 0 {} [] _ (by decide +kernel) (by decide +kernel)
-- DROP of the table alone leaves an index without its table: its catalog is not valid, so the
-- condition of the theorem fails, and so does the conclusion (the statement succeeds).
example : ¬ ((.drop [0] none : Resolved.Statement).applyCatalog emptyDatabase.catalog).Valid defaults.limits := by
  decide +kernel
example : ¬ (effectDatabase (runStatement 0 {} [] (.drop [0] none) emptyDatabase).effect).catalog.Valid defaults.limits := by
  decide +kernel

end Belay.Sqlite.Model.AdmittedAtomsTheoremExamples
