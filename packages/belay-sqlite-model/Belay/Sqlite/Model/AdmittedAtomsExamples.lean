import Belay.Sqlite.Model.ModelLaws
import Belay.Sqlite.Model.CatalogValidSet
import Belay.Sqlite.Model.CatalogValidDrop
import Belay.Sqlite.Model.Resolution.Examples

set_option doc.verso true

/-! Examples of the theorems of the Admitted atoms (ADR 0022, slice 4), each checked by the
kernel. Part 1: the conditions of {lit}`CatalogTable.supported` that this slice adds (a key that
names a column twice, the rowid alias, and the columns that a CHECK reads), each with a table that
meets it and a table that breaks it; and the laws of {lit}`Catalog.Valid` for ADD COLUMN and DROP,
with a drop that breaks the closure of {lit}`Catalog.DropClosed`. -/

namespace Belay.Sqlite.Model.AdmittedAtomsExamples

open Belay.Sqlite.Model Resolution.Examples

/-- The table {lit}`t(a INTEGER, b TEXT)` before its keys. -/
def twoColumns : CatalogTable :=
  { columns := [{ name := name! "a", declaredType := some "INTEGER" }, { name := name! "b", declaredType := some "TEXT" }] }

/-- A generated column. -/
def generatedColumn : CatalogColumn :=
  { name := name! "g", declaredType := some "INTEGER", generated := some { expression := .literal .null, stored := false } }

/-- A CHECK that reads the column at the position. -/
def readsColumn (position : Nat) : CheckConstraint := { condition := .column position, label := "" }

-- A key may name a column twice, as SQLite accepts `PRIMARY KEY(a, a)` and `UNIQUE(a, a)`.
example : twoColumns.supported defaults.limits = true := by decide +kernel
example : { twoColumns with primaryKey := [0, 0] }.supported defaults.limits = true := by decide +kernel
example : { twoColumns with uniqueKeys := [[1, 1]] }.supported defaults.limits = true := by decide +kernel
-- A key still needs a column, and every column of the key is a column of the table.
example : { twoColumns with uniqueKeys := [[]] }.supported defaults.limits = false := by decide +kernel
example : { twoColumns with primaryKey := [0, 2] }.supported defaults.limits = false := by decide +kernel

-- The alias is the whole primary key, a column of INTEGER affinity that is not generated, in a
-- table with a rowid.
example : { twoColumns with primaryKey := [0], rowidAlias := some 0 }.supported defaults.limits = true := by
  decide +kernel
example : { twoColumns with rowidAlias := some 0 }.supported defaults.limits = false := by decide +kernel
example : { twoColumns with primaryKey := [1], rowidAlias := some 1 }.supported defaults.limits = false := by
  decide +kernel
example : { twoColumns with primaryKey := [0, 1], rowidAlias := some 0 }.supported defaults.limits = false := by
  decide +kernel
example : { twoColumns with primaryKey := [0], rowidAlias := some 0, withoutRowid := true }.supported
    defaults.limits = false := by decide +kernel
example : { twoColumns with columns := twoColumns.columns ++ [generatedColumn], primaryKey := [2], rowidAlias := some 2 }.supported
    defaults.limits = false := by decide +kernel
example : { twoColumns with primaryKey := [5], rowidAlias := some 5 }.supported defaults.limits = false := by
  decide +kernel
example : ({ columns := [], primaryKey := [0], rowidAlias := some 0 } : CatalogTable).supported defaults.limits = false := by
  decide +kernel

-- The alias condition alone refuses an alias whose column is missing.
example : ({ columns := [], primaryKey := [0], rowidAlias := some 0 } : CatalogTable).aliasSupported = false := by
  decide +kernel
example : { twoColumns with primaryKey := [5], rowidAlias := some 5 }.aliasSupported = false := by decide +kernel

-- A CHECK of the table or of a column reads only columns of the table.
example : { twoColumns with checks := [readsColumn 1] }.supported defaults.limits = true := by decide +kernel
example : { twoColumns with checks := [readsColumn 2] }.supported defaults.limits = false := by decide +kernel
example : { twoColumns with columns := [{ name := name! "a", declaredType := none, checks := [readsColumn 2] }] }.supported
    defaults.limits = false := by decide +kernel
example : { twoColumns with columns := [{ name := name! "a", declaredType := none, checks := [readsColumn 0] }] }.supported
    defaults.limits = true := by decide +kernel

-- The facts of `CatalogTable.supported` are an equivalent form of the check.
example : twoColumns.SupportedFacts defaults.limits := (CatalogTable.supported_iff _ _).mp (by decide +kernel)

/-- {lit}`t(a INTEGER, b TEXT)` and the unique index {lit}`i` on {lit}`a`. -/
def indexedCatalog : Catalog :=
  [{ name := name! "t", entry := .table twoColumns },
   { name := name! "i", entry := .index { table := 0, keys := [{ term := .column 0 }], unique := true } }]

example : indexedCatalog.Valid defaults.limits := by decide +kernel

-- A drop of the index, or of the table with its index, keeps the catalog valid; it meets the closure.
example : (indexedCatalog.drop [1]).Valid defaults.limits := by decide +kernel
example : (indexedCatalog.drop [0, 1]).Valid defaults.limits := by decide +kernel
example : indexedCatalog.DropClosed [0, 1] := by
  refine ⟨fun place object index found entry kept => ?_, fun place object trigger found entry kept => ?_⟩
  · rcases place with _ | _ | place <;> simp_all [indexedCatalog]
  · rcases place with _ | _ | place <;> simp_all [indexedCatalog]
-- A drop of the table alone keeps an index without its table: the catalog is not valid and the
-- closure fails, because the kept index at position 1 names the dropped table at position 0.
example : ¬ (indexedCatalog.drop [0]).Valid defaults.limits := by decide +kernel
example : ¬ indexedCatalog.DropClosed [0] := fun closed =>
  absurd (closed.1 1 _ _ rfl rfl (by decide)) (by decide)

-- ADD COLUMN of `c REAL` to the table keeps the catalog valid ({name}`Catalog.Valid.addColumn`).
example : (indexedCatalog.addColumn 0 { name := name! "c", declaredType := some "REAL" }).Valid defaults.limits :=
  Catalog.Valid.addColumn (by decide +kernel) rfl _ (by intro object found; cases found; decide) (by decide +kernel)

end Belay.Sqlite.Model.AdmittedAtomsExamples
