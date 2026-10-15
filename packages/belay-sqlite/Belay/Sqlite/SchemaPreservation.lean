import Belay.Sqlite.ModelFacts

set_option doc.verso true

/-! Keys are invariant under exact old-field projections. The key predicate is
universally quantified: no tagged-value equality pretends to be SQLite's numeric,
collation, or NULL comparison semantics. -/

namespace Belay.Sqlite

/-- For every row, retain its rowid and select the cells at the column positions, in
order; a position beyond a row's width selects {name}`Option.none`. -/
def Table.projectPositions (table : Table) (positions : List Nat) : List (Int × List (Option Value)) :=
  table.rows.map fun row => (row.rowid, positions.map (row.values[·]?))

/-- For every before/after table satisfying {name}`TableExtends`, the keys, the
rowid alias and the prefix of new columns with the old length are unchanged. No
validity or row premise is required. Use this for retained types, defaults,
nullability and keys. The proof unfolds the column append witness. -/
theorem TableExtends.declarations (extension : TableExtends before after) :
    after.shape.columns.take before.shape.columns.length = before.shape.columns ∧
    after.shape.primaryKey = before.shape.primaryKey ∧ after.shape.uniqueKeys = before.shape.uniqueKeys ∧
    after.shape.rowidAlias = before.shape.rowidAlias := by
  obtain ⟨columns, rfl⟩ := extension
  simp [Table.appendColumns]

/-- For every before/after table and position list, assume {name}`TableExtends`,
one old cell per original column in every old row, and every position below the
old width. Then the position projections are equal, including rowids. With no
rows width is vacuous. The proof reads each cell before the appended values. -/
theorem TableExtends.projectPositions (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length)
    (inside : ∀ position ∈ positions, position < before.shape.columns.length) :
    after.projectPositions positions = before.projectPositions positions := by
  obtain ⟨columns, rfl⟩ := extension
  simp only [Table.projectPositions, Table.appendColumns, List.map_map]
  apply List.map_congr_left
  intro row member
  apply Prod.ext
  · rfl
  · apply List.map_congr_left
    intro position listed
    have bound : position < row.values.length := by rw [width row member]; exact inside position listed
    simp [Row.appendValues, List.getElem?_append_left bound]

/-- For every given key, require the supplied predicate on its column positions and
their projected rows. With no keys this requires nothing. Supply the desired SQLite
comparison and NULL meaning, or any other logical key predicate; this flexible
primitive selects neither a comparator nor a nonnullness rule. -/
def Table.KeysValid (meaning : List Nat → List (Int × List (Option Value)) → Prop) (keys : List (List Nat))
    (table : Table) : Prop :=
  ∀ key ∈ keys, meaning key (table.projectPositions key)

/-- For every before/after table, key list and key predicate, assume
{name}`TableExtends`, correct old row widths, every key position below the old
width and old {name}`Table.KeysValid`. Then key validity holds after. With no keys
the premises are vacuous. The proof rewrites each key projection to the old one. -/
theorem TableExtends.keysValid (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length)
    (inside : ∀ key ∈ keys, ∀ position ∈ key, position < before.shape.columns.length)
    (valid : before.KeysValid meaning keys) : after.KeysValid meaning keys := by
  intro key member
  rw [extension.projectPositions width (inside key member)]
  exact valid key member

/-- For every before/after table, column name and predicate, assume
{name}`TableExtends`, correct old row widths, coverage of the name and the
predicate on the name and its old projection. Then the predicate holds for the
same name and the new projection. With no old rows, widths are vacuous. Use this
to retain any fact about this observation. The proof rewrites the projection
using {name}`TableExtends.project`. -/
theorem TableExtends.columnInvariant {name : String}
    {predicate : String → List (Int × List (Option Value)) → Prop} (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.shape.columns.length)
    (covered : Covers before [name])
    (valid : predicate name (before.project [name])) :
    predicate name (after.project [name]) := by
  rw [extension.project width covered]
  exact valid

#print axioms TableExtends.keysValid

end Belay.Sqlite
