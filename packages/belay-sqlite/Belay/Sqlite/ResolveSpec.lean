import Belay.Sqlite.Resolve

set_option doc.verso true

/-! The declarative rules of name resolution, close to SQLite's documentation, and
the theorems that {name}`Belay.Sqlite.resolve` meets them for all inputs. A reviewer
reads the rules here; the theorems connect them to the algorithm. -/

namespace Belay.Sqlite

/-- The first-match rule of a search: the element at the position passes the test,
and no earlier element passes it. -/
def FirstMatch (test : α → Bool) (items : List α) (position : Nat) (found : α) : Prop :=
  items[position]? = some found ∧ test found = true ∧
    ∀ earlier < position, ∀ item, items[earlier]? = some item → test item = false

/-- For every test, list, position and element, {name}`findPosition` returns the
position and element exactly when they satisfy {name}`FirstMatch`. Proof sketch:
induction on the list; the head either passes the test (position zero) or fails
it, and then every position moves by one. -/
theorem findPosition_eq_some_iff (test : α → Bool) (items : List α) (position : Nat) (found : α) :
    findPosition test items = some (position, found) ↔ FirstMatch test items position found := by
  induction items generalizing position with
  | nil => simp [findPosition, FirstMatch]
  | cons head rest ih =>
    by_cases passes : test head = true
    · have earliest : ∀ found', FirstMatch test (head :: rest) position found' → position = 0 := by
        intro found' ⟨_, _, earlier⟩
        cases position with
        | zero => rfl
        | succ p => exact absurd (earlier 0 (Nat.succ_pos p) head rfl) (by simp [passes])
      constructor
      · intro h
        simp only [findPosition, passes, ite_true, Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        exact ⟨rfl, passes, fun _ h => absurd h (Nat.not_lt_zero _)⟩
      · intro match_
        have zero := earliest found match_
        subst zero
        obtain ⟨at_, _, _⟩ := match_
        simp only [List.getElem?_cons_zero, Option.some.injEq] at at_
        subst at_
        simp [findPosition, passes]
    · have fails : test head = false := by simpa using passes
      constructor
      · intro h
        simp only [findPosition, fails, Bool.false_eq_true, ite_false, Option.map_eq_some_iff] at h
        obtain ⟨⟨p, f⟩, inner, outer⟩ := h
        simp only [Prod.mk.injEq] at outer
        obtain ⟨rfl, rfl⟩ := outer
        obtain ⟨at_, ok, earlier⟩ := (ih p).mp inner
        refine ⟨by simpa using at_, ok, fun e he item hi => ?_⟩
        cases e with
        | zero => simp only [List.getElem?_cons_zero, Option.some.injEq] at hi; subst hi; exact fails
        | succ e => exact earlier e (by omega) item (by simpa using hi)
      · intro ⟨at_, ok, earlier⟩
        cases position with
        | zero =>
          simp only [List.getElem?_cons_zero, Option.some.injEq] at at_
          subst at_; simp [fails] at ok
        | succ position =>
          simp only [findPosition, fails, Bool.false_eq_true, ite_false, Option.map_eq_some_iff]
          refine ⟨(position, found), (ih position).mpr ⟨by simpa using at_, ok, fun e he item hi =>
            earlier (e + 1) (by omega) item (by simpa using hi)⟩, rfl⟩

/-- The column reference rule ({lit}`lang_expr.html`, "Column Names"; SQLite's
{lit}`sqlite3ColumnIndex`): a name refers to the column at a position when that
column's ASCII-folded name equals the folded name, and no earlier column has it. -/
def ColumnReference (columns : List CatalogColumn) (name : String) (position : Nat) : Prop :=
  ∃ column, columns[position]? = some column ∧
    normalizeIdentifier column.name = normalizeIdentifier name ∧
    ∀ earlier < position, ∀ other, columns[earlier]? = some other →
      normalizeIdentifier other.name ≠ normalizeIdentifier name

/-- For all columns, names and positions: {name}`columnPosition` gives the position
exactly when {name}`ColumnReference` holds for it. -/
theorem columnPosition_eq_some_iff (columns : List CatalogColumn) (name : String) (position : Nat) :
    columnPosition columns name = some position ↔ ColumnReference columns name position := by
  simp only [columnPosition, Option.map_eq_some_iff, Prod.exists, findPosition_eq_some_iff,
    FirstMatch, ColumnReference, beq_iff_eq, beq_eq_false_iff_ne, ne_eq]
  constructor
  · rintro ⟨_, column, match_, rfl⟩; exact ⟨column, match_⟩
  · rintro ⟨column, match_⟩; exact ⟨position, column, match_, rfl⟩

end Belay.Sqlite
