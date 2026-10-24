import Belay.Sqlite.Model.PreservationLaws
import Belay.Sqlite.Model.DatabaseWriteLaws

set_option doc.verso true

/-! Structural lookup, update and projection facts need no application contract. -/

namespace Belay.Sqlite.Model

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
def Covers (table : Table) (names : List Identifier) : Prop :=
  ∀ name ∈ names, ∃ index, columnPosition table.shape.columns name = some index

/-- For every table and two limits, if the table is supported under the first and
the second allows at least as many columns, it is supported under the second. Only
the column limit enters {name}`CatalogTable.supported`. The proof splits the
conjunction, keeps each check, and weakens the width bound by transitivity. -/
theorem CatalogTable.supported_mono {table : CatalogTable} (supported : table.supported limits = true)
    (more : limits.columns ≤ other.columns) : table.supported other = true := by
  simp only [CatalogTable.supported, Bool.and_eq_true, decide_eq_true_eq] at supported ⊢
  obtain ⟨⟨⟨⟨⟨⟨⟨nonempty, width⟩, names⟩, rowid⟩, primary⟩, unique⟩, alias⟩, checks⟩ := supported
  exact ⟨⟨⟨⟨⟨⟨⟨nonempty, Nat.le_trans width more⟩, names⟩, rowid⟩, primary⟩, unique⟩, alias⟩, checks⟩

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
  all_goals exact supported

/-- For every valid catalog under the profile's limits, {name}`Catalog.emptyDatabase`
satisfies {name}`Conforms`, including the empty catalog. Use it as an empty-data
witness; additional invariants require a separate proof. The proof separates
positions with and without a table; empty rows satisfy row validity. -/
theorem Catalog.emptyDatabase_conforms (valid : catalog.Valid profile.limits) :
    Conforms profile catalog catalog.emptyDatabase := by
  have empty : ∀ position, (catalog.map fun _ => ([] : List Row)).getD position [] = [] := by
    intro position
    simp only [List.getD_eq_getElem?_getD, List.getElem?_map]
    cases catalog[position]? <;> rfl
  refine ⟨rfl, Database.Admitted.ofTables valid ⟨by simp [Catalog.emptyDatabase], fun position _ => empty position⟩ ?_⟩
  intro position table present
  cases found : catalog.tableAt position with
  | none => simp [Catalog.emptyDatabase, Database.table, found] at present
  | some shape =>
    simp only [Catalog.emptyDatabase, Database.table, found, Option.map_some, Option.some.injEq] at present
    subst table
    exact Table.Admitted.ofEmpty (empty position)

/-- For every conforming database and table in its view, the catalog entry at that
position is the table's shape. The table-presence premise excludes absence. Use
this to read all declared metadata; the proof unfolds {name}`Database.table`. -/
theorem Conforms.shape (conforms : Conforms profile catalog database)
    (present : database.table position = some table) : catalog.tableAt position = some table.shape := by
  obtain ⟨same, _⟩ := conforms
  subst same
  unfold Database.table at present
  cases found : database.catalog.tableAt position with
  | none => simp [found] at present
  | some shape =>
    simp only [found, Option.map_some, Option.some.injEq] at present
    subst present
    rfl

/-- For every profile, catalog, database, position and shape, assume
{name}`Conforms` and a table entry with that shape at the position. Then the view has
a table at the position with exactly that shape, and it satisfies {name}`Table.Admitted`.
A position without a table cannot meet the premise. Proof sketch: the catalog is the
database's, so {name}`Database.table` builds the table from the entry, and validity holds
for every table of the view. -/
theorem Conforms.table {shape : CatalogTable} (conforms : Conforms profile catalog database)
    (lookup : catalog.tableAt position = some shape) :
    ∃ table, database.table position = some table ∧ table.shape = shape ∧ table.Admitted := by
  obtain ⟨same, admitted⟩ := conforms
  subst same
  have present : database.table position = some { shape, rows := database.rows.getD position [] } := by
    simp [Database.table, lookup]
  exact ⟨_, present, rfl, admitted.table present⟩

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

end Belay.Sqlite.Model
