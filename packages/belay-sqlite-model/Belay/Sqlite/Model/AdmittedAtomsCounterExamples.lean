import Belay.Sqlite.Model.AdmittedAtomsTheoremExamples

set_option doc.verso true

/-! Counterexamples to the statement theorems of the Admitted atoms (ADR 0022, slice 4, part 2), each
checked by the kernel. Each one runs a plain INSERT on a database that satisfies the atom, and the
atom fails after the statement. They show what the hypotheses of the theorems keep out:
* an INSERT after the largest rowid (the run is not ready), against "rowids in range";
* a cell that is not in stored form, against "rows stored";
* a row with fewer cells than columns, against "rows wide";
* a rowid alias column of TEXT affinity (the run is not ready), against "rows stored";
* a rowid alias column that is generated (the run is ready; the catalog is not valid), against
  "rows aliased". -/

namespace Belay.Sqlite.Model.AdmittedAtomsCounterExamples

open Belay.Sqlite.Model

/-- The database with the table at position 0 and nothing else. -/
def oneTable (table : Table) : Database := .ofTables [(Identifier.ofString "t", table)]

/-- The table of {name}`oneTable` at position 0. Proof sketch: by computation. -/
theorem oneTable_table_zero (table : Table) : (oneTable table).table 0 = some table := rfl

/-- No table of {name}`oneTable` is at a position after 0. Proof sketch: the catalog has one entry. -/
theorem oneTable_table_succ (table : Table) (position : Nat) : (oneTable table).table (position + 1) = none := by
  simp [oneTable, Database.ofTables, Database.table, Catalog.tableAt]

/-- For every atom of tables and table that has it, every table of {name}`oneTable` of the table has it.
Proof sketch: position 0 holds the table, and no other position holds a table. -/
theorem oneTable_every {atom : Table → Prop} {table : Table} (holds : atom table) :
    (oneTable table).EveryTable fun _ other => atom other := by
  intro position other found
  rcases position with _ | position
  · rw [oneTable_table_zero] at found
    cases found
    exact holds
  · rw [oneTable_table_succ] at found
    cases found

/-- For every effect, database after and atom: if the effect is a success with the database after, and
the database after does not satisfy the atom, the effect does not satisfy it ({name}`Effect.Satisfies`).
Proof sketch: a success is one of the databases that the effect keeps. -/
theorem not_satisfies_of_ok {effect : Effect} {after : Database} {atom : Database → Prop}
    (ok : effect = .ok after) (broken : ¬ atom after) : ¬ effect.Satisfies atom :=
  fun satisfies => broken (satisfies after (.inl ok))

/-- The column {lit}`a INTEGER`. -/
def columnA : CatalogColumn := { name := Identifier.ofString "a", declaredType := some "INTEGER" }

/-- The table {lit}`t(a INTEGER)`, without rows. -/
def emptyTable : Table := { shape := { columns := [columnA] }, rows := [] }

/-- The table {lit}`t(a INTEGER)` with one row at the largest rowid, {lit}`2 ^ 63 - 1`. -/
def largestRowidTable : Table :=
  { emptyTable with rows := [{ rowid := 2 ^ 63 - 1, values := [.integer 1] }] }

/-- The INSERT of a row of one value, {lit}`INSERT INTO t VALUES (v)`, with the given cells. -/
def insertCells (cells : List Resolved.Cell) : Resolved.Statement := .insert 0 [cells] []

-- "Rowids in range": the INSERT after the largest rowid succeeds with the rowid 2 ^ 63, which is out of
-- range. The run is not ready, so the theorem `runStatement_rowidsInRange` does not apply.
example : (oneTable largestRowidTable).RowidsInRange :=
  oneTable_every fun row member => by
    simp only [largestRowidTable, List.mem_singleton] at member
    subst member
    exact ⟨by decide, by decide⟩
example : (runStatement 0 {} [] (insertCells [.value (.integer 2)]) (oneTable largestRowidTable)).ready = false := by
  decide +kernel
example : ¬ (runStatement 0 {} [] (insertCells [.value (.integer 2)]) (oneTable largestRowidTable)).effect.Satisfies
    Database.RowidsInRange := by
  refine not_satisfies_of_ok (after := (oneTable largestRowidTable).setRows 0
    [{ rowid := 2 ^ 63 - 1, values := [.integer 1] }, { rowid := 2 ^ 63, values := [.integer 2] }]) (by rfl) ?_
  intro inRange
  have row := inRange 0 { emptyTable with rows := [{ rowid := 2 ^ 63 - 1, values := [.integer 1] },
    { rowid := 2 ^ 63, values := [.integer 2] }] } rfl { rowid := 2 ^ 63, values := [.integer 2] } (by decide +kernel)
  exact absurd row.2 (by decide)

