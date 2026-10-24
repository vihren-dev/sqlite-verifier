import Belay.Sqlite.Model.KeysUniqueLookup
import Belay.Sqlite.Model.ValidityExamples

set_option doc.verso true

/-! Examples of the theorems of the atom "keys unique" (ADR 0022, slice 2), each checked by the
kernel: the lookup lemma for the partial unique index {lit}`accounts_live` of the user guide, and
the counterexamples that show that the conditions of ADD COLUMN and DROP are necessary. -/

namespace Belay.Sqlite.Model.KeysUniqueExamples

open Belay.Sqlite.Model Syntax
open Belay.Sqlite.Model.ValidityExamples (built withRows stored typed text textValue)

/-- The guide's accounts: {lit}`accounts (id INTEGER PRIMARY KEY, email TEXT NOT NULL,
deleted_at TEXT, UNIQUE (email, deleted_at))`, the partial unique index
{lit}`CREATE UNIQUE INDEX accounts_live ON accounts (email) WHERE deleted_at IS NULL`, one live
account and one deleted account for {lit}`'a@x'`. -/
def accounts : Database := built
  [.createTable (name! "accounts")
    [typed "id" (some "INTEGER") [.primaryKey false], typed "email" (some "TEXT") [.notNull],
     typed "deleted_at" (some "TEXT")] [.unique [name! "email", name! "deleted_at"]],
   .createIndex (name! "accounts_live") true (name! "accounts") [{ expression := ValidityExamples.name "email", descending := false }]
     (some (.isNull (ValidityExamples.name "deleted_at") false)),
   .insert (name! "accounts") (some [name! "email"]) [[text "a@x"]] [],
   .insert (name! "accounts") (some [name! "email", name! "deleted_at"]) [[text "a@x", text "2026-01-01"]] []]

/-- The table {lit}`accounts` of {name}`accounts`, or a table without columns and rows when the
script fails. -/
def accountsTable : Table := (accounts.table 0).getD { shape := { columns := [] }, rows := [] }

/-- The key of {lit}`accounts_live`: the last unique key of {lit}`accounts`
({name}`Catalog.uniqueKeys`). -/
def liveKey : UniqueKey := ((accounts.catalog.uniqueKeys 0 accountsTable.shape).getLast?).getD { terms := [] }

-- The script stores both rows; the key of the index reads `email` and has a filter.
example : accountsTable.rows.length = 2 ∧ accounts.table 0 = some accountsTable ∧ liveKey.terms.length = 1 ∧
    liveKey.filter.isSome := by decide +kernel

/-- The lookup lemma for {lit}`accounts_live`: for every probe row, at most one row of
{lit}`accounts` conflicts with it on the key of the index, so at most one live account has an
email. The facts that the lemma needs are checked by the kernel for this database. -/
theorem accounts_one_live (probe : Row) :
    (accountsTable.rows.filter fun row => LiteralData.keyEqual liveKey row probe).length ≤ 1 :=
  Database.KeysUnique.lookup (by decide +kernel : accounts.KeysUnique) (by decide +kernel : accounts.table 0 = some accountsTable)
    (by decide +kernel : liveKey ∈ accounts.catalog.uniqueKeys 0 accountsTable.shape) probe

-- A live probe for `'a@x'` conflicts with the live row and not with the deleted row.
example : (accountsTable.rows.filter fun row =>
    LiteralData.keyEqual liveKey row (stored 9 [.integer 9, textValue "a@x", .null])).length = 1 := by decide +kernel

/-- The column {lit}`c` without a type, which ADD COLUMN appends. -/
def columnC : CatalogColumn := { name := Identifier.ofString "c", declaredType := none }

/-- {lit}`CREATE TABLE w(a, b UNIQUE)` with two rows that have no cell for {lit}`b`. -/
def shortRows : Database :=
  withRows (built [.createTable (name! "w") [typed "a" none, typed "b" none [.unique]] []])
    [stored 1 [.integer 1], stored 2 [.integer 1]]

-- Without wide rows: the keys are unique before ADD COLUMN with the default 5, whose cell lands
-- at the position of `b` in both rows, and not after.
example : shortRows.KeysUnique ∧ ¬shortRows.RowsWide ∧ ¬(shortRows.addColumn 0 columnC (.integer 5)).KeysUnique := by
  decide +kernel

/-- The unique index on column 0 of the table at position 0 with the filter
{lit}`column1 = 5`, which reads the column at position 1. -/
def filterPastWidthIndex : CatalogIndex :=
  { table := 0, keys := [{ term := .column 0 }], unique := true,
    filter := some (.compare .eq none (.column 1) (.literal (.integer 5))) }

/-- A table {lit}`t(a)` with two equal rows and a unique index on {lit}`a` whose filter reads the
column at position 1, which the table does not have: a catalog that resolution does not give. -/
def filterPastWidth : Database :=
  { catalog := [{ name := name! "t", entry := .table { columns := [{ name := name! "a", declaredType := none }] } },
      { name := name! "i", entry := .index filterPastWidthIndex }],
    rows := [[stored 1 [.integer 1], stored 2 [.integer 1]], []] }

-- Without keys that read the old columns: the filter is NULL for both rows before ADD COLUMN with
-- the default 5, and true for both after, so the rows conflict.
example : filterPastWidth.KeysUnique ∧ filterPastWidth.RowsWide ∧
    ¬(filterPastWidth.addColumn 0 columnC (.integer 5)).KeysUnique := by decide +kernel

/-- The column {lit}`c` with {lit}`DEFAULT 5`. -/
def columnFive : CatalogColumn :=
  { columnC with defaultValue := some { form := .literal (.value (.integer 5)) (.integer 5), sourceText := "5" } }

/-- The table {lit}`t(a)` of {name}`filterPastWidth` with its two rows and without the index. -/
def tableOnly : Database :=
  { catalog := [{ name := name! "t", entry := .table { columns := [{ name := name! "a", declaredType := none }] } }],
    rows := [[stored 1 [.integer 1], stored 2 [.integer 1]]] }

-- A resolved statement need not give a catalog that resolution gives: `runStatement` runs
-- CREATE INDEX of the index of `filterPastWidth` as ready, and then ADD COLUMN with the
-- default 5 as ready, and the keys are no longer unique. A theorem over every resolved statement
-- needs a condition on the statements.
example : (runStatement 0 {} [] (.createIndex 1 (name! "i") filterPastWidthIndex) tableOnly).ready = true ∧
    effectDatabase (runStatement 0 {} [] (.createIndex 1 (name! "i") filterPastWidthIndex) tableOnly).effect =
      filterPastWidth ∧ (runStatement 0 {} [] (.addColumn 0 columnFive) filterPastWidth).ready = true ∧
    ¬(effectDatabase (runStatement 0 {} [] (.addColumn 0 columnFive) filterPastWidth).effect).KeysUnique := by
  decide +kernel

/-- The catalog {lit}`[t0, t1, i]` with the unique index {lit}`i` on {lit}`t0`, one row in
{lit}`t0` and two equal rows in {lit}`t1`. -/
def indexOnDropped : Database :=
  { catalog := [{ name := name! "t0", entry := .table { columns := [{ name := name! "a", declaredType := none }] } },
      { name := name! "t1", entry := .table { columns := [{ name := name! "a", declaredType := none }] } },
      { name := name! "i", entry := .index { table := 0, keys := [{ term := .column 0 }], unique := true } }],
    rows := [[stored 1 [.integer 1]], [stored 1 [.integer 1], stored 2 [.integer 1]], []] }

-- Without the condition of DROP: dropping `t0` and keeping `i` moves `i` to `t1`, whose rows
-- conflict on it.
example : indexOnDropped.KeysUnique ∧ ¬(indexOnDropped.drop [0]).KeysUnique := by decide +kernel

end Belay.Sqlite.Model.KeysUniqueExamples
