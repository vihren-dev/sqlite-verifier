import SqliteVerifier.ModelFacts

set_option doc.verso true

/-! Retained constraints are invariant under exact old-field projections. The key
predicate is universally quantified: no tagged-value equality pretends to be
SQLite's numeric, collation, or NULL comparison semantics. -/

namespace SqliteVerifier

/-- For every schema, database, name and table, assume {name}`Conforms` and
that the table is stored at the name. Then schema property lookup returns its
properties. An absent table cannot satisfy the premise. Use this for metadata
reads; the proof selects the property conjunct of conformance. -/
theorem Conforms.properties {table : Table} (conforms : Conforms schema database)
    (present : database name = some table) :
    schema.lookupProperties name = some table.properties :=
  ((conforms.2 name).2 table present).2

/-- For every before/after table satisfying {name}`TableExtends`, their properties
are equal, including keys and indexes. No validity or row premise is required.
Use this for retained metadata. The proof unfolds the column append witness. -/
theorem TableExtends.properties (extension : TableExtends before after) :
    after.properties = before.properties := by
  obtain ⟨columns, rfl⟩ := extension
  rfl

/-- For every before/after table satisfying {name}`TableExtends`, the prefix of
new columns with the old length equals the complete old declarations. With no
old columns the equality is between empty lists. Use this for retained types,
defaults and nullability. The proof takes the prefix of the append witness. -/
theorem TableExtends.declarations (extension : TableExtends before after) :
    after.columns.take before.columns.length = before.columns := by
  obtain ⟨columns, rfl⟩ := extension
  simp [Table.appendColumns]

/-- For every retained key, require the supplied predicate on that key's column
names and projected rows. With no keys this requires nothing. Supply the desired
SQLite comparison and NULL meaning, or any other logical key predicate;
this flexible primitive selects neither a comparator nor a nonnullness rule. -/
def Table.KeysValid (meaning : List String → List (Int × List (Option Value)) → Prop) (table : Table) : Prop :=
  ∀ key ∈ table.properties.keys, meaning key (table.project key)

/-- For every before/after table and key predicate, assume {name}`TableExtends`,
correct old row widths, {name}`Covers` for every old key and old {name}`Table.KeysValid`.
Then key validity holds after. With no keys, coverage and validity are vacuous;
with no old rows, widths are vacuous. Use this with the supplied key meaning.
The proof retains properties and rewrites each key projection to the old one. -/
theorem TableExtends.keysValid (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.columns.length)
    (coverage : ∀ key ∈ before.properties.keys, Covers before key)
    (valid : before.KeysValid meaning) : after.KeysValid meaning := by
  intro key member
  rw [extension.properties] at member
  rw [extension.project width (coverage key member)]
  exact valid key member

/-- For every before/after table, supplied column and predicate, assume
{name}`TableExtends`, correct old row widths, coverage of the column's name and
the predicate on that column and its old projection. Then the predicate holds
for the same column and new projection. Only its name must be covered; equality
with stored column metadata is not a premise. With no old rows, widths are
vacuous. Use this to retain any fact about this observation.
The proof rewrites the projection using {name}`TableExtends.project`. -/
theorem TableExtends.columnInvariant {column : Column}
    {predicate : Column → List (Int × List (Option Value)) → Prop} (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.columns.length)
    (covered : Covers before [column.name])
    (valid : predicate column (before.project [column.name])) :
    predicate column (after.project [column.name]) := by
  rw [extension.project width covered]
  exact valid

#print axioms TableExtends.keysValid

end SqliteVerifier