-- "Rows stored": a text cell for an INTEGER column that is not the stored form of its value.
example : (oneTable emptyTable).RowsStored := oneTable_every fun row member => by simp [emptyTable] at member
example : (runStatement 0 {} [] (insertCells [.value (.text [53])]) (oneTable emptyTable)).ready = false := by
  decide +kernel
example : ¬ (runStatement 0 {} [] (insertCells [.value (.text [53])]) (oneTable emptyTable)).effect.Satisfies
    Database.RowsStored := by
  refine not_satisfies_of_ok (after := (oneTable emptyTable).setRows 0 [{ rowid := 1, values := [.text [53]] }])
    (by rfl) ?_
  intro stored
  have cell := stored 0 { emptyTable with rows := [{ rowid := 1, values := [.text [53]] }] } rfl
    { rowid := 1, values := [.text [53]] } (by decide +kernel) 0 columnA (.text [53]) rfl rfl
  exact absurd cell (by decide +kernel)

-- "Rows wide": a row of no cell for a table of one column.
example : (oneTable emptyTable).RowsWide := oneTable_every fun row member => by simp [emptyTable] at member
example : (runStatement 0 {} [] (insertCells []) (oneTable emptyTable)).ready = false := by decide +kernel
example : ¬ (runStatement 0 {} [] (insertCells []) (oneTable emptyTable)).effect.Satisfies Database.RowsWide := by
  refine not_satisfies_of_ok (after := (oneTable emptyTable).setRows 0 [{ rowid := 1, values := [] }]) (by rfl) ?_
  intro wide
  have width := wide 0 { emptyTable with rows := [{ rowid := 1, values := [] }] } rfl { rowid := 1, values := [] }
    (by decide +kernel)
  exact absurd width (by decide)

/-- The column {lit}`a TEXT`. -/
def columnText : CatalogColumn := { name := Identifier.ofString "a", declaredType := some "TEXT" }

/-- The table {lit}`t(a TEXT PRIMARY KEY)` that a Lean user can build with the column as a rowid alias. The
catalog of a table that {name}`Catalog.Valid` accepts gives the alias INTEGER affinity. -/
def textAliasTable : Table :=
  { shape := { columns := [columnText], primaryKey := [0], rowidAlias := some 0 }, rows := [] }

-- A rowid alias of TEXT affinity: the alias cell is the integer rowid, which TEXT affinity does not
-- store. The run is not ready (`aliasReady` fails), and the INSERT succeeds with the unstored cell.
example : (runStatement 0 {} [] (insertCells [.value .null]) (oneTable textAliasTable)).ready = false := by
  decide +kernel
example : ¬ (runStatement 0 {} [] (insertCells [.value .null]) (oneTable textAliasTable)).effect.Satisfies
    Database.RowsStored := by
  refine not_satisfies_of_ok (after := (oneTable textAliasTable).setRows 0 [{ rowid := 1, values := [.integer 1] }])
    (by rfl) ?_
  intro stored
  have cell := stored 0 { textAliasTable with rows := [{ rowid := 1, values := [.integer 1] }] } rfl
    { rowid := 1, values := [.integer 1] } (by decide +kernel) 0 columnText (.integer 1) rfl rfl
  exact absurd cell (by decide +kernel)

/-- The column {lit}`g INTEGER` that is generated. -/
def generatedColumn : CatalogColumn :=
  { name := Identifier.ofString "g", declaredType := some "INTEGER",
    generated := some { expression := .literal .null, stored := false } }

/-- The table {lit}`t(g INTEGER PRIMARY KEY)` with a generated column as the rowid alias: a Lean user
can build it, and {name}`Catalog.Valid` refuses it. -/
def generatedAliasTable : Table :=
  { shape := { columns := [generatedColumn], primaryKey := [0], rowidAlias := some 0 }, rows := [] }

-- A generated rowid alias: the generated cell replaces the rowid in the alias cell. The run is ready,
-- and "rows aliased" fails after the INSERT. The catalog is not valid, which the theorem asks for.
example : (oneTable generatedAliasTable).RowsAliased := oneTable_every fun row member => by
  simp [generatedAliasTable] at member
example : (runStatement 0 {} [] (insertCells [.value .null]) (oneTable generatedAliasTable)).ready = true := by
  decide +kernel
example : ¬ (oneTable generatedAliasTable).catalog.Valid Resolution.Examples.defaults.limits := by decide +kernel
example : ¬ (runStatement 0 {} [] (insertCells [.value .null]) (oneTable generatedAliasTable)).effect.Satisfies
    Database.RowsAliased := by
  refine not_satisfies_of_ok (after := (oneTable generatedAliasTable).setRows 0
    [{ rowid := 1, values := [.null] }]) (by rfl) ?_
  intro aliased
  have cell := aliased 0 { generatedAliasTable with rows := [{ rowid := 1, values := [.null] }] } rfl
    { rowid := 1, values := [.null] } (by decide +kernel) 0 rfl
  exact absurd cell (by decide +kernel)

end Belay.Sqlite.Model.AdmittedAtomsCounterExamples
