import Belay.Sqlite.Model.RowLocalAddColumnTheorems
import Belay.Sqlite.Model.ValidityExamples

set_option doc.verso true

/-! Examples of the conditions of ADD COLUMN for the atoms "not null", "types fit" and "checks
hold" (ADR 0022, slice 3), each checked by the kernel: for each condition, a database that
satisfies the atom, and meets the other conditions, and a resolved ADD COLUMN that the model runs
({lit}`StatementRun.ready`), after which the atom fails. So each condition is necessary. The
databases are literals, because the resolver refuses these statements or no script builds the
rows. -/

namespace Belay.Sqlite.Model.RowLocalExamples

open Belay.Sqlite.Model Syntax
open Belay.Sqlite.Model.ValidityExamples (stored textValue)

/-- A column without a type, a default or constraints. -/
def plain (column : String) : CatalogColumn := { name := Identifier.ofString column, declaredType := none }

/-- The condition {lit}`column1 > 0`, which reads the column at position 1. -/
def secondPositive : CheckConstraint :=
  { condition := .compare .gt none (.column 1) (.literal (.integer 0)), label := "column1 > 0" }

/-- The default {lit}`DEFAULT -1`. -/
def minusOne : ColumnDefault := { form := .literal (.value (.integer (-1))) (.integer (-1)), sourceText := "-1" }

/-- The effect of ADD COLUMN of the column at the table at position 0: the database after it. -/
def afterAdd (database : Database) (column : CatalogColumn) : Database :=
  effectDatabase (runStatement 0 {} [] (.addColumn 0 column) database).effect

/-- The object that names the table {lit}`t` with the entry. -/
def tableT (shape : CatalogTable) : CatalogObject := { name := name! "t", entry := .table shape }

/-- {lit}`CREATE TABLE t(a, b NOT NULL)` with the row {lit}`[1]`, which has no cell for {lit}`b`. -/
def shortNotNull : Database :=
  { catalog := [tableT { columns := [plain "a", { (plain "b") with notNull := true }] }],
    rows := [[stored 1 [.integer 1]]] }

-- Without wide rows, "not null" fails: ADD COLUMN {lit}`c` without a default puts NULL at the
-- position of {lit}`b`.
example : shortNotNull.NotNull ∧ ¬shortNotNull.RowsWide ∧ (runStatement 0 {} [] (.addColumn 0 (plain "c")) shortNotNull).ready = true ∧
    ¬(afterAdd shortNotNull (plain "c")).NotNull := by decide +kernel

/-- A {lit}`STRICT` table {lit}`t(a INTEGER, b INTEGER)` with the row {lit}`[1]`. -/
def shortStrict : Database :=
  let integer : CatalogColumn := { (plain "a") with declaredType := some "INTEGER", strictType := some .integer }
  { catalog := [tableT { columns := [integer, { integer with name := Identifier.ofString "b" }], strict := true }],
    rows := [[stored 1 [.integer 1]]] }

/-- The default {lit}`DEFAULT 'x'`. -/
def textDefault : Option ColumnDefault :=
  some { form := .literal (.value (textValue "x")) (textValue "x"), sourceText := "'x'" }

/-- The column {lit}`c TEXT DEFAULT 'x'`. -/
def textColumn : CatalogColumn :=
  { (plain "c") with declaredType := some "TEXT", strictType := some .text, defaultValue := textDefault }

-- Without wide rows, "types fit" fails: the text default lands at the position of {lit}`b`.
example : shortStrict.TypesFit ∧ ¬shortStrict.RowsWide ∧ strictDefaultFits textColumn = true ∧
    (runStatement 0 {} [] (.addColumn 0 textColumn) shortStrict).ready = true ∧
    ¬(afterAdd shortStrict textColumn).TypesFit := by decide +kernel

/-- {lit}`CREATE TABLE t(a, b CHECK (b > 0))` with the row {lit}`[1]`; the missing cell reads as
NULL, which passes. -/
def shortCheck : Database :=
  { catalog := [tableT { columns := [plain "a", { (plain "b") with checks := [{ secondPositive with label := "b > 0" }] }] }],
    rows := [[stored 1 [.integer 1]]] }

/-- The column {lit}`c DEFAULT -1`. -/
def minusColumn : CatalogColumn := { (plain "c") with defaultValue := some minusOne }

-- Without wide rows, "checks hold" fails: the default {lit}`-1` lands at the position of {lit}`b`.
example : shortCheck.ChecksHold ∧ ¬shortCheck.RowsWide ∧ (runStatement 0 {} [] (.addColumn 0 minusColumn) shortCheck).ready = true ∧
    ¬(afterAdd shortCheck minusColumn).ChecksHold := by decide +kernel

/-- {lit}`CREATE TABLE t(a)` with the row {lit}`[1]` and the CHECK {lit}`column1 > 0` of a column
that the table does not have: a catalog that resolution does not give. -/
def checkPastWidth : Database :=
  { catalog := [tableT { columns := [plain "a"], checks := [secondPositive] }],
    rows := [[stored 1 [.integer 1]]] }

-- A CHECK that reads past the width, "checks hold" fails: before, column 1 reads NULL and passes;
-- after ADD COLUMN {lit}`b DEFAULT -1` it reads -1.
example : checkPastWidth.ChecksHold ∧ checkPastWidth.RowsWide ∧
    secondPositive.condition.readsBelow 1 = false ∧
    (runStatement 0 {} [] (.addColumn 0 { minusColumn with name := Identifier.ofString "b" }) checkPastWidth).ready = true ∧
    ¬(afterAdd checkPastWidth { minusColumn with name := Identifier.ofString "b" }).ChecksHold := by decide +kernel

/-- A {lit}`STRICT` table {lit}`t(a INTEGER)` with the row {lit}`[1]`. -/
def strictOne : Database :=
  { catalog := [tableT
      { columns := [{ (plain "a") with declaredType := some "INTEGER", strictType := some .integer }], strict := true }],
    rows := [[stored 1 [.integer 1]]] }

/-- The column {lit}`b INTEGER DEFAULT 'x'` of a {lit}`STRICT` table, which the resolver refuses
({lit}`add-column-strict-type`). -/
def integerText : CatalogColumn :=
  { (plain "b") with declaredType := some "INTEGER", strictType := some .integer, defaultValue := textDefault }

-- A default that does not fit the strict type, "types fit" fails: a TEXT cell in an INTEGER column.
example : strictOne.TypesFit ∧ strictOne.RowsWide ∧ strictDefaultFits integerText = false ∧
    (runStatement 0 {} [] (.addColumn 0 integerText) strictOne).ready = true ∧
    ¬(afterAdd strictOne integerText).TypesFit := by decide +kernel

end Belay.Sqlite.Model.RowLocalExamples
