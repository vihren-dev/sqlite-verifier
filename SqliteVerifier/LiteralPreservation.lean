import SqliteVerifier.Library

/-! Row and schema lemmas for ordinary literal writes. These follow from the
executable definitions; neither native row allocation nor frame rules are axioms. -/
namespace SqliteVerifier

/-- Replacing only rows preserves every represented schema object. -/
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

/-- A finite maximum bounds both its initial accumulator and every visited row. -/
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

/-- Normal automatic rowid allocation is strictly above every old physical identity. -/
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

/-- A bounded newly allocated identity preserves widths and distinct physical rows. -/
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

/-- Appending a key distinct from each old key preserves uniqueness. -/
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

end SqliteVerifier
