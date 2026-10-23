import Belay.Sqlite.Model.IntegrityCheckTables
import Belay.Sqlite.Model.PragmaRun

set_option doc.verso true

/-! The laws of {lit}`PRAGMA integrity_check` and {lit}`PRAGMA quick_check` (ADR 0019, D2): over
an admitted database, a check pragma gives the one row {lit}`ok` exactly when the facts of a
valid database hold ({lit}`Database.NotNull`, {lit}`Database.ChecksHold`, {lit}`Database.TypesFit`,
and for {lit}`integrity_check` {lit}`Database.KeysUnique`), for every table or for the named one,
with each row limit.

SQLite also checks the stored form of each cell of a table that is not {lit}`STRICT`, which
{lit}`Table.RowsStored` of an admitted table makes true, so the model does not give those rows.
SQLite computes a {lit}`VIRTUAL` column for its NOT NULL and type checks; the model reads its
cell. The two agree in each database that the statements reach, but no fact of an admitted
database says so. -/

namespace Belay.Sqlite.Model

/-- For every quick flag, catalog, position, table name and admitted table ({name}`Table.Admitted`):
the table gives no failures with the indexes of {name}`Catalog.checkedIndexes`
({name}`Table.checkFailures`) exactly when all of these hold:

* {name}`Table.NotNull`, {name}`Table.TypesFit` and {name}`Table.ChecksHold`;
* without {lit}`quick`, {name}`Table.KeysUnique` of the unique keys of the table in the catalog
  ({name}`Catalog.uniqueKeys`).

Proof sketch: the cells give the first three facts ({name}`Table.cellFailures_scan`). With them,
the conflicts are the equal keys of the writes ({name}`Table.conflicts_iff`), symmetric, so the
scan order does not matter. Each unique key is the key of a checked index, the primary key of a
{lit}`WITHOUT ROWID` table, which the order check covers, or the rowid alias, which an admitted
table keeps unique ({name}`Table.aliasKeyUnique`). -/
theorem Table.checkFailures_eq_nil (quick : Bool) (catalog : Catalog) (position : Nat) (name : Identifier)
    {table : Table} (admitted : table.Admitted) :
    table.checkFailures quick name (catalog.checkedIndexes position name table.shape) = [] ↔
      table.NotNull ∧ table.TypesFit ∧ table.ChecksHold ∧
        (quick = false → table.KeysUnique (catalog.uniqueKeys position table.shape)) := by
  unfold Table.checkFailures
  rw [Table.failuresFrom_eq_nil, Table.cellFailures_scan]
  simp only [List.not_mem_nil, false_implies, implies_true, true_and]
  let primary := UniqueKey.ofColumns table.shape.columns table.shape.primaryKey
  let indexes := catalog.checkedIndexes position name table.shape
  have scan : ∀ (notNull : table.NotNull), (table.scanRows.Pairwise fun a b => table.orderConflict quick a b = false ∧
      ∀ checked ∈ indexes, table.entryDuplicated quick checked a b true = false ∧
        table.entryDuplicated quick checked b a false = false) ↔
      (quick = false → table.shape.withoutRowid = true → table.shape.primaryKey ≠ [] →
          table.rows.Pairwise fun a b => LiteralData.keyEqual primary a b = false) ∧
        (quick = false → ∀ checked ∈ indexes, table.rows.Pairwise fun a b => LiteralData.keyEqual checked.key a b = false) := by
    intro notNull
    rw [List.Pairwise.iff_of_mem fun first second => Table.conflicts_iff notNull quick indexes
      (table.scanRows_perm.mem_iff.mp first) (table.scanRows_perm.mem_iff.mp second)]
    rw [List.Perm.pairwise_iff (fun {a b} related => ⟨fun unquick rowid nonempty =>
        (keyEqual_comm _ _ _).trans (related.1 unquick rowid nonempty),
      fun unquick checked found => (keyEqual_comm _ _ _).trans (related.2 unquick checked found)⟩) table.scanRows_perm]
    simp only [List.pairwise_and_iff, pairwise_imp_iff, pairwise_forall_iff]
    exact Iff.rfl
  constructor
  · rintro ⟨⟨notNull, types, checks⟩, pairs⟩
    obtain ⟨order, unique⟩ := (scan notNull).mp pairs
    refine ⟨notNull, types, checks, fun unquick key member => ?_⟩
    rcases Catalog.of_mem_uniqueKeys (name := name) member with ⟨checked, found, rfl⟩ | ⟨nonempty, rfl⟩
    · exact unique unquick checked found
    · cases rowid : table.shape.withoutRowid
      · cases indexed : table.shape.primaryIndexed
        · obtain ⟨alias, isAlias, isPrimary⟩ := CatalogTable.alias_of_not_indexed nonempty indexed
          rw [isPrimary]
          exact Table.aliasKeyUnique admitted isAlias
        · obtain ⟨checked, found, key⟩ := Catalog.checked_of_primary (catalog := catalog) (position := position)
            (name := name) indexed rowid
          rw [← key]
          exact unique unquick checked found
      · exact order unquick rowid nonempty
  · rintro ⟨notNull, types, checks, keys⟩
    refine ⟨⟨notNull, types, checks⟩, (scan notNull).mpr ⟨fun unquick _ nonempty => ?_, fun unquick checked found => ?_⟩⟩
    · exact keys unquick _ (Catalog.primary_mem_uniqueKeys catalog position nonempty)
    · exact keys unquick _ (Catalog.key_mem_uniqueKeys found)

