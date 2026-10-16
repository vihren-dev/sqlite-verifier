import Belay.Sqlite.Resolution.ColumnSpec

set_option doc.verso true

/-! The row width rule of INSERT, and the theorem that resolution meets it. -/

namespace Belay.Sqlite

/-- For a successful {name}`resolveAllFrom`, the result has one value per item, and
for each index with an item, the value at that index is the result of resolving the
item at the start position plus the index. Proof sketch: induction on the items;
the head's value comes first and every later index moves by one. -/
theorem resolveAllFrom_ok (resolveOne : Nat → α → Except ValueIssue β) (start : Nat)
    (items : List α) (values : List β) (ok : resolveAllFrom resolveOne start items = .ok values) :
    values.length = items.length ∧ ∀ index item, items[index]? = some item →
      ∃ value, values[index]? = some value ∧ resolveOne (start + index) item = .ok value := by
  induction items generalizing start values with
  | nil => cases ok; simp
  | cons item rest ih =>
    simp only [resolveAllFrom, bind, Except.bind] at ok
    split at ok <;> try contradiction
    rename_i value head
    split at ok <;> try contradiction
    rename_i tail_values tail
    cases ok
    obtain ⟨length, each⟩ := ih (start + 1) tail_values tail
    refine ⟨by simp [length], fun index found h => ?_⟩
    cases index with
    | zero => simp at h; subst h; exact ⟨value, rfl, by simpa using head⟩
    | succ index =>
      obtain ⟨v, hv, hr⟩ := each index found (by simpa using h)
      exact ⟨v, by simpa using hv, by simpa [Nat.add_assoc, Nat.add_comm 1 index] using hr⟩

/-- The row width rule ({lit}`lang_insert.html`, R-12183-43719 and R-18927-01951):
for the table columns, the table positions of the written columns, a written row
and a full row:
* The full row has one value for each table column.
* For each table column, when its position occurs in the written positions, the
  first occurrence {lit}`k` decides: the column has the {lit}`k`-th written value, or
  NULL when the written row has no {lit}`k`-th value, stored with the column's
  affinity ({name}`storeValue`).
* Every other table column has the value of its default, as {name}`defaultValue`
  gives it, stored with the column's affinity.
Written positions outside the table impose nothing. -/
def RowWidth (columns : List CatalogColumn) (positions : List Nat)
    (written full : List Value) : Prop :=
  full.length = columns.length ∧ ∀ index (h : index < columns.length),
    (∀ k, positions.idxOf? index = some k →
      full[index]? = some (storeValue columns[index].affinity (written[k]?.getD .null))) ∧
    (positions.idxOf? index = none →
      (defaultValue columns[index]).map (storeValue columns[index].affinity) = .ok (full[index]?.getD .null))

/-- For all inputs, a successful {name}`fullRow` gives a full row that satisfies
{name}`RowWidth`. Proof sketch: {name}`resolveAllFrom_ok` gives the length and the
value of each column, which is the stored written value or the stored default. -/
theorem fullRow_rowWidth (columns : List CatalogColumn) (positions : List Nat)
    (written full : List Value) (ok : fullRow columns positions written = .ok full) :
    RowWidth columns positions written full := by
  unfold fullRow resolveAll at ok
  obtain ⟨length, each⟩ := resolveAllFrom_ok _ 0 columns full ok
  refine ⟨length, fun index h => ?_⟩
  obtain ⟨value, hvalue, step⟩ := each index columns[index] (List.getElem?_eq_getElem h)
  simp only [Nat.zero_add, bind, Except.bind] at step
  constructor
  · intro k hk
    rw [hk] at step
    simp only at step
    cases step
    exact hvalue
  · intro hk
    rw [hk] at step
    simp only at step
    cases hdefault : defaultValue columns[index] with
    | error cause => rw [hdefault] at step; cases step
    | ok default =>
      rw [hdefault] at step
      cases step
      simp [hvalue, Except.map]

/-- For a successful resolution of INSERT, with any {lit}`ON CONFLICT` clauses, to an
insert statement, the catalog is
unchanged, the statement names the position of the table that the name finds and
carries that table's {name}`Catalog.uniqueKeys`, and for every resolved row there are table positions of the written columns and a
written row such that the resolved row satisfies {name}`RowWidth` for the table's
columns. So every resolved row has one value for each table column. Proof sketch:
split the resolver down to its successful branch; each row is a result of
{name}`fullRow` by {name}`resolveAllFrom_ok`, and {name}`fullRow_rowWidth` gives the rule. -/
theorem resolveInsert_rowWidth (context : ResolveContext) (catalog after : Catalog) (index : Nat)
    (tableName : String) (names : Option (List String)) (rows : List (List Syntax.Expr))
    (conflicts : List Syntax.ConflictClause) (algorithm : Option ConflictAlgorithm)
    (returning : List Syntax.ResultColumn)
    (position : Nat) (full : List (List Value)) (keys : List (List Nat))
    (columns : List (Resolved.Expr × String))
    (ok : resolveInsert context catalog index tableName names rows conflicts algorithm returning =
      .ok (.insert position full keys columns, after)) :
    after = catalog ∧ ∃ table, catalog.findTable tableName = some (position, table) ∧
      keys = catalog.uniqueKeys position table ∧ ∀ row ∈ full, ∃ positions written, RowWidth table.columns positions written row := by
  unfold resolveInsert at ok
  simp only [prepareError, restrict, issueResolution] at ok
  split at ok
  · cases ok
  split at ok
  · cases ok
  rename_i found_position table found
  split at ok
  · cases ok
  rename_i positions _
  split at ok
  · split at ok <;> cases ok
  rename_i written _
  split at ok
  · cases ok
  split at ok
  · cases ok
  split at ok
  · cases ok
  split at ok
  · split at ok <;> cases ok
  rename_i rows_ok
  split at ok
  · split at ok <;> cases ok
  split at ok
  · split at ok <;> cases ok
  split at ok
  · cases ok
  split at ok
  · cases ok
  split at ok
  case isFalse => cases ok
  cases ok
  refine ⟨rfl, table, found, rfl, fun row member => ?_⟩
  unfold resolveAll at rows_ok
  obtain ⟨length, each⟩ := resolveAllFrom_ok _ 0 written full rows_ok
  obtain ⟨r, hr⟩ := List.getElem?_of_mem member
  have hlen : r < written.length := by
    have := (List.getElem?_eq_some_iff.mp hr).1; omega
  obtain ⟨value, hvalue, step⟩ := each r written[r] (List.getElem?_eq_getElem hlen)
  rw [hr] at hvalue
  cases hvalue
  exact ⟨positions, written[r], fullRow_rowWidth _ _ _ _ step⟩

end Belay.Sqlite
