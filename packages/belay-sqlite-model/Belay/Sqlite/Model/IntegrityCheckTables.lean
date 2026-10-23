import Belay.Sqlite.Model.IntegrityCheckRows
import Belay.Sqlite.Model.IntegrityCheckIndexes
import Belay.Sqlite.Model.IntegrityCheckKeys
import Belay.Sqlite.Model.QueryLaws

set_option doc.verso true

/-! The law of the check pragmas for one table (ADR 0019, D2): an admitted table gives no
failures exactly when {lit}`Table.NotNull`, {lit}`Table.TypesFit` and {lit}`Table.ChecksHold`
hold, and for {lit}`integrity_check` also {lit}`Table.KeysUnique` of its unique keys. -/

namespace Belay.Sqlite.Model

/-- For every condition, relation and list: the relation holds for every two items of the list
under the condition exactly when, under the condition, it holds for every two items.
Proof sketch: both sides are statements about every sublist of two items. -/
theorem pairwise_imp_iff {α} {condition : Prop} {relation : α → α → Prop} {items : List α} :
    items.Pairwise (fun a b => condition → relation a b) ↔ (condition → items.Pairwise relation) := by
  simp only [List.pairwise_iff_forall_sublist]
  constructor
  · intro all holds a b sub
    exact all sub holds
  · intro all a b sub holds
    exact all holds sub

/-- For every list of choices, relation for each choice and list: every two items are related
for every choice exactly when, for every choice, every two items are related.
Proof sketch: both sides are statements about every sublist of two items, with the quantifiers
swapped. -/
theorem pairwise_forall_iff {α β} {choices : List β} {relation : β → α → α → Prop} {items : List α} :
    items.Pairwise (fun a b => ∀ choice ∈ choices, relation choice a b) ↔
      ∀ choice ∈ choices, items.Pairwise (relation choice) := by
  simp only [List.pairwise_iff_forall_sublist]
  constructor
  · intro all choice member a b sub
    exact all sub choice member
  · intro all a b sub choice member
    exact all choice member sub

/-- For every table with {name}`Table.NotNull` and every row of it: at each position with a NOT
NULL column, the cell of the row, if any, is not NULL.
Proof sketch: it is {name}`Table.NotNull` at the row with the NULL cell. -/
theorem Table.NotNull.clean {table : Table} (notNull : table.NotNull) {row : Row} (member : row ∈ table.rows) :
    ∀ position column, table.shape.columns[position]? = some column → column.notNull = true →
      LiteralData.read row position ≠ some .null :=
  fun position column found marked cell => notNull row member position column .null found cell marked rfl

/-- For every table, index and two rows: the entry of the second row comes after the entry of
the first row when the second is later in the scan, or the entry of the first row comes after
the entry of the second row when the first is earlier in the scan ({name}`Table.entryFollows`).
Proof sketch: the comparison of the primary keys is oriented ({name}`Resolved.compareSort_transCmp`), so
when the second key is less than the first, the first is greater than the second. -/
theorem Table.entryFollows_total (table : Table) (checked : CheckedIndex) (first second : Row) :
    table.entryFollows checked first second true = true ∨ table.entryFollows checked second first false = true := by
  have swap : table.ascendingKeyOrder second first = (table.ascendingKeyOrder first second).swap := by
    unfold Table.ascendingKeyOrder
    have := Resolved.compareSort_transCmp (table.shape.primaryKey.map fun position =>
      (false, (table.shape.columns[position]?.map (·.collation)).getD .binary))
    exact Std.OrientedCmp.eq_swap
  unfold Table.entryFollows
  rw [swap]
  cases checked.ascendingTies <;> cases table.ascendingKeyOrder first second <;> simp [Ordering.swap]

/-- For every table, quick flag, two rows of a table with {name}`Table.NotNull` and indexes: the
rows are in order for integrity checking ({name}`Table.orderConflict`) and in every index,
neither entry is followed by an equal entry of the other row ({name}`Table.entryDuplicated`),
exactly when both hold:

* without {lit}`quick`, in a {lit}`WITHOUT ROWID` table with a primary key, their primary keys
  are not equal ({name}`LiteralData.keyEqual`);
