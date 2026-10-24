import Belay.Sqlite.Model.ModelLaws
import Belay.Sqlite.Model.AdmittedAddColumnLaws
import Belay.Sqlite.Model.DatabaseShapedLaws
import Belay.Sqlite.Model.StoreValueLaws
import Belay.Sqlite.Model.DatabaseLaws

set_option doc.verso true

/-! Catalog updates for added columns keep lookup proofs independent of the catalog
size. -/
namespace Belay.Sqlite.Model

/-- For every admitted table and list of column/value pairs, {name}`Table.appendColumns`
gives an admitted table ({name}`Table.Admitted`). With no rows, each fact is vacuous. Column
support is a separate catalog check. Proof sketch: one law for each fact
({name}`Table.RowidsDistinct.appendColumns`, {name}`Table.RowidsInRange.appendColumns`,
{name}`Table.RowsWide.appendColumns`, {name}`Table.RowsStored.appendColumns`,
{name}`Table.RowsAliased.appendColumns`). -/
theorem Table.Admitted.appendColumns {table : Table} {columns : List (CatalogColumn × Value)}
    (admitted : table.Admitted) : (table.appendColumns columns).Admitted :=
  ⟨admitted.rowidsDistinct.appendColumns columns, admitted.rowidsInRange.appendColumns columns,
    admitted.rowsWide.appendColumns columns, admitted.rowsStored.appendColumns admitted.rowsWide columns,
    admitted.rowsAliased.appendColumns columns⟩

/-- For every profile, catalog, database, table, position, column and value, assume:
* The original database satisfies {name}`Conforms` with the original catalog.
* The view has the given table at the selected position.
* The catalog from {name}`Catalog.addColumn` satisfies {name}`Catalog.Valid`.
Then {name}`Database.addColumn` satisfies {name}`Conforms` with the extended catalog. A
position without a table cannot satisfy the second assumption. Use this theorem after
checking the new catalog. Proof sketch: the changed table is the old valid table with the
column appended ({name}`Database.table_addColumn`, {name}`Table.Admitted.appendColumns`);
every other position is unchanged ({name}`Database.table_addColumn_other`). -/
theorem Conforms.addColumn {catalog : Catalog} {database : Database} {table : Table} {column : CatalogColumn}
    (value : Value) (conforms : Conforms profile catalog database) (present : database.table position = some table)
    (catalogValid : (catalog.addColumn position column).Valid profile.limits) :
    Conforms profile (catalog.addColumn position column) (database.addColumn position column value) := by
  obtain ⟨same, admitted⟩ := conforms
  subst same
  refine ⟨rfl, Database.Admitted.ofTables catalogValid (admitted.rowsShaped.addColumn present column value) fun other => ?_⟩
  · intro result found
    by_cases equal : other = position
    · subst other
      rw [Database.table_addColumn column value present] at found
      cases found
      exact (admitted.table present).appendColumns
    · rw [Database.table_addColumn_other database column value equal] at found
      exact admitted.table found
/-- For every catalog, name, table and position below the catalog length,
{name}`Catalog.createTable` keeps the entry at the position. -/
theorem Catalog.tableAt_createTable_below (catalog : Catalog) (name : Identifier) (table : CatalogTable)
    {position : Nat} (below : position < catalog.length) :
    (catalog.createTable name table).tableAt position = catalog.tableAt position := by
  simp [Catalog.tableAt, Catalog.createTable, List.getElem?_append_left below]

/-- For every catalog, name and table, after {name}`Catalog.createTable` the position
{lean}`catalog.length` holds the new table. -/
theorem Catalog.tableAt_createTable_end (catalog : Catalog) (name : Identifier) (table : CatalogTable) :
    (catalog.createTable name table).tableAt catalog.length = some table := by
  simp [Catalog.tableAt, Catalog.createTable]

/-- For every catalog, name, table and position above the catalog length, the position
holds no table after {name}`Catalog.createTable`. -/
theorem Catalog.tableAt_createTable_above (catalog : Catalog) (name : Identifier) (table : CatalogTable)
    {position : Nat} (above : catalog.length < position) :
    (catalog.createTable name table).tableAt position = none := by
  simp [Catalog.tableAt, Catalog.createTable, List.getElem?_eq_none (by simp; omega : (catalog ++ [_]).length ≤ position)]

/-- For every profile, catalog, database, name and table, assume:
* The database satisfies {name}`Conforms` with the catalog.
* The catalog from {name}`Catalog.createTable` satisfies {name}`Catalog.Valid`.
Then the database after CREATE TABLE (the new catalog, and an empty row list appended)
satisfies {name}`Conforms` with the new catalog. Proof sketch: positions below the old
length keep their entry and rows; the new position holds the table with no rows; positions
above it hold nothing. -/
theorem Conforms.createTable {catalog : Catalog} {database : Database} (name : Identifier) (table : CatalogTable)
    (conforms : Conforms profile catalog database)
    (catalogValid : (catalog.createTable name table).Valid profile.limits) :
    Conforms profile (catalog.createTable name table)
      { catalog := database.catalog.createTable name table, rows := database.rows ++ [[]] } := by
  obtain ⟨same, admitted⟩ := conforms
  subst same
  refine ⟨rfl, Database.Admitted.ofTables catalogValid (admitted.rowsShaped.append { name, entry := .table table })
    fun position => ?_⟩
  · intro result found
    rcases Nat.lt_trichotomy position database.catalog.length with below | equal | above
    · have kept : ({ catalog := database.catalog.createTable name table, rows := database.rows ++ [[]] } : Database).table
          position = database.table position := by
        simp only [Database.table, Catalog.tableAt_createTable_below _ _ _ below, rows_getD_append_nil]
      rw [kept] at found
      exact admitted.table found
    · subst equal
      simp only [Database.table, Catalog.tableAt_createTable_end, Option.map_some, Option.some.injEq,
        rows_getD_append_nil] at found
      subst found
      have empty : database.rows.getD database.catalog.length [] = [] := by
        simp [List.getD_eq_getElem?_getD, List.getElem?_eq_none (by have := admitted.rowsShaped.1; omega : database.rows.length ≤ database.catalog.length)]
      exact Table.Admitted.ofEmpty empty
    · simp [Database.table, Catalog.tableAt_createTable_above _ _ _ above] at found

end Belay.Sqlite.Model