/-- For every database, quick flag, limit and table choice: the check pragma gives the one row
{lit}`ok` ({name}`Database.checkRows`) exactly when no table at the positions of the choice
fails ({name}`Database.checkPositions`). Proof sketch: with one failing table, the rows are
texts of failures, and no failure has the text {lit}`ok` ({name}`CheckFailure.text_ne_ok`). -/
theorem Database.checkRows_ok_iff (database : Database) (quick : Bool) (limit : Nat) (table : Option Nat) :
    database.checkRows quick limit table = some [[.text checkOk]] ↔
      ∀ position ∈ database.checkPositions table, ∀ found, database.table position = some found →
        database.tableFailures quick position found = [] := by
  rw [← Database.blocks_eq_nil]
  unfold Database.checkRows
  cases database.blocks (database.checkPositions table) (database.tableFailures quick) with
  | nil => simp
  | cons failures rest =>
    cases rest with
    | nil =>
      simp only [Option.some.injEq, reduceCtorEq, iff_false]
      intro rows
      have member : [Value.text checkOk] ∈ (failures.take (checkLimit limit)).map fun failure => [Value.text failure.text] := by
        rw [rows]
        exact List.mem_singleton_self _
      obtain ⟨failure, _, text⟩ := List.mem_map.mp member
      exact failure.text_ne_ok (by simpa using text)
    | cons _ _ => simp

