import Belay.Sqlite.ModelFacts

set_option doc.verso true

/-! Row and schema lemmas for ordinary literal writes. These follow from the
executable definitions; neither native row allocation nor frame rules are axioms. -/
namespace Belay.Sqlite

/-- For every schema, database, name and old/replacement tables, assume original
{name}`Conforms`, the old table's presence, equal columns and properties, and
replacement {name}`Table.Valid`. Then setting the replacement preserves
conformance with that schema. An absent old table cannot meet the assumptions.
Use this theorem when a write changes only represented rows.

The proof separates the updated lookup from other names. Equal metadata
retains schema matching, and the supplied validity covers the replacement. -/
theorem Conforms.replaceRows {old replacement : Table} (conforms : Conforms schema database)
    (present : database name = some old) (columns : replacement.columns = old.columns)
    (properties : replacement.properties = old.properties) (valid : replacement.Valid) :
    Conforms schema (database.set name replacement) := by
  refine ⟨conforms.1, ?_⟩
  intro other
  by_cases same : other = name
  · subst other
    refine ⟨?_, ?_⟩
    · simpa [Database.set, present, columns] using (conforms.2 name).1
    · intro table stored
      have equal : table = replacement := by simpa [Database.set] using stored.symm
      subst table
      exact ⟨valid, by simpa [properties] using ((conforms.2 name).2 old present).2⟩
  · simpa [Database.set, same] using conforms.2 other

/-- For every row list and initial integer, the folded maximum is at least
the initial value and every listed rowid. With no rows the second condition
is vacuous and the first is equality. Use these bounds for row allocation.
The proof inducts on the list and applies transitivity through each maximum. -/
theorem foldRowMaximum (rows : List Row) (initial : Int) :
    initial ≤ rows.foldl (fun largest row => max largest row.rowid) initial ∧
    ∀ row ∈ rows, row.rowid ≤ rows.foldl (fun largest row => max largest row.rowid) initial := by
  induction rows generalizing initial with
  | nil => simp
  | cons first rest ih =>
    have tail := ih (max initial first.rowid)
    refine ⟨Int.le_trans (Int.le_max_left ..) tail.1, ?_⟩
    intro row member
    rcases List.mem_cons.mp member with equal | member
    · subst row
      exact Int.le_trans (Int.le_max_right ..) tail.1
    · exact tail.2 row member

/-- For every row and list containing it, its rowid is strictly below
{name}`LiteralData.nextRowid`. Membership excludes an empty list; boundedness
and table validity are not assumed. Use this to prove the allocated rowid fresh.
The proof bounds the rowid by the folded maximum, then adds one. -/
theorem LiteralData.rowid_lt_next (member : row ∈ rows) : row.rowid < nextRowid rows := by
  cases rows with
  | nil => simp at member
  | cons first rest =>
    have bounds := foldRowMaximum rest first.rowid
    have below : row.rowid ≤ rest.foldl (fun largest row => max largest row.rowid) first.rowid := by
      rcases List.mem_cons.mp member with equal | member
      · subst row; exact bounds.1
      · exact bounds.2 row member
    simp only [nextRowid]
    omega

/-- For every table and value list, assume {name}`Table.Valid`, a valid newly
allocated rowid, and one supplied value per column. Then {name}`LiteralData.inserted`
satisfies {name}`Table.Valid`. Old row checks are vacuous for an empty table;
new row bounds and width still apply. This says nothing about key constraints.
The proof makes the new rowid fresh using {name}`LiteralData.rowid_lt_next`,
then handles the old rows and single appended row separately. -/
theorem Table.Valid.inserted (valid : table.Valid)
    (bounded : validRowid (LiteralData.nextRowid table.rows))
    (width : values.length = table.columns.length) :
    (LiteralData.inserted table values).Valid := by
  refine ⟨valid.1, ?_, ?_⟩
  · have fresh : LiteralData.nextRowid table.rows ∉ table.rows.map Row.rowid := by
      intro member
      obtain ⟨row, member, equal⟩ := List.mem_map.mp member
      have smaller := LiteralData.rowid_lt_next member
      omega
    simp only [LiteralData.inserted, List.map_append, List.map_cons, List.map_nil, List.nodup_append]
    refine ⟨valid.2.1, by simp, ?_⟩
    intro identity member other freshMember equal
    simp only [List.mem_singleton] at freshMember
    exact fresh ((equal.trans freshMember) ▸ member)
  · intro row member
    simp only [LiteralData.inserted, List.mem_append, List.mem_singleton] at member
    rcases member with old | rfl
    · exact valid.2.2 row old
    · exact ⟨bounded, width⟩

