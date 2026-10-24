import Belay.Sqlite.Model.DatabaseFacts
import Belay.Sqlite.Model.DatabaseLaws
import Belay.Sqlite.Model.DropPositionLaws

set_option doc.verso true

/-! What the operations on a database keep of {lit}`Database.RowsShaped` (ADR 0022, D3, slice 4):
one row list for each catalog object, and no rows at a position without a table. A write replaces
the row list of a table, CREATE appends an object and an empty row list, ADD COLUMN changes the
rows of a table and one catalog entry, and DROP removes the same positions from both lists. -/

namespace Belay.Sqlite.Model

/-- For every catalog, position and column, {name}`Catalog.addColumn` keeps the number of
catalog objects. -/
theorem Catalog.length_addColumn (catalog : Catalog) (position : Nat) (column : CatalogColumn) :
    (catalog.addColumn position column).length = catalog.length := by
  unfold Catalog.addColumn
  split <;> simp

/-- For every shaped database, position of a table and rows, the database after
{name}`Database.setRows` is shaped. Proof sketch: setting a row list keeps the number of row lists;
the position has a table, so the row lists at the positions without a table are the old ones. -/
theorem Database.RowsShaped.setRows {database : Database} (shaped : database.RowsShaped) {target : Nat}
    {table : Table} (found : database.table target = some table) (rows : List Row) :
    (database.setRows target rows).RowsShaped := by
  refine ⟨by simpa [Database.setRows] using shaped.1, fun position absent => ?_⟩
  have different : position ≠ target := by
    intro same
    subst same
    have none : database.catalog.tableAt position = none := absent
    simp [Database.table, none] at found
  simp only [Database.setRows, List.getD_eq_getElem?_getD, List.getElem?_set_ne (Ne.symm different)]
  simpa [List.getD_eq_getElem?_getD] using shaped.2 position absent

/-- For every shaped database and every catalog object, the database with the object appended to its
catalog and an empty row list appended to its rows is shaped. Proof sketch: both lists grow by one; the empty
row list does not change what {lit}`getD` reads ({name}`rows_getD_append_nil`), and the new position is
past the old row lists or below them. -/
theorem Database.RowsShaped.append {database : Database} (shaped : database.RowsShaped) (object : CatalogObject) :
    ({ catalog := database.catalog ++ [object], rows := database.rows ++ [[]] } : Database).RowsShaped := by
  refine ⟨by simp [shaped.1], fun position absent => ?_⟩
  change (database.rows ++ [[]]).getD position [] = []
  rw [rows_getD_append_nil]
  by_cases below : position < database.catalog.length
  · apply shaped.2 position
    change database.catalog.tableAt position = none
    unfold Catalog.tableAt at absent ⊢
    rwa [List.getElem?_append_left below] at absent
  · simp [List.getD_eq_getElem?_getD, List.getElem?_eq_none (by have := shaped.1; omega : database.rows.length ≤ position)]

/-- For every catalog, positions and kept position, the entry of {name}`Catalog.drop` at the new
position ({name}`keptBelow`) is a table exactly when the old entry is. Proof sketch: the kept entry
is the old entry after {name}`CatalogEntry.afterDrop`, which changes only an index. -/
theorem Catalog.tableAt_drop_kept (catalog : Catalog) {positions : List Nat} {old : Nat}
    (kept : !positions.contains old) :
    (catalog.drop positions).tableAt (keptBelow positions old) = catalog.tableAt old := by
  have entry : (catalog.drop positions)[keptBelow positions old]? =
      (catalog[old]?).map fun object => { object with entry := object.entry.afterDrop positions } := by
    simp only [Catalog.drop_eq_keptAfterDrop, List.getElem?_map, getElem?_keptAfterDrop _ _ kept]
  unfold Catalog.tableAt
  rw [entry]
  cases atOld : catalog[old]? with
  | none => rfl
  | some object =>
    rcases object with ⟨name, objectEntry⟩
    cases objectEntry <;> simp [CatalogEntry.afterDrop]

/-- For every shaped database and positions, the database after {name}`Database.drop` is shaped.
Proof sketch: both lists lose the same positions, so they keep the same length
({name}`length_keptAfterDrop`); a kept position without a table has the row list of its old position
({name}`getElem?_keptAfterDrop`, {name}`Catalog.tableAt_drop_kept`), and a position past the kept
row lists has none. -/
theorem Database.RowsShaped.drop {database : Database} (shaped : database.RowsShaped) (positions : List Nat) :
    (database.drop positions).RowsShaped := by
  refine ⟨?_, fun position absent => ?_⟩
  · change (keptAfterDrop positions database.rows).length = (database.catalog.drop positions).length
    rw [Catalog.drop_eq_keptAfterDrop, List.length_map, length_keptAfterDrop, length_keptAfterDrop, shaped.1]
  · by_cases inside : position < (keptAfterDrop positions database.rows).length
    · obtain ⟨old, kept, rfl⟩ := exists_keptBelow positions database.rows inside
      have oldRows : (database.drop positions).rows.getD (keptBelow positions old) [] = database.rows.getD old [] := by
        simp only [List.getD_eq_getElem?_getD, Database.drop_rows, getElem?_keptAfterDrop _ _ kept]
      rw [oldRows]
      apply shaped.2
      change (database.drop positions).catalog.tableAt (keptBelow positions old) = none at absent
      rwa [show (database.drop positions).catalog = database.catalog.drop positions from rfl,
        Catalog.tableAt_drop_kept _ kept] at absent
    · simp [List.getD_eq_getElem?_getD, Database.drop_rows, List.getElem?_eq_none (Nat.le_of_not_lt inside)]

/-- For every shaped database, position of a table, column and value, the database after
{name}`Database.addColumn` is shaped. Proof sketch: the catalog keeps its length
({name}`Catalog.length_addColumn`) and every entry that is not a table; the row lists keep their
length, and only the table's changes. -/
theorem Database.RowsShaped.addColumn {database : Database} (shaped : database.RowsShaped) {position : Nat}
    {table : Table} (present : database.table position = some table) (column : CatalogColumn) (value : Value) :
    (database.addColumn position column value).RowsShaped := by
  refine ⟨by simp [Database.addColumn, Catalog.length_addColumn, shaped.1], fun other absent => ?_⟩
  by_cases equal : other = position
  · subst other
    have kept := Database.table_addColumn column value present
    simp [Database.table, absent] at kept
  · change (database.catalog.addColumn position column).tableAt other = none at absent
    rw [Catalog.tableAt_addColumn_other _ column equal] at absent
    simpa [Database.addColumn, List.getD_eq_getElem?_getD, List.getElem?_modify, Ne.symm equal] using
      shaped.2 other absent

end Belay.Sqlite.Model