/-- For every profile, admitted database ({name}`Database.Admitted`), quick flag, limit and table
at a position: the rows of the check pragma of that table ({name}`Resolved.PragmaRows.rowsOn`) are
the one row {lit}`ok` exactly when the table satisfies {name}`Table.NotNull`,
{name}`Table.TypesFit` and {name}`Table.ChecksHold`, and without {lit}`quick` also
{name}`Table.KeysUnique` of its unique keys in the catalog. The other tables do not matter.
Proof sketch: the rows are {name}`Database.checkRows` of the one position
({name}`Database.checkRows_ok_iff`), and the table is admitted ({name}`Table.checkFailures_eq_nil`).
-/
theorem Database.tableCheck_ok_iff {profile : Profile} {database : Database} (admitted : database.Admitted profile)
    (quick : Bool) (limit : Nat) {position : Nat} {table : Table} (present : database.table position = some table) :
    (Resolved.PragmaRows.check quick limit (some position)).rowsOn database = some [[.text checkOk]] ↔
      table.NotNull ∧ table.TypesFit ∧ table.ChecksHold ∧
        (quick = false → table.KeysUnique (database.catalog.uniqueKeys position table.shape)) := by
  show database.checkRows quick limit (some position) = _ ↔ _
  rw [Database.checkRows_ok_iff]
  simp only [Database.checkPositions, List.mem_singleton, forall_eq, present, Option.some.injEq, forall_eq']
  exact Table.checkFailures_eq_nil quick database.catalog position _ (admitted.table present)

/-- For every profile, admitted database ({name}`Database.Admitted`), quick flag and limit: the
rows of the check pragma of every table ({name}`Resolved.PragmaRows.rowsOn`) are the one row
{lit}`ok` exactly when the database satisfies {name}`Database.NotNull`,
{name}`Database.ChecksHold` and {name}`Database.TypesFit`, and without {lit}`quick` also
{name}`Database.KeysUnique`.
Proof sketch: every table at a position is below the catalog length ({name}`Database.table_lt`) and
admitted, so {name}`Table.checkFailures_eq_nil` applies at each table, and the facts of the database
are the facts of each table. -/
theorem Database.check_ok_iff {profile : Profile} {database : Database} (admitted : database.Admitted profile)
    (quick : Bool) (limit : Nat) :
    (Resolved.PragmaRows.check quick limit none).rowsOn database = some [[.text checkOk]] ↔
      database.NotNull ∧ database.ChecksHold ∧ database.TypesFit ∧ (quick = false → database.KeysUnique) := by
  show database.checkRows quick limit none = _ ↔ _
  rw [Database.checkRows_ok_iff]
  simp only [Database.checkPositions, List.mem_range]
  have tables : (∀ position, position < database.catalog.length → ∀ found, database.table position = some found →
      database.tableFailures quick position found = []) ↔
      ∀ position found, database.table position = some found → found.NotNull ∧ found.TypesFit ∧ found.ChecksHold ∧
        (quick = false → found.KeysUnique (database.catalog.uniqueKeys position found.shape)) :=
    ⟨fun all position found present => (Table.checkFailures_eq_nil quick database.catalog position _
        (admitted.table present)).mp (all position (Database.table_lt present) found present),
      fun all position _ found present => (Table.checkFailures_eq_nil quick database.catalog position _
        (admitted.table present)).mpr (all position found present)⟩
  rw [tables]
  unfold Database.NotNull Database.ChecksHold Database.TypesFit Database.KeysUnique Database.EveryTable
  exact ⟨fun all => ⟨fun position found present => (all position found present).1,
      fun position found present => (all position found present).2.2.1,
      fun position found present => (all position found present).2.1,
      fun unquick position found present => (all position found present).2.2.2 unquick⟩,
    fun ⟨notNull, checks, types, keys⟩ position found present => ⟨notNull position found present,
      types position found present, checks position found present,
      fun unquick => keys unquick position found present⟩⟩

/-- For every profile, admitted database and limit: {lit}`PRAGMA integrity_check` gives the one
row {lit}`ok` ({name}`Resolved.PragmaRows.rowsOn`) exactly when the database satisfies
{name}`Database.NotNull`, {name}`Database.ChecksHold`, {name}`Database.TypesFit` and
{name}`Database.KeysUnique`. -/
theorem Database.integrityCheck_ok_iff {profile : Profile} {database : Database} (admitted : database.Admitted profile)
    (limit : Nat) :
    (Resolved.PragmaRows.check false limit none).rowsOn database = some [[.text checkOk]] ↔
      database.NotNull ∧ database.ChecksHold ∧ database.TypesFit ∧ database.KeysUnique := by
  simp [Database.check_ok_iff admitted]

/-- For every profile, admitted database and limit: {lit}`PRAGMA quick_check` gives the one row
{lit}`ok` ({name}`Resolved.PragmaRows.rowsOn`) exactly when the database satisfies
{name}`Database.NotNull`, {name}`Database.ChecksHold` and {name}`Database.TypesFit`. -/
theorem Database.quickCheck_ok_iff {profile : Profile} {database : Database} (admitted : database.Admitted profile)
    (limit : Nat) :
    (Resolved.PragmaRows.check true limit none).rowsOn database = some [[.text checkOk]] ↔
      database.NotNull ∧ database.ChecksHold ∧ database.TypesFit := by
  simp [Database.check_ok_iff admitted]

end Belay.Sqlite.Model
