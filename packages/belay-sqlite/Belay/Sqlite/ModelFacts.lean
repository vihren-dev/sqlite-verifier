import Belay.Sqlite.Preservation

set_option doc.verso true

/-! Structural lookup, update and projection facts need no application contract. -/

namespace Belay.Sqlite

/-- For every test, list and found position: if {name}`findPosition` finds the
position, it is below the list length. The proof inducts over the list: the
head gives position zero, and a later match adds one to a position that is below
the tail length. -/
theorem findPosition_lt {test : α → Bool} {items : List α} (found : findPosition test items = some (index, item)) :
    index < items.length := by
  induction items generalizing index with
  | nil => simp [findPosition] at found
  | cons head rest ih =>
    simp only [findPosition] at found
    split at found
    · cases found; simp
    · obtain ⟨⟨inner, value⟩, innerFound, equal⟩ := Option.map_eq_some_iff.mp found
      cases equal
      simpa using ih innerFound

/-- For every test, list, suffix and found position: appending a suffix keeps the
position that {name}`findPosition` finds in the list. The proof inducts over the
list: the search stops at the same item before it reaches the suffix. -/
theorem findPosition_append {test : α → Bool} {items : List α} (more : List α)
    (found : findPosition test items = some (index, item)) :
    findPosition test (items ++ more) = some (index, item) := by
  induction items generalizing index with
  | nil => simp [findPosition] at found
  | cons head rest ih =>
    simp only [findPosition, List.cons_append] at found ⊢
    split at found
    · simp_all
    · obtain ⟨⟨inner, value⟩, innerFound, equal⟩ := Option.map_eq_some_iff.mp found
      cases equal
      simp_all

/-- For every requested name, {name}`columnPosition` finds a column of the table.
An empty name list requires nothing; repeated names are allowed. Use this to
establish column presence before projection; row width is separate. -/
def Covers (table : Table) (names : List String) : Prop :=
  ∀ name ∈ names, ∃ index, columnPosition table.shape.columns name = some index

/-- For every table and two limits, if the table is supported under the first and
the second allows at least as many columns, it is supported under the second. Only
the column limit enters {name}`CatalogTable.supported`. The proof splits the
conjunction, keeps each check, and weakens the width bound by transitivity. -/
theorem CatalogTable.supported_mono {table : CatalogTable} (supported : table.supported limits = true)
    (more : limits.columns ≤ other.columns) : table.supported other = true := by
  simp only [CatalogTable.supported, Bool.and_eq_true, decide_eq_true_eq] at supported ⊢
  obtain ⟨⟨⟨⟨⟨⟨nonempty, width⟩, names⟩, rowid⟩, alias⟩, primary⟩, unique⟩ := supported
  exact ⟨⟨⟨⟨⟨⟨nonempty, Nat.le_trans width more⟩, names⟩, rowid⟩, alias⟩, primary⟩, unique⟩

/-- For every catalog and two limits, if the catalog is valid under the first and
the second allows at least as many columns, it is valid under the second. Use it
to check a literal catalog once under small limits and keep the result for every
profile with a larger column limit. The proof applies
{name}`CatalogTable.supported_mono` to each table and keeps the other checks. -/
theorem Catalog.Valid.mono {catalog : Catalog} (valid : catalog.Valid limits)
    (more : limits.columns ≤ other.columns) : catalog.Valid other := by
  simp only [Catalog.Valid, Catalog.supported, Bool.and_eq_true, List.all_eq_true] at valid ⊢
  refine ⟨valid.1, fun object member => ?_⟩
  have supported := valid.2 object member
  unfold CatalogObject.supported at supported ⊢
  split at supported
  · simp only [Bool.and_eq_true] at supported ⊢
    exact ⟨CatalogTable.supported_mono supported.1 more, supported.2⟩
  · exact supported

/-- For every valid catalog under the profile's limits, {name}`Catalog.emptyDatabase`
satisfies {name}`Conforms`, including the empty catalog. Use it as an empty-data
witness; additional invariants require a separate proof. The proof separates
positions with and without a table; empty rows satisfy row validity. -/
theorem Catalog.emptyDatabase_conforms (valid : catalog.Valid profile.limits) :
    Conforms profile catalog catalog.emptyDatabase := by
  refine ⟨valid, fun position => ⟨?_, ?_⟩⟩
  · cases found : catalog.tableAt position <;> simp [Catalog.emptyDatabase, found]
  · intro table present
    cases found : catalog.tableAt position with
    | none => simp [Catalog.emptyDatabase, found] at present
    | some shape =>
      simp only [Catalog.emptyDatabase, found, Option.map_some, Option.some.injEq] at present
      subst table
      exact ⟨by simp, by simp⟩

