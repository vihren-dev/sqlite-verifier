import Belay.Sqlite.Model.ResolveAddColumnCatalog
import Belay.Sqlite.Model.RowLocalAddColumn
import Belay.Sqlite.Model.KeysUniqueAddColumn

set_option doc.verso true

/-! The conditions of ADD COLUMN that a valid catalog gives (ADR 0022, D3, slice 4). A table of a valid
catalog is supported: its keys and its CHECK constraints read only columns below its width. An index of a
valid catalog is supported for the width of its table. So the unique keys of a table read below its width
({lit}`Database.AddColumnCondition`), and its CHECK constraints do ({lit}`Database.ChecksReadBelowAt`). -/

namespace Belay.Sqlite.Model

/-- For every index and width: if {name}`CatalogIndex.supported` holds for the width, the unique key of
the index ({name}`CatalogIndex.uniqueKey`) reads only columns below the width
({name}`UniqueKey.readsBelow`). Proof sketch: the key has the terms and the filter of the index, and
the definition of support gives the same bounds as the definition of the reading. -/
theorem CatalogIndex.uniqueKey_readsBelow {index : CatalogIndex} {width : Nat}
    (supported : index.supported width = true) : index.uniqueKey.readsBelow width = true := by
  simp only [CatalogIndex.supported, Bool.and_eq_true, List.all_eq_true, List.mem_filterMap,
    decide_eq_true_eq, forall_exists_index, and_imp] at supported
  obtain ⟨⟨⟨_, positions⟩, terms⟩, filter⟩ := supported
  simp only [CatalogIndex.uniqueKey, UniqueKey.readsBelow, Bool.and_eq_true, List.all_eq_true]
  refine ⟨fun key member => ?_, filter⟩
  cases hterm : key.term with
  | column position => exact decide_eq_true (positions position key member (by rw [hterm]))
  | expression value => simpa [KeyTerm.readsBelow, hterm] using terms key member

/-- For every valid catalog, position and table at the position: each unique key of the position for
the table reads only columns below the width of the table ({name}`UniqueKey.readsBelow`). Proof sketch: a
key of the primary key or of a UNIQUE constraint names columns below the width, because the table is
supported; a key of a unique index is the key of an index that is supported for this table
({name}`CatalogIndex.uniqueKey_readsBelow`). -/
theorem Catalog.Valid.uniqueKeys_readsBelow {limits : Limits} {catalog : Catalog} (valid : catalog.Valid limits)
    {position : Nat} {shape : CatalogTable} (present : catalog.tableAt position = some shape) :
    ∀ key ∈ catalog.uniqueKeys position shape, key.readsBelow shape.columns.length = true := by
  obtain ⟨_, _, _, _, primary, unique, _⟩ := (CatalogTable.supported_iff _ _).mp (valid.tableSupported present)
  intro key member
  unfold Catalog.uniqueKeys at member
  rcases List.mem_append.mp member with tableKey | indexKey
  · obtain ⟨positions, inside, rfl⟩ := List.mem_map.mp tableKey
    have below : ∀ place ∈ positions, place < shape.columns.length := by
      rcases List.mem_append.mp inside with first | later
      · split at first
        · cases first
        · rw [List.mem_singleton.mp first]; exact primary
      · exact (unique positions later).2
    simp only [UniqueKey.ofColumns, UniqueKey.readsBelow, List.all_map, List.all_eq_true, Function.comp,
      KeyTerm.readsBelow, decide_eq_true_eq, Option.all_none, Bool.and_true]
    exact below
  · obtain ⟨object, inside, kept⟩ := List.mem_filterMap.mp indexKey
    have supported := valid.object inside
    cases entry : object.entry with
    | table _ => simp [entry] at kept
    | trigger _ => simp [entry] at kept
    | index found =>
      simp only [entry, Bool.and_eq_true, beq_iff_eq] at kept
      split at kept <;> try contradiction
      rename_i same
      cases kept
      simp only [CatalogObject.supported, entry, Bool.and_eq_true, Bool.and_eq_true] at supported
      rw [(by simpa using same.1 : found.table = position), present] at supported
      exact CatalogIndex.uniqueKey_readsBelow (by simpa using supported.2)

/-- For every database and position of a table in it, the catalog has that table's entry at the position
({name}`Catalog.tableAt`). Proof sketch: {name}`Database.table` maps the entry of the catalog. -/
theorem Database.tableAt_of_table {database : Database} {target : Nat} {table : Table}
    (present : database.table target = some table) : database.catalog.tableAt target = some table.shape := by
  unfold Database.table at present
  cases found : database.catalog.tableAt target with
  | none => simp [found] at present
  | some shape => simp [found] at present; rw [← present]

/-- For every database whose catalog is valid and target, the database meets
{name}`Database.ChecksReadBelowAt`: if the target holds a table, each CHECK constraint of the table reads
below its width. A target without a table requires nothing. Proof sketch: a supported table has that
fact ({name}`CatalogTable.SupportedFacts`). -/
theorem Database.checksReadBelowAt_of_valid {limits : Limits} {database : Database}
    (valid : database.catalog.Valid limits) (target : Nat) : database.ChecksReadBelowAt target := by
  intro table present
  obtain ⟨_, _, _, _, _, _, _, checks⟩ := (CatalogTable.supported_iff _ _).mp
    (valid.tableSupported (Database.tableAt_of_table present))
  exact checks

/-- For every admitted database and target, the database meets {name}`Database.RowsWideAt`: if the target
holds a table, each row of the table has a cell for each column. A target without a table requires
nothing. Proof sketch: {name}`Database.Admitted` has the fact for every table. -/
theorem Database.rowsWideAt_of_admitted {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) (target : Nat) : database.RowsWideAt target :=
  fun table present => admitted.rowsWide target table present

/-- For every database, target and column: if the default of the column fits its strict type
({name}`strictDefaultFits`), the database meets {name}`Database.StrictDefaultFitsAt` for the column.
That condition says: if the target holds a table with rows, the default of the column fits its strict
type. It requires nothing when the target holds no table or a table without rows. Proof sketch: the
conclusion of the condition is the assumption, whatever the table and its rows are. -/
theorem Database.strictDefaultFitsAt_of_fits {database : Database} {target : Nat} {column : CatalogColumn}
    (fits : strictDefaultFits column = true) : database.StrictDefaultFitsAt target column :=
  fun _ _ _ => fits

/-- For every admitted database and target, the database meets {name}`Database.AddColumnCondition`: if the
target holds a table, its rows are wide and each unique key of the table reads only columns below its
width. A target without a table requires nothing. Proof sketch: {name}`Database.rowsWideAt_of_admitted`
for the rows, and {name}`Catalog.Valid.uniqueKeys_readsBelow` for the keys of the valid catalog. -/
theorem Database.addColumnCondition_of_admitted {profile : Profile} {database : Database}
    (admitted : database.Admitted profile) (target : Nat) : database.AddColumnCondition target :=
  fun table present => ⟨admitted.rowsWide target table present,
    admitted.catalogSupported.uniqueKeys_readsBelow (Database.tableAt_of_table present)⟩

end Belay.Sqlite.Model
