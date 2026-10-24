import Belay.Sqlite.Model.QueryOutputs
import Belay.Sqlite.Model.QueryLaws

set_option doc.verso true

/-! What the output of a query says about the results that SQLite may give for it
({name}`Belay.Sqlite.Model.Output.ofResults`): the output has rows exactly when there is at least one
result and each result has a row, has no rows exactly when there is at least one result and each
result is empty, and is never an error. The surface states {lit}`Holds`, {lit}`Empty` and {lit}`Fails` with
these facts (ADR 0017, S4). -/

namespace Belay.Sqlite.Model

/-- For every list of results, the results of {name}`Output.ofResults` are the same results as
the list, once each and sorted: some list {lit}`listed` has exactly the members of {lit}`rs`, and
the output is {name}`Output.rows` for one result, {name}`Output.oneOf` for more, and
{name}`Output.unmodeled` for none. Proof sketch: sorting and removing repeats keep the members
({name}`Resolved.stableSort_perm`, {name}`List.mem_eraseDups`). -/
theorem Output.ofResults_listed (rs : List (List (List Value))) :
    ∃ listed : List (List (List Value)), (∀ x, x ∈ listed ↔ x ∈ rs) ∧
      Output.ofResults rs = match listed with
        | [result] => .rows result
        | [] => .unmodeled "the model gives no result for this query"
        | first :: second :: rest => .oneOf (first :: second :: rest) := by
  refine ⟨Resolved.stableSort (fun a b => (compareResults a b).isLE) rs.eraseDups, fun x => ?_, rfl⟩
  rw [(Resolved.stableSort_perm _ _).mem_iff, List.mem_eraseDups]

/-- For every list of results and every property of a result, lists with the same members agree
that there is a member and that each member has the property: the claim for {lit}`rs` is the claim
for {lit}`listed`. Proof sketch: the members are the same, so the two claims are the same. -/
theorem Output.listed_iff (rs listed : List (List (List Value))) (mem : ∀ x, x ∈ listed ↔ x ∈ rs)
    (property : List (List Value) → Prop) :
    (rs ≠ [] ∧ ∀ result ∈ rs, property result) ↔ (listed ≠ [] ∧ ∀ result ∈ listed, property result) := by
  have same : listed = [] ↔ rs = [] := by
    simp only [List.eq_nil_iff_forall_not_mem, mem]
  exact and_congr (not_congr same.symm) ⟨fun h r m => h r ((mem r).1 m), fun h r m => h r ((mem r).2 m)⟩

/-- For every list of results {lit}`rs`, {name}`Output.ofResults` of it has rows
({name}`Output.hasRows`) exactly when {lit}`rs` is not empty and no result in it is empty. With no
result, the output is {name}`Output.unmodeled`, which has no rows. Proof sketch: the output lists
the same results ({name}`Output.ofResults_listed`); one case for each shape of the list. -/
theorem Output.hasRows_ofResults (rs : List (List (List Value))) :
    (Output.ofResults rs).hasRows = true ↔ rs ≠ [] ∧ ∀ result ∈ rs, result ≠ [] := by
  obtain ⟨listed, mem, eq⟩ := Output.ofResults_listed rs
  rw [eq, Output.listed_iff rs listed mem]
  match listed with
  | [] => simp [Output.hasRows]
  | [result] => simp [Output.hasRows]
  | first :: second :: rest => simp [Output.hasRows]

/-- For every list of results {lit}`rs`, {name}`Output.ofResults` of it has no rows
({name}`Output.hasNoRows`) exactly when {lit}`rs` is not empty and every result in it is empty.
Proof sketch: as {name}`Output.hasRows_ofResults`. -/
theorem Output.hasNoRows_ofResults (rs : List (List (List Value))) :
    (Output.ofResults rs).hasNoRows = true ↔ rs ≠ [] ∧ ∀ result ∈ rs, result = [] := by
  obtain ⟨listed, mem, eq⟩ := Output.ofResults_listed rs
  rw [eq, Output.listed_iff rs listed mem]
  match listed with
  | [] => simp [Output.hasNoRows]
  | [result] => simp [Output.hasNoRows]
  | first :: second :: rest => simp [Output.hasNoRows]

/-- For every list of results, {name}`Output.ofResults` of it is no error ({name}`Output.isError`
is false). Proof sketch: it is rows, a choice of results, or unmodeled. -/
theorem Output.isError_ofResults (rs : List (List (List Value))) : (Output.ofResults rs).isError = false := by
  obtain ⟨listed, mem, eq⟩ := Output.ofResults_listed rs
  rw [eq]
  match listed with
  | [] => simp [Output.isError]
  | [result] => simp [Output.isError]
  | first :: second :: rest => simp [Output.isError]

end Belay.Sqlite.Model
