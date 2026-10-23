import Belay.Sqlite.Model.ForeignKeysHold
import Belay.Sqlite.Model.PragmaRun
import Belay.Sqlite.Model.QueryLaws

set_option doc.verso true

/-! The laws of {lit}`PRAGMA foreign_key_check` (ADR 0019, D2): the pragma gives no rows exactly
when the foreign keys hold ({lit}`Database.ForeignKeysHold`), or for the named table
{lit}`Table.ForeignKeysHold` of that table. The laws are about the rows of the pragma: a
{lit}`foreign key mismatch` fails the statement at prepare before the rows
({lit}`Catalog.keyMismatch`). -/

namespace Belay.Sqlite.Model

/-- For every list and property of its items: the property holds for the first item of each
pair of {lit}`zipIdx` exactly when it holds for each item.
Proof sketch: each item has a pair at its index, and the first item of each pair is an item. -/
theorem forall_zipIdx_iff {α : Type} {items : List α} {property : α → Prop} :
    (∀ pair ∈ items.zipIdx, property pair.1) ↔ ∀ item ∈ items, property item := by
  constructor
  · intro all item member
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp member
    exact all (item, index) (List.mem_zipIdx_iff_getElem?.mpr found)
  · intro all pair member
    exact all pair.1 (List.fst_mem_of_mem_zipIdx member)

/-- For every database, position and table: the table gives no rows of
{lit}`PRAGMA foreign_key_check` ({name}`Database.keyCheckRows`) exactly when it satisfies
{name}`Table.ForeignKeysHold`. Proof sketch: no row and key gives a row exactly when each row
satisfies each key, and the scan is a permutation of the rows
({name}`Table.scanRows_perm`). -/
theorem Database.keyCheckRows_eq_nil (database : Database) (position : Nat) (table : Table) :
    database.keyCheckRows position table = [] ↔ Table.ForeignKeysHold database position table := by
  unfold Database.keyCheckRows Table.ForeignKeysHold
  simp only [List.flatMap_eq_nil_iff, List.filterMap_eq_nil_iff, table.scanRows_perm.mem_iff]
  have each : ∀ row, (∀ pair ∈ (childLinks database.catalog.foreignKeyLinks position).zipIdx,
      (if pair.1.satisfied database row then none else
        some (foreignKeyCheckRow ((database.catalog[position]?.map (·.name)).getD default) table.shape row pair.1
          pair.2)) = none) ↔
      ∀ link ∈ childLinks database.catalog.foreignKeyLinks position, link.satisfied database row = true := by
    intro row
    refine Iff.trans ?_ forall_zipIdx_iff
    refine forall_congr' fun pair => imp_congr_right fun _ => ?_
    cases pair.1.satisfied database row <;> simp
  simp only [each]
  exact ⟨fun all link found row member => all row member link found,
    fun all row member link found => all link found row member⟩

/-- For every database and table choice: {lit}`PRAGMA foreign_key_check` gives no rows
({name}`Database.foreignKeyCheckRows`) exactly when every table at the positions of the choice
({name}`Database.checkPositions`) satisfies {name}`Table.ForeignKeysHold`.
Proof sketch: one table with rows gives its rows, which are not empty
({name}`Database.blocks_ne_nil`), and two or more give no result. -/
theorem Database.foreignKeyCheckRows_nil_iff (database : Database) (table : Option Nat) :
    database.foreignKeyCheckRows table = some [] ↔
      ∀ position ∈ database.checkPositions table, ∀ found, database.table position = some found →
        Table.ForeignKeysHold database position found := by
  have empty : database.foreignKeyCheckRows table = some [] ↔
      database.blocks (database.checkPositions table) database.keyCheckRows = [] := by
    unfold Database.foreignKeyCheckRows
    cases blocks : database.blocks (database.checkPositions table) database.keyCheckRows with
    | nil => simp
    | cons rows rest =>
      cases rest with
      | nil =>
        have member : rows ∈ database.blocks (database.checkPositions table) database.keyCheckRows := by
          rw [blocks]; exact List.mem_singleton_self rows
        simpa using Database.blocks_ne_nil member
      | cons _ _ => simp
  rw [empty, Database.blocks_eq_nil]
  simp only [Database.keyCheckRows_eq_nil]

/-- For every database and table at a position: {lit}`PRAGMA foreign_key_check` of that table
({name}`Resolved.PragmaRows.rowsOn`) gives no rows exactly when the table satisfies
{name}`Table.ForeignKeysHold`. The other tables need not satisfy their own foreign keys, but
the rows of the parent tables of the table decide both sides. -/
theorem Database.tableKeyCheck_nil_iff (database : Database) {position : Nat} {table : Table}
    (present : database.table position = some table) :
    (Resolved.PragmaRows.foreignKeyCheck (some position)).rowsOn database = some [] ↔
      Table.ForeignKeysHold database position table := by
  show database.foreignKeyCheckRows (some position) = _ ↔ _
  rw [Database.foreignKeyCheckRows_nil_iff]
  simp [Database.checkPositions, present]

/-- For every database: {lit}`PRAGMA foreign_key_check` of every table
({name}`Resolved.PragmaRows.rowsOn`) gives no rows exactly when the database satisfies
{name}`Database.ForeignKeysHold`. Proof sketch: every table is at a position below the catalog
length ({name}`Database.table_lt`). -/
theorem Database.keyCheck_nil_iff (database : Database) :
    (Resolved.PragmaRows.foreignKeyCheck none).rowsOn database = some [] ↔ database.ForeignKeysHold := by
  show database.foreignKeyCheckRows none = _ ↔ _
  rw [Database.foreignKeyCheckRows_nil_iff]
  unfold Database.ForeignKeysHold Database.EveryTable
  simp only [Database.checkPositions, List.mem_range]
  exact ⟨fun all position found present => all position (Database.table_lt present) found present,
    fun all position _ found present => all position found present⟩

end Belay.Sqlite.Model