/-- For every table, key, old row list and added row, assume {name}`LiteralData.uniqueRows`
on the old list and false {name}`LiteralData.keyEqual` from every old row to
the addition. Then uniqueness holds after appending that row. For no old rows,
both assumptions hold vacuously. Use this to establish a new row's key constraint.
The proof inducts on the old list and separates its head from the appended row. -/
theorem LiteralData.uniqueRows_append (unique : uniqueRows table key rows = true)
    (fresh : ∀ row ∈ rows, keyEqual table key row added = false) :
    uniqueRows table key (rows ++ [added]) = true := by
  induction rows with
  | nil => simp [uniqueRows]
  | cons row rest ih =>
    simp only [uniqueRows, Bool.and_eq_true] at unique
    simp only [List.cons_append, uniqueRows, List.any_append, List.any_cons, List.any_nil,
      Bool.or_false, fresh row (by simp), Bool.or_false]
    rw [unique.1, ih unique.2 (fun item member => fresh item (List.mem_cons_of_mem row member))]
    rfl

/-- For any two tables with equal columns, and every key and row list,
{name}`LiteralData.uniqueRows` returns the same result for both tables.
No row, property or validity agreement is required, including for an empty list.
Use this to move a key check between tables with unchanged columns.
The proof shows identical key reads, then inducts on the supplied rows. -/
theorem LiteralData.uniqueRows_columns (columns : before.columns = after.columns) :
    uniqueRows before key rows = uniqueRows after key rows := by
  have same : keyEqual before key = keyEqual after key := by
    funext first second
    simp [keyEqual, read, columns]
  induction rows with
  | nil => rfl
  | cons row rest ih => simp [uniqueRows, same, ih]

/-- For every table and supplied value list, assume old {name}`LiteralData.constraints`,
NOT NULL checks on zipped new column/cell pairs, and a false key comparison
between every old row and the new row for every retained key. Then the inserted
table satisfies the same constraint check. With no retained keys the freshness
requirement is vacuous; with no old rows each key's pairwise check is vacuous.
Row width and allocation bounds are not assumed.
Use this after admission and new-row constraint checks.
The proof separates old and new NOT NULL checks, then applies the uniqueness
append and unchanged-column theorems to each retained key. -/
theorem LiteralData.inserted_constraints (old : constraints table = true)
    (nonnull : (table.columns.zip values).all (fun (column, value) =>
      !column.notNull || value != .null) = true)
    (fresh : ∀ key ∈ table.properties.keys, ∀ row ∈ table.rows,
      keyEqual table key row { rowid := nextRowid table.rows, values := values } = false) :
    constraints (inserted table values) = true := by
  simp only [constraints, Bool.and_eq_true] at old ⊢
  constructor
  · simpa [inserted, List.all_append, nonnull] using old.1
  · apply List.all_eq_true.mpr
    intro key member
    change uniqueRows (inserted table values) key
      (table.rows ++ [{ rowid := nextRowid table.rows, values := values }]) = true
    rw [uniqueRows_columns (show (inserted table values).columns = table.columns from rfl)]
    exact uniqueRows_append (List.all_eq_true.mp old.2 key member) (fresh key member)

/-- For every table, key name and supplied value list, assume old
{name}`LiteralData.comparisonReady` and an integer-or-NULL read of that key
in the new row. Then the inserted table remains comparison-ready for the key.
An empty old table still needs the column-affinity requirement; other cells,
allocation bounds and constraints are not assumed. Use this for key admission.
The proof retains the column test and separates old rows from the added row. -/
theorem LiteralData.inserted_comparison (old : comparisonReady table key = true)
    (cell : (read table { rowid := nextRowid table.rows, values := values } key).any integerOrNull = true) :
    comparisonReady (inserted table values) key = true := by
  simp only [comparisonReady, Bool.and_eq_true] at old ⊢
  refine ⟨old.1, ?_⟩
  change (table.rows ++ [(⟨nextRowid table.rows, values⟩ : Row)]).all
    (fun row => (read table row key).any integerOrNull) = true
  simp [List.all_append, old.2, cell]

end Belay.Sqlite
