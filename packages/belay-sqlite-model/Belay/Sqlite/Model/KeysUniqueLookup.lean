import Belay.Sqlite.Model.DatabaseConstraints

set_option doc.verso true

/-! The lookup lemma of the atom "keys unique" (ADR 0022, slice 2; ADR 0017, S4): in a table
whose keys are unique, at most one row conflicts with a probe row on a unique key, so a lookup by
a unique key gives at most one row. It needs that a conflict ({lit}`LiteralData.keyEqual`) is
symmetric and transitive, which follows from the comparison of a collation
({lit}`Collation.compare`, a {lit}`Std.TransCmp`). -/

namespace Belay.Sqlite.Model
namespace LiteralData

/-- For every two values and collation: if they conflict as key cells ({name}`keyCellsEqual`),
they conflict in the other order. Proof sketch: the comparison of a collation is oriented
({lit}`Std.OrientedCmp`). -/
theorem keyCellsEqual_symm {first second : Value} {collation : Collation}
    (equal : keyCellsEqual first second collation = true) : keyCellsEqual second first collation = true := by
  simp only [keyCellsEqual, Bool.and_eq_true, beq_iff_eq] at equal ⊢
  exact ⟨⟨equal.1.2, equal.1.1⟩, Std.OrientedCmp.eq_symm equal.2⟩

/-- For every three values and collation: if the first conflicts with the second and the second
with the third as key cells ({name}`keyCellsEqual`), the first conflicts with the third. Proof sketch: the comparison of a collation is transitive
({lit}`Std.TransCmp`). -/
theorem keyCellsEqual_trans {first second third : Value} {collation : Collation}
    (left : keyCellsEqual first second collation = true) (right : keyCellsEqual second third collation = true) :
    keyCellsEqual first third collation = true := by
  simp only [keyCellsEqual, Bool.and_eq_true, beq_iff_eq] at left right ⊢
  exact ⟨⟨left.1.1, right.1.2⟩, Std.TransCmp.eq_trans left.2 right.2⟩

/-- For every key and two rows, {name}`keyEqual` is {lean}`true` exactly when all of these hold:
* the key applies to the first row ({name}`keyApplies`);
* the key applies to the second row;
* for every term of the key, both rows have a value of the term ({name}`termValue`), and the two
  values conflict under the term's collation ({name}`keyCellsEqual`).

Proof sketch: unfold {name}`keyEqual` and split on whether each term has a value in each row. -/
theorem keyEqual_iff (key : UniqueKey) (first second : Row) :
    keyEqual key first second = true ↔ keyApplies key first = true ∧ keyApplies key second = true ∧
      ∀ term ∈ key.terms, ∃ a b, termValue first term.term = some a ∧ termValue second term.term = some b ∧
        keyCellsEqual a b term.collation = true := by
  simp only [keyEqual, Bool.and_eq_true, List.all_eq_true, and_assoc]
  refine and_congr_right fun _ => and_congr_right fun _ => forall_congr' fun term => imp_congr_right fun _ => ?_
  cases termValue first term.term <;> cases termValue second term.term <;> simp

/-- For every key and two rows: if the first conflicts with the second on the key
({name}`keyEqual`), the second conflicts with the first. Proof sketch: {name}`keyEqual_iff`
and {name}`keyCellsEqual_symm` for each term. -/
theorem keyEqual_symm {key : UniqueKey} {first second : Row} (equal : keyEqual key first second = true) :
    keyEqual key second first = true := by
  rw [keyEqual_iff] at equal ⊢
  refine ⟨equal.2.1, equal.1, fun term member => ?_⟩
  obtain ⟨a, b, atFirst, atSecond, cells⟩ := equal.2.2 term member
  exact ⟨b, a, atSecond, atFirst, keyCellsEqual_symm cells⟩

/-- For every key and three rows: if the first conflicts with the second and the second with
the third on the key ({name}`keyEqual`), the first conflicts with the third. Proof sketch:
{name}`keyEqual_iff`; the value of each term in the second row is the same in both conflicts,
and {name}`keyCellsEqual_trans` joins them. -/
theorem keyEqual_trans {key : UniqueKey} {first second third : Row} (left : keyEqual key first second = true)
    (right : keyEqual key second third = true) : keyEqual key first third = true := by
  rw [keyEqual_iff] at left right ⊢
  refine ⟨left.1, right.2.1, fun term member => ?_⟩
  obtain ⟨a, b, atFirst, atSecond, cells⟩ := left.2.2 term member
  obtain ⟨b', c, atSecond', atThird, cells'⟩ := right.2.2 term member
  rw [atSecond, Option.some.injEq] at atSecond'
  subst atSecond'
  exact ⟨a, c, atFirst, atThird, keyCellsEqual_trans cells cells'⟩

end LiteralData

/-- For every list and property: if no two elements of the list, in list order, both have the
property, at most one element of the list has it. Proof sketch: induction on the list; when the
head has the property, no later element has it. -/
theorem filter_length_le_one_of_pairwise {α} {property : α → Bool} :
    ∀ {list : List α}, list.Pairwise (fun a b => ¬(property a = true ∧ property b = true)) →
      (list.filter property).length ≤ 1
  | [], _ => by simp
  | head :: rest, pairwise => by
    rw [List.pairwise_cons] at pairwise
    by_cases holds : property head = true
    · have none : rest.filter property = [] :=
        List.filter_eq_nil_iff.mpr fun other member atOther => pairwise.1 other member ⟨holds, by simpa using atOther⟩
      simp [holds, none]
    · simpa [List.filter_cons, holds] using filter_length_le_one_of_pairwise pairwise.2

/-- The lookup lemma, for every keys, table, key in the keys and probe row: if the table
satisfies {name}`Table.KeysUnique` for the keys, at most one row of the table conflicts with
the probe on the key ({name}`LiteralData.keyEqual`). The probe need not be a row of the table.
Proof sketch: two rows that conflict with the probe conflict with each other
({name}`LiteralData.keyEqual_symm`, {name}`LiteralData.keyEqual_trans`), which the atom
forbids for each pair of rows. -/
theorem Table.KeysUnique.lookup {keys : List UniqueKey} {table : Table} (unique : table.KeysUnique keys)
    {key : UniqueKey} (member : key ∈ keys) (probe : Row) :
    (table.rows.filter fun row => LiteralData.keyEqual key row probe).length ≤ 1 :=
  filter_length_le_one_of_pairwise <| (unique key member).imp fun {first second} distinct both =>
    absurd (LiteralData.keyEqual_trans both.1 (LiteralData.keyEqual_symm both.2)) (by simp [distinct])

/-- The lookup lemma for a database, for every database, position, table, key and probe row:
if the database satisfies {name}`Database.KeysUnique`, it has the table at the position, and the
key is a unique key of the position ({name}`Catalog.uniqueKeys`), then at most one row of the
table conflicts with the probe on the key ({name}`LiteralData.keyEqual`). Proof sketch:
{name}`Table.KeysUnique.lookup` of the atom at the position. -/
theorem Database.KeysUnique.lookup {database : Database} (unique : database.KeysUnique) {position : Nat}
    {table : Table} (found : database.table position = some table) {key : UniqueKey}
    (member : key ∈ database.catalog.uniqueKeys position table.shape) (probe : Row) :
    (table.rows.filter fun row => LiteralData.keyEqual key row probe).length ≤ 1 :=
  (unique position table found).lookup member probe

end Belay.Sqlite.Model
