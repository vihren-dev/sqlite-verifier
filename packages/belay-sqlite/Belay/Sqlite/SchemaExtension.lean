import Belay.Sqlite.ModelFacts
import Belay.Sqlite.StoreValueLaws

set_option doc.verso true

/-! Catalog updates for added columns keep lookup proofs independent of the catalog
size. -/
namespace Belay.Sqlite

/-- For every valid table and list of column/value pairs, {name}`Table.appendColumns`
remains valid. With no rows, rowid and width conditions are vacuous. Column
support is a separate catalog check. The proof preserves old cells and rowids,
adds equal numbers of columns and cells, and uses idempotence of
{name}`storeValue` for the appended cells. -/
theorem Table.Valid.appendColumns {table : Table} {columns : List (CatalogColumn × Value)} (valid : table.Valid) :
    (table.appendColumns columns).Valid := by
  refine ⟨?_, ?_⟩
  · simpa [Table.appendColumns, Row.appendValues, List.map_map, Function.comp_def] using valid.1
  · intro row member
    obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
    obtain ⟨rowid, width, stored, aliased⟩ := valid.2 original oldMember
    refine ⟨rowid, by simp [Row.appendValues, Table.appendColumns, width], ?_, ?_⟩
    rotate_left
    · intro position alias
      have cell := aliased position alias
      have old : position < original.values.length := (List.getElem?_eq_some_iff.mp cell).1
      simpa [Table.appendColumns, Row.appendValues, List.getElem?_append_left old] using cell
    intro position column value columnAt cellAt
    simp only [Table.appendColumns, Row.appendValues] at columnAt cellAt
    by_cases old : position < original.values.length
    · rw [List.getElem?_append_left old] at cellAt
      rw [List.getElem?_append_left (width ▸ old)] at columnAt
      exact stored position column value columnAt cellAt
    · rw [List.getElem?_append_right (by omega)] at cellAt
      rw [List.getElem?_append_right (by omega)] at columnAt
      rw [← width] at columnAt
      cases found : columns[position - original.values.length]? with
      | none => simp [List.getElem?_map, found] at cellAt
      | some pair =>
        simp [List.getElem?_map, found] at columnAt cellAt
        subst column
        subst value
        exact storeValue_storeValue _ _

/-- Append columns to the table entry at the catalog position. Every other object,
an index at the position and a position past the end stay unchanged; an empty
column list leaves the catalog unchanged. -/
def Catalog.appendAt (catalog : Catalog) (position : Nat) (columns : List CatalogColumn) : Catalog :=
  catalog.mapIdx fun index object => if index = position then match object.entry with
    | .table table => { object with entry := .table { table with columns := table.columns ++ columns } }
    | .index _ => object
    else object

/-- For every catalog, selected position, lookup position and column list, the
table entry after {name}`Catalog.appendAt` has the columns appended at the selected
position and is unchanged elsewhere. A position without a table stays without a
table; catalog validity is not assumed. The proof reads the mapped element and
separates tables from indexes. -/
theorem Catalog.tableAt_appendAt (catalog : Catalog) (position other : Nat) (columns : List CatalogColumn) :
    (catalog.appendAt position columns).tableAt other =
      if other = position then (catalog.tableAt other).map
        (fun table => { table with columns := table.columns ++ columns }) else catalog.tableAt other := by
  simp only [Catalog.appendAt, Catalog.tableAt, List.getElem?_mapIdx]
  cases found : catalog[other]? with
  | none => simp
  | some object =>
    rcases object with ⟨name, entry⟩
    by_cases same : other = position <;> cases entry <;> simp [same]

/-- For every profile, catalog, database, table, position and column/value list, assume:
* The original database satisfies {name}`Conforms` with the original catalog.
* The database stores the given table at the selected position.
* The catalog from {name}`Catalog.appendAt` satisfies {name}`Catalog.Valid`.
Then {name}`Database.set` of {name}`Table.appendColumns` satisfies {name}`Conforms`
with the extended catalog. A position without a table cannot satisfy the second
assumption. Use this theorem after checking the new catalog. The proof obtains the
old table's validity and shape from conformance and applies {name}`Conforms.set`. -/
theorem Conforms.appendAt {catalog : Catalog} {database : Database} {table : Table}
    (conforms : Conforms profile catalog database) (present : database position = some table)
    (catalogValid : (catalog.appendAt position (columns.map Prod.fst)).Valid profile.limits) :
    Conforms profile (catalog.appendAt position (columns.map Prod.fst)) (database.set position (table.appendColumns columns)) := by
  have valid := (conforms.2 position).2 table present
  have shape := conforms.shape present
  apply conforms.set catalogValid valid.appendColumns
  intro other
  rw [Catalog.tableAt_appendAt]
  by_cases same : other = position
  · subst other; simp [shape, Table.appendColumns]
  · simp [same]

end Belay.Sqlite
