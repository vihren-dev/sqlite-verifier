import Belay.Sqlite.Model.IntegrityCheck
import Belay.Sqlite.Model.DatabaseFacts

set_option doc.verso true

/-! The laws of the key conflicts of {lit}`integrity_check` (ADR 0019, D2): in a row with no NULL
in a NOT NULL column, an entry conflicts exactly when the keys are equal for the writes
({lit}`LiteralData.keyEqual`), which is symmetric; and in an admitted table no two rows have
equal rowid aliases, which have no index to check. -/

namespace Belay.Sqlite.Model

/-- For every two values and collation, {name}`LiteralData.keyCellsEqual` does not depend on
the order of the values.
Proof sketch: the comparison is oriented ({lit}`Std.OrientedCmp.eq_swap`), so it is
{lean}`Ordering.eq` in one order exactly when in the other. -/
theorem keyCellsEqual_comm (first second : Value) (collation : Collation) :
    LiteralData.keyCellsEqual first second collation = LiteralData.keyCellsEqual second first collation := by
  unfold LiteralData.keyCellsEqual
  rw [Std.OrientedCmp.eq_swap (cmp := collation.compare) (a := first)]
  cases collation.compare second first <;> cases (first != Value.null) <;> cases (second != Value.null) <;> rfl

/-- For every key and two rows, {name}`LiteralData.keyEqual` does not depend on the order of the
rows.
Proof sketch: the filters are a conjunction, and each term compares with {name}`keyCellsEqual_comm`.
-/
theorem keyEqual_comm (key : UniqueKey) (first second : Row) :
    LiteralData.keyEqual key first second = LiteralData.keyEqual key second first := by
  unfold LiteralData.keyEqual
  rw [Bool.and_comm (LiteralData.keyApplies key first)]
  congr 1
  congr 1
  funext term
  cases LiteralData.termValue first term.term <;> cases LiteralData.termValue second term.term <;>
    simp [keyCellsEqual_comm]

/-- For every columns, key and two rows such that the first row holds no NULL in a NOT NULL
column (at each position with a NOT NULL column, its cell, if any, is not NULL): the entries
conflict for {lit}`integrity_check` ({name}`entryConflict`) exactly when the keys are equal for
the writes ({name}`LiteralData.keyEqual`). Proof sketch: a NULL term of the first row is then not
a NOT NULL column, so both sides are false; otherwise each term compares the same. -/
theorem entryConflict_eq_keyEqual (columns : List CatalogColumn) (key : UniqueKey) (first second : Row)
    (clean : ∀ position column, columns[position]? = some column → column.notNull = true →
      LiteralData.read first position ≠ some .null) :
    entryConflict columns key first second = LiteralData.keyEqual key first second := by
  have notNullTerm : ∀ term : KeyTerm, termNotNull columns term = true → LiteralData.termValue first term ≠ some .null := by
    intro term marked
    cases term with
    | column position =>
      simp only [termNotNull, Option.any_eq_true] at marked
      obtain ⟨column, found, notNull⟩ := marked
      exact clean position column found notNull
    | expression _ => simp [termNotNull] at marked
  unfold entryConflict entryHasNull LiteralData.keyEqual
  apply Bool.eq_iff_iff.mpr
  simp only [Bool.and_eq_true, Bool.not_eq_true', List.all_eq_true, List.any_eq_false]
  constructor
  · rintro ⟨⟨applies, noNull⟩, cells⟩
    refine ⟨applies, fun term member => ?_⟩
    have cell := cells term member
    have clear := noNull term member
    have marked := notNullTerm term.term
    revert cell clear marked
    cases termNotNull columns term.term <;> cases LiteralData.termValue first term.term with
    | none => cases LiteralData.termValue second term.term <;> simp
    | some cellOfFirst => cases LiteralData.termValue second term.term with
      | none => simp
      | some cellOfSecond =>
        by_cases firstNull : cellOfFirst = .null <;> by_cases secondNull : cellOfSecond = .null <;>
          simp [firstNull, secondNull, entryCellsEqual, LiteralData.keyCellsEqual]
  · rintro ⟨applies, cells⟩
    have notNullFirst : ∀ term ∈ key.terms, LiteralData.termValue first term.term ≠ some .null := by
      intro term member
      have cell := cells term member
      revert cell
      cases LiteralData.termValue first term.term with
      | none => simp
      | some cellOfFirst =>
        cases LiteralData.termValue second term.term <;> by_cases firstNull : cellOfFirst = .null <;>
          simp [firstNull, LiteralData.keyCellsEqual]
    refine ⟨⟨applies, fun term member => by simp [notNullFirst term member]⟩, fun term member => ?_⟩
    have cell := cells term member
    have notNull := notNullFirst term member
    revert cell notNull
    cases LiteralData.termValue first term.term with
    | none => simp
    | some cellOfFirst => cases LiteralData.termValue second term.term with
      | none => simp
      | some cellOfSecond =>
        by_cases firstNull : cellOfFirst = .null <;> by_cases secondNull : cellOfSecond = .null <;>
          simp [firstNull, secondNull, entryCellsEqual, LiteralData.keyCellsEqual]

/-- For every collation and two integers, the integers compare as equal under the collation
only when they are equal.
Proof sketch: a collation keeps an integer, and two integers of the same rank compare by their
scaled values, which are equal only for equal integers. -/
theorem Collation.compare_integer_eq (collation : Collation) (first second : Int)
    (equal : collation.compare (.integer first) (.integer second) = .eq) : first = second := by
  have key : ∀ value : Int, collation.key (.integer value) = .integer value := by
    intro value
    cases collation <;> rfl
  simp only [Collation.compare, key, Value.compare, compareLex, compareOn, Value.rank, Value.scaled, Value.bytes,
    Ordering.then_eq_eq, Int.compare_eq_eq] at equal
  exact Int.eq_of_mul_eq_mul_right (Int.ne_of_gt (Int.pow_pos (by decide))) equal.2.1

/-- For every admitted table ({name}`Table.Admitted`) with the rowid alias at {lit}`position`: no
two rows of the table, in either order of the list, have equal keys on the alias
({name}`LiteralData.keyEqual`). Proof sketch: the alias holds the rowid ({name}`Row.Aliased`),
integers are equal under a collation only when they are equal, and the rowids are distinct. -/
theorem Table.aliasKeyUnique {table : Table} {position : Nat} (admitted : table.Admitted)
    (alias : table.shape.rowidAlias = some position) :
    table.rows.Pairwise fun first second =>
      LiteralData.keyEqual (UniqueKey.ofColumns table.shape.columns [position]) first second = false := by
  have distinct := admitted.rowidsDistinct
  unfold Table.RowidsDistinct at distinct
  rw [List.nodup_iff_pairwise_ne, List.pairwise_map] at distinct
  refine distinct.imp_of_mem fun {first second} firstMember secondMember different => ?_
  have firstCell := admitted.rowsAliased first firstMember position alias
  have secondCell := admitted.rowsAliased second secondMember position alias
  cases equal : LiteralData.keyEqual (UniqueKey.ofColumns table.shape.columns [position]) first second
  · rfl
  · simp only [LiteralData.keyEqual, UniqueKey.ofColumns, LiteralData.keyApplies, LiteralData.termValue,
      LiteralData.read, firstCell, secondCell, List.map_cons, List.map_nil, List.all_cons, List.all_nil,
      LiteralData.keyCellsEqual, Bool.and_true, Bool.true_and] at equal
    exact absurd (Collation.compare_integer_eq _ _ _ (by simpa using equal)) different

end Belay.Sqlite.Model