* without {lit}`quick`, for every index, their keys on it are not equal.
Proof sketch: the conflicts are the equal keys of the writes ({name}`entryConflict_eq_keyEqual`),
and one of the two entries comes after the other ({name}`Table.entryFollows_total`); a skipped
order check has a NULL first key cell of the second row, so the keys are not equal. -/
theorem Table.conflicts_iff {table : Table} (notNull : table.NotNull) (quick : Bool) (indexes : List CheckedIndex)
    {first second : Row} (firstMember : first ∈ table.rows) (secondMember : second ∈ table.rows) :
    (table.orderConflict quick first second = false ∧ ∀ checked ∈ indexes,
        table.entryDuplicated quick checked first second true = false ∧
          table.entryDuplicated quick checked second first false = false) ↔
      ((quick = false → table.shape.withoutRowid = true → table.shape.primaryKey ≠ [] →
          LiteralData.keyEqual (UniqueKey.ofColumns table.shape.columns table.shape.primaryKey) first second = false) ∧
        (quick = false → ∀ checked ∈ indexes, LiteralData.keyEqual checked.key first second = false)) := by
  have clean := notNull.clean firstMember
  have order : table.orderConflict quick first second = false ↔ (quick = false → table.shape.withoutRowid = true →
      table.shape.primaryKey ≠ [] →
      LiteralData.keyEqual (UniqueKey.ofColumns table.shape.columns table.shape.primaryKey) first second = false) := by
    unfold Table.orderConflict
    dsimp only
    rw [entryConflict_eq_keyEqual _ _ _ _ clean]
    cases primary : table.shape.primaryKey with
    | nil => simp [orderSkipped, UniqueKey.ofColumns]
    | cons position rest =>
      cases skipped : orderSkipped (UniqueKey.ofColumns table.shape.columns (position :: rest)) second
      · cases quick <;> cases table.shape.withoutRowid <;> simp
      · simp only [orderSkipped, UniqueKey.ofColumns, List.map_cons, LiteralData.termValue, beq_iff_eq] at skipped
        have unequal : LiteralData.keyEqual (UniqueKey.ofColumns table.shape.columns (position :: rest)) first second =
            false := by
          simp only [LiteralData.keyEqual, UniqueKey.ofColumns, List.map_cons, List.all_cons, LiteralData.termValue,
            skipped]
          cases LiteralData.read first position <;> simp [LiteralData.keyCellsEqual]
        simp [unequal]
  have index : ∀ checked ∈ indexes, (table.entryDuplicated quick checked first second true = false ∧
      table.entryDuplicated quick checked second first false = false) ↔
      (quick = false → LiteralData.keyEqual checked.key first second = false) := by
    intro checked _
    unfold Table.entryDuplicated Table.indexConflict
    rw [entryConflict_eq_keyEqual _ _ _ _ clean, entryConflict_eq_keyEqual _ _ _ _ (notNull.clean secondMember),
      keyEqual_comm _ second first]
    cases quick <;> cases LiteralData.keyEqual checked.key first second <;>
      rcases table.entryFollows_total checked first second with follows | follows <;> simp [follows]
  rw [order]
  exact and_congr_right fun _ => ⟨fun all unquick checked found => (index checked found).mp (all checked found) unquick,
    fun all checked found => (index checked found).mpr fun unquick => all unquick checked found⟩

/-- For every catalog, position and table whose primary key is not empty: the primary key is in
{name}`Catalog.uniqueKeys` of the table.
Proof sketch: {name}`Catalog.uniqueKeys` starts with a primary key that is not empty. -/
theorem Catalog.primary_mem_uniqueKeys (catalog : Catalog) (position : Nat) {table : CatalogTable}
    (nonempty : table.primaryKey ≠ []) :
    UniqueKey.ofColumns table.columns table.primaryKey ∈ catalog.uniqueKeys position table := by
  unfold Catalog.uniqueKeys
  cases primary : table.primaryKey with
  | nil => exact absurd primary nonempty
  | cons _ _ => simp

/-- For every table whose primary key is not empty and has no index
({name}`CatalogTable.primaryIndexed`): the primary key is the rowid alias alone.
Proof sketch: {name}`CatalogTable.primaryIndexed` is false for a key that is not empty only when it
is the alias. -/
theorem CatalogTable.alias_of_not_indexed {table : CatalogTable} (nonempty : table.primaryKey ≠ [])
    (unindexed : table.primaryIndexed = false) : ∃ position, table.rowidAlias = some position ∧ table.primaryKey = [position] := by
  unfold CatalogTable.primaryIndexed at unindexed
  cases alias : table.rowidAlias with
  | none => cases primary : table.primaryKey <;> simp_all
  | some position => exact ⟨position, rfl, by cases primary : table.primaryKey <;> simp_all⟩

end Belay.Sqlite.Model
