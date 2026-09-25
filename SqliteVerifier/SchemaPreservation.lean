import SqliteVerifier.Library

/-! Retained constraints are invariant under exact old-field projections. The key
predicate is universally quantified: no tagged-value equality pretends to be
SQLite's numeric, collation, or NULL comparison semantics. -/

namespace SqliteVerifier

/-- A metadata read recovers the properties of the actual represented table. -/
theorem Conforms.properties {table : Table} (conforms : Conforms schema database)
    (present : database name = some table) :
    schema.lookupProperties name = some table.properties :=
  ((conforms.2 name).2 table present).2

/-- Additions retain every existing primary key, unique key, and named index. -/
theorem TableExtends.properties (extension : TableExtends before after) :
    after.properties = before.properties := by
  obtain ⟨columns, rfl⟩ := extension
  rfl

/-- Old declared types, NOT NULL annotations and defaults remain exact declaration data. -/
theorem TableExtends.declarations (extension : TableExtends before after) :
    after.columns.take before.columns.length = before.columns := by
  obtain ⟨columns, rfl⟩ := extension
  simp [Table.appendColumns]

/-- A supplied native key predicate can express SQLite comparison and NULL rules.
This definition does not choose a comparator or require primary-key nonnullness. -/
def Table.KeysValid (meaning : List String → LogicalRows → Prop) (table : Table) : Prop :=
  ∀ key ∈ table.properties.keys, meaning key (table.project key)

/-- Any true old key predicate remains true, regardless of native key comparison. -/
theorem TableExtends.keysValid (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.columns.length)
    (coverage : ∀ key ∈ before.properties.keys, Covers before key)
    (valid : before.KeysValid meaning) : after.KeysValid meaning := by
  intro key member
  rw [extension.properties] at member
  rw [extension.project width (coverage key member)]
  exact valid key member

/-- Existing NOT NULL and other column-local facts are preserved as actual reads.
The predicate may inspect the full old declaration, including its nullability. -/
theorem TableExtends.columnInvariant {column : Column}
    {predicate : Column → LogicalRows → Prop} (extension : TableExtends before after)
    (width : ∀ row ∈ before.rows, row.values.length = before.columns.length)
    (covered : Covers before [column.name])
    (valid : predicate column (before.project [column.name])) :
    predicate column (after.project [column.name]) := by
  rw [extension.project width covered]
  exact valid

#print axioms TableExtends.keysValid

end SqliteVerifier
