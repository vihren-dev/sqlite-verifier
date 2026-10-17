import Belay.Sqlite.Resolution.ColumnSpec
import Belay.Sqlite.Resolution.ClockRows

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

/-- For all inputs, a successful {name}`fullCells` without a clock cell gives values that
satisfy {name}`RowWidth` for the values of the written cells. Proof sketch:
{name}`resolveAllFrom_ok` gives the length and the cell of each column, which is the
stored written value or the stored default; a time default would give a clock cell,
which the premise excludes. -/
theorem fullCells_rowWidth (columns : List CatalogColumn) (positions : List Nat)
    (written cells : List RowCell) (ok : fullCells columns positions written = .ok cells)
    (plain : ∀ cell ∈ cells, cell.2 = none) :
    RowWidth columns positions (written.map Prod.fst) (cells.map Prod.fst) := by
  unfold fullCells resolveAll at ok
  obtain ⟨length, each⟩ := resolveAllFrom_ok _ 0 columns cells ok
  refine ⟨by simpa using length, fun index h => ?_⟩
  obtain ⟨cell, hcell, step⟩ := each index columns[index] (List.getElem?_eq_getElem h)
  simp only [Nat.zero_add] at step
  constructor
  · intro k hk
    rw [hk] at step
    simp only at step
    cases step
    cases hw : written[k]? <;> simp [hcell, hw, List.getElem?_map]
  · intro hk
    rw [hk] at step
    simp only at step
    unfold omittedCell at step
    split at step
    · cases step
      exact absurd (plain _ (List.mem_of_getElem? hcell)) (by simp)
    · cases hdefault : defaultValue columns[index] with
      | error cause => rw [hdefault] at step; cases step
      | ok default =>
        rw [hdefault] at step
        cases step
        simp [hcell, Except.map, List.getElem?_map]

/-- For all columns and rows of cells: if they have no clock cells ({name}`clockCells`),
no cell of a row has a clock expression. -/
theorem clockCells_empty (columns : List CatalogColumn) (rows : List (List RowCell))
    (empty : (clockCells columns rows).isEmpty = true) : ∀ row ∈ rows, ∀ cell ∈ row, cell.2 = none := by
  intro row member cell inRow
  cases hclock : cell.2 with
  | none => rfl
  | some value =>
    obtain ⟨r, hr⟩ := List.getElem?_of_mem member
    obtain ⟨c, hc⟩ := List.getElem?_of_mem inRow
    have found : ({ row := r, column := c, value, affinity := (columns[c]?.map (·.affinity)).getD .blob } :
        Resolved.ClockCell) ∈ clockCells columns rows :=
      List.mem_flatMap.mpr ⟨(row, r), List.mem_zipIdx_iff_getElem?.mpr hr,
        List.mem_filterMap.mpr ⟨(cell, c), List.mem_zipIdx_iff_getElem?.mpr hc, by simp [hclock]⟩⟩
    simp only [List.isEmpty_iff] at empty
    simp [empty] at found

/-- For a successful resolution of INSERT, with any {lit}`ON CONFLICT` clauses, to an
insert statement, the catalog is
unchanged, the statement names the position of the table that the name finds and
carries that table's {name}`Catalog.uniqueKeys`, and for every resolved row there are table positions of the written columns and a
written row such that the resolved row satisfies {name}`RowWidth` for the table's
columns. So every resolved row has one value for each table column. Proof sketch:
split the resolver down to its successful branch; each row is a result of
{name}`fullCells` by {name}`resolveAllFrom_ok`, and {name}`fullCells_rowWidth` gives the rule. -/
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
  simp only [prepareError, restrict, issueResolution, withClockCells] at ok
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
  case isFalse => split at ok <;> cases ok
  split at ok
  case isFalse => cases ok
  rename_i empty
  cases ok
  refine ⟨rfl, table, found, rfl, fun row member => ?_⟩
  unfold resolveAll at rows_ok
  obtain ⟨cellRow, cellMember, rowEq⟩ := List.mem_map.mp member
  subst rowEq
  obtain ⟨length, each⟩ := resolveAllFrom_ok _ 0 written _ rows_ok
  obtain ⟨r, hr⟩ := List.getElem?_of_mem cellMember
  have hlen : r < written.length := by
    have := (List.getElem?_eq_some_iff.mp hr).1; omega
  obtain ⟨value, hvalue, step⟩ := each r written[r] (List.getElem?_eq_getElem hlen)
  rw [hr] at hvalue
  cases hvalue
  exact ⟨positions, written[r].map Prod.fst, fullCells_rowWidth _ _ _ _ step
    (clockCells_empty _ _ empty _ cellMember)⟩

end Belay.Sqlite