/-- For every conforming database and stored table, the catalog entry at that
position is the table's shape. The table-presence premise excludes absence. Use
this to read all declared metadata; the proof selects the conformance equality. -/
theorem Conforms.shape (conforms : Conforms profile catalog database)
    (present : database position = some table) : catalog.tableAt position = some table.shape := by
  simpa [present] using (conforms.2 position).1.symm

/-- For every profile, catalog, database, position and shape, assume
{name}`Conforms` and a table entry with that shape at the position. Then some
stored table at the position has exactly that shape and satisfies
{name}`Table.Valid`. A position without a table cannot meet the premise.
The proof uses the shape equality and rules out absence. -/
theorem Conforms.table {shape : CatalogTable} (conforms : Conforms profile catalog database)
    (lookup : catalog.tableAt position = some shape) :
    ∃ table, database position = some table ∧ table.shape = shape ∧ table.Valid := by
  obtain ⟨equal, valid⟩ := conforms.2 position
  cases present : database position with
  | none => simp [present, lookup] at equal
  | some table => exact ⟨table, rfl, by simpa [present, lookup] using equal, valid table present⟩

/-- For every original/next catalog, database, position and table, assume original
{name}`Conforms`, a valid next catalog and a valid replacement table. For every
position, assume the next catalog has the replacement's shape at the changed
position and the original entries elsewhere. Then setting the table conforms to
the next catalog. The old table need not exist. Use this for one-table updates.
The proof separates the changed position from the others. -/
theorem Conforms.set {catalog nextCatalog : Catalog} {database : Database} {position : Nat}
    {table : Table} (conforms : Conforms profile catalog database) (catalogValid : nextCatalog.Valid profile.limits)
    (tableValid : table.Valid)
    (lookup : ∀ other, nextCatalog.tableAt other =
      if other = position then some table.shape else catalog.tableAt other) :
    Conforms profile nextCatalog (database.set position table) := by
  refine ⟨catalogValid, ?_⟩
  intro other
  by_cases same : other = position
  · subst other
    simp only [Database.set, ↓reduceIte, Option.map_some, lookup]
    exact ⟨trivial, fun result equal => by
      cases equal
      exact tableValid⟩
  · simpa only [Database.set, same, ↓reduceIte, lookup] using conforms.2 other

/-- For every database, two distinct positions and two tables, setting the tables
in either order gives the same database. Table validity and rows are unrestricted;
use this equality for independent updates. The proof compares every lookup. -/
theorem Database.set_comm (database : Database) (first second : Nat)
    (firstTable secondTable : Table) (different : first ≠ second) :
    (database.set first firstTable).set second secondTable =
      (database.set second secondTable).set first firstTable := by
  funext position
  by_cases a : position = first <;> by_cases b : position = second <;>
    simp_all [Database.set]

/-- For every before/after table and name list, assume {name}`TableExtends` and
{name}`Covers` before. Then coverage holds after; with no names it is vacuous.
Use this to retain selected columns. The proof keeps each first matching position
through the unchanged prefix of original columns. -/
theorem TableExtends.covers (extension : TableExtends before after)
    (covered : Covers before names) : Covers after names := by
  obtain ⟨columns, rfl⟩ := extension
  intro name member
  obtain ⟨index, found⟩ := covered name member
  obtain ⟨⟨position, column⟩, located, rfl⟩ := Option.map_eq_some_iff.mp found
  exact ⟨position, by simp [Table.appendColumns, columnPosition, findPosition_append (columns.map Prod.fst) located]⟩

/-- For every before/after table and name list, assume {name}`TableExtends`,
one old cell per original column in every old row, and old {name}`Covers`.
Then the two projections are equal, including rowids, duplicates and every cell.
With no rows width is vacuous; with no names coverage is vacuous and rowids remain.
Use this to prove view preservation. The proof retains old column positions and
uses row width to read their cells before the appended values. -/
theorem TableExtends.project (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length)
    (covered : Covers before names) : after.project names = before.project names := by
  obtain ⟨columns, rfl⟩ := extension
  simp only [Table.project, Table.appendColumns, List.map_map]
  apply List.map_congr_left
  intro row member
  apply Prod.ext
  · rfl
  · apply List.map_congr_left
    intro name named
    obtain ⟨index, found⟩ := covered name named
    obtain ⟨⟨position, column⟩, located, rfl⟩ := Option.map_eq_some_iff.mp found
    have afterFound : columnPosition (before.shape.columns ++ columns.map Prod.fst) name = some position := by
      simp [columnPosition, findPosition_append (columns.map Prod.fst) located]
    have bound : position < row.values.length := by
      rw [width row member]
      exact findPosition_lt located
    simp [Row.appendValues, found, afterFound, List.getElem?_append_left bound]

end Belay.Sqlite
